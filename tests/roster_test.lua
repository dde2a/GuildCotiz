-- Reconciliation du roster : detection des departs, protection contre un roster
-- partiel, et purge des anciens membres.
local H = dofile((arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/harness.lua")
local NewClient, AddDeposit = H.NewClient, H.AddDeposit
local check, NOW, DAY = H.check, H.NOW, H.DAY

local GUILD = { "Karn", "Lyra", "Muran", "Sedra", "Zeda" }

local function Names(list)
  local out = {}
  for _, entry in ipairs(list) do out[#out + 1] = entry.name end
  table.sort(out)
  return table.concat(out, ",")
end

local function VisibleNames(client, opts)
  local out = {}
  for _, entry in ipairs(client.ns.GetSortedMembers(client.g, opts or { includeInactive = true })) do
    out[#out + 1] = entry.name
  end
  table.sort(out)
  return table.concat(out, ",")
end

print("== Scenario 1 : un depart est detecte sur un roster complet ==")
local o = NewClient("Officier")
o.SetRoster(GUILD)
o.ns.ScanRoster()
check("tout le monde est actif au depart", VisibleNames(o) == "Karn,Lyra,Muran,Sedra,Zeda")

-- Nettoyage de guilde : Muran et Zeda sont exclus.
o.SetRoster({ "Karn", "Lyra", "Sedra" })
local complete, departures, returns = o.ns.ScanRoster()
check("roster reconnu complet", complete == true)
check("2 departs detectes", departures == 2, "(obtenu " .. tostring(departures) .. ")")
check("aucun retour", returns == 0)
check("les partis sortent du tableau", VisibleNames(o) == "Karn,Lyra,Sedra",
  "(obtenu " .. VisibleNames(o) .. ")")
check("les partis restent en base", Names(o.ns.GetFormerMembers(o.g)) == "Muran,Zeda")
check("leftAt est horodate", (o.g.members.Muran.leftAt or 0) > 0)

print("== Scenario 2 : un rescan ne redeclenche pas les memes departs ==")
local _, again = o.ns.ScanRoster()
check("aucun nouveau depart", again == 0, "(obtenu " .. tostring(again) .. ")")

print("== Scenario 3 : reglage d'affichage des anciens membres ==")
o.env.GuildCotizDB.settings.showFormerMembers = true
check("les anciens reapparaissent", VisibleNames(o) == "Karn,Lyra,Muran,Sedra,Zeda",
  "(obtenu " .. VisibleNames(o) .. ")")
o.env.GuildCotizDB.settings.showFormerMembers = false
check("et se remasquent", VisibleNames(o) == "Karn,Lyra,Sedra")
check("includeFormer force l'affichage",
  VisibleNames(o, { includeInactive = true, includeFormer = true })
    == "Karn,Lyra,Muran,Sedra,Zeda")

print("== Scenario 4 : roster partiel, aucun depart applique ==")
-- Le cas dangereux : le serveur annonce 5 membres mais n'en indexe que 2
-- (affichage des hors-ligne coupe). Conclure au depart viderait la guilde.
local p = NewClient("Prudent")
p.SetRoster(GUILD)
p.ns.ScanRoster()
p.SetRoster(GUILD, 2)
local partialComplete, partialDepartures = p.ns.ScanRoster()
check("roster reconnu incomplet", partialComplete == false)
check("aucun depart applique", partialDepartures == 0,
  "(obtenu " .. tostring(partialDepartures) .. ")")
check("personne n'a disparu du tableau", VisibleNames(p) == "Karn,Lyra,Muran,Sedra,Zeda",
  "(obtenu " .. VisibleNames(p) .. ")")
check("aucun ancien membre enregistre", #p.ns.GetFormerMembers(p.g) == 0)

print("== Scenario 5 : un retour dans la guilde annule le depart ==")
o.SetRoster({ "Karn", "Lyra", "Sedra", "Zeda" })
local _, dep, ret = o.ns.ScanRoster()
check("un retour detecte", ret == 1, "(obtenu " .. tostring(ret) .. ")")
check("aucun nouveau depart", dep == 0)
check("Zeda est de retour dans le tableau", VisibleNames(o) == "Karn,Lyra,Sedra,Zeda")
check("Zeda n'est plus un ancien membre", Names(o.ns.GetFormerMembers(o.g)) == "Muran")

print("== Scenario 6 : purge, l'historique comptable est protege ==")
local q = NewClient("Purge")
q.SetRoster({ "Karn", "Lyra", "Muran", "Sedra" })
q.ns.ScanRoster()
AddDeposit(q, "Muran", 1500, NOW - 3 * DAY)   -- Muran a cotise
q.ns.SetRaids(q.g, q.ns.WeekMonday(NOW - 3 * DAY), "Muran", 2)
q.ns.SetRaids(q.g, q.ns.WeekMonday(NOW - 3 * DAY), "Sedra", 1)
q.g.altToMain["Sedra"] = "Muran"              -- Sedra est un reroll de Muran
q.SetRoster({ "Karn", "Lyra" })               -- Muran et Sedra quittent
q.ns.ScanRoster()

local removed = q.ns.PurgeFormerMembers(q.g, true)
check("seul l'ancien sans depot est purge", removed == 1, "(obtenu " .. tostring(removed) .. ")")
check("Muran est conserve car il a depose", q.g.members.Muran ~= nil)
check("Sedra est supprime", q.g.members.Sedra == nil)
check("le lien reroll de Sedra est nettoye", q.g.altToMain["Sedra"] == nil)
check("les raids de Sedra sont nettoyes",
  q.ns.GetRaids(q.g, q.ns.WeekMonday(NOW - 3 * DAY), "Sedra") == 0)
check("les raids de Muran sont intacts",
  q.ns.GetRaids(q.g, q.ns.WeekMonday(NOW - 3 * DAY), "Muran") == 2)

local removedAll = q.ns.PurgeFormerMembers(q.g, false)
check("purge all supprime aussi Muran", removedAll == 1 and q.g.members.Muran == nil)
check("les membres actifs sont intacts", q.g.members.Karn ~= nil and q.g.members.Lyra ~= nil)

print("== Scenario 7 : un membre actif n'est jamais purgeable ==")
check("PurgeFormerMember refuse un actif", q.ns.PurgeFormerMember(q.g, "Karn") == false)
check("Karn est toujours la", q.g.members.Karn ~= nil)

os.exit(H.report())
