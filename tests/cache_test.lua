-- Caches derives : normalisation des saisons et index des groupes main/reroll.
--
-- Ces deux caches evitent de rebalayer toute la guilde a chaque lecture, mais
-- ils portent un risque comptable precis : conserve trop longtemps, le debut de
-- suivi ne recule plus vers une activite plus ancienne, et les depots anterieurs
-- sortent silencieusement des totaux. Chaque chemin d'ecriture est donc verifie
-- ici avec un cache deja chaud.
local H = dofile((arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/harness.lua")
local NewClient, check, NOW, DAY = H.NewClient, H.check, H.NOW, H.DAY

local function Names(list)
  local out = {}
  for _, entry in ipairs(list) do out[#out + 1] = entry.name end
  return table.concat(out, ",")
end

print("== Scenario 1 : un depot plus ancien que la premiere saison recule le suivi ==")
local o = NewClient("Officier")
o.ns.SetRatePeriod(o.g, NOW - 10 * DAY, 500 * 10000, "S1")
local before = o.ns.TrackingStart(o.g)   -- chauffe le cache de normalisation
check("le suivi part de la saison declaree", before == NOW - 10 * DAY)

o.SetBankLog({ { kind = "deposit", name = "Karn", gold = 3000, daysAgo = 100 } })
o.ns.ScanBankLog()
local after = o.ns.TrackingStart(o.g)
check("le suivi a recule jusqu'au depot", after < before,
  string.format("(avant %d, apres %d)", before, after))
check("le depot ancien est compte", o.ns.TotalPaid(o.g, o.g.members["Karn"]) == 3000 * 10000,
  string.format("(obtenu %d)", o.ns.TotalPaid(o.g, o.g.members["Karn"])))

print("== Scenario 2 : une correction manuelle ancienne recule aussi le suivi ==")
local c2 = NewClient("Officier2")
c2.ns.SetRatePeriod(c2.g, NOW - 10 * DAY, 500 * 10000, "S1")
local m2 = c2.ns.EnsureMember(c2.g, "Zeda")
local ref2 = c2.ns.TrackingStart(c2.g)
local oldWeek = c2.ns.WeekMonday(NOW - 200 * DAY)
c2.ns.SetDepositOverride(m2, oldWeek, 900 * 10000)
check("le suivi couvre la semaine corrigee", c2.ns.TrackingStart(c2.g) <= oldWeek,
  string.format("(suivi %d, semaine %d, avant %d)", c2.ns.TrackingStart(c2.g), oldWeek, ref2))
check("la correction est comptee", c2.ns.TotalPaid(c2.g, m2) == 900 * 10000,
  string.format("(obtenu %d)", c2.ns.TotalPaid(c2.g, m2)))

print("== Scenario 3 : une presence saisie sur une semaine ancienne recule le suivi ==")
local c3 = NewClient("Officier3")
c3.ns.SetRatePeriod(c3.g, NOW - 10 * DAY, 500 * 10000, "S1")
c3.ns.EnsureMember(c3.g, "Muran")
c3.ns.TrackingStart(c3.g)
local oldRaidWeek = c3.ns.WeekMonday(NOW - 300 * DAY)
c3.ns.SetRaids(c3.g, oldRaidWeek, "Muran", 2)
check("le suivi couvre la semaine de raid", c3.ns.TrackingStart(c3.g) <= oldRaidWeek,
  string.format("(suivi %d, semaine %d)", c3.ns.TrackingStart(c3.g), oldRaidWeek))
check("les deux raids sont dus", c3.ns.TotalOwed(c3.g, "Muran", NOW,
  c3.ns.TrackingStart(c3.g)) == 2 * 500 * 10000,
  string.format("(obtenu %d)", c3.ns.TotalOwed(c3.g, "Muran", NOW, c3.ns.TrackingStart(c3.g))))

print("== Scenario 4 : l'index des groupes suit les ecritures ==")
local c4 = NewClient("Officier4")
for _, n in ipairs({ "Muran", "Alia", "Sedra", "Bardu" }) do c4.ns.EnsureMember(c4.g, n) end
check("un membre isole est seul dans son groupe",
  Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) == "Muran",
  "(obtenu " .. Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) .. ")")

c4.ns.SetCharacterMain(c4.g, "Sedra", "Muran")
c4.ns.SetCharacterMain(c4.g, "Alia", "Muran")
check("le lien est visible immediatement",
  Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) == "Muran,Alia,Sedra",
  "(obtenu " .. Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) .. ")")
check("le main reste en tete, les rerolls par ordre alphabetique",
  c4.ns.GetLinkedCharacters(c4.g, "Muran")[1].isMain == true)
check("le groupe se retrouve depuis un reroll",
  Names(c4.ns.GetLinkedCharacters(c4.g, "Sedra")) == "Muran,Alia,Sedra")
check("le nombre de rerolls suit", c4.ns.GetAltCount(c4.g, "Muran") == 2,
  string.format("(obtenu %d)", c4.ns.GetAltCount(c4.g, "Muran")))

c4.ns.SetCharacterMain(c4.g, "Alia", nil)
check("le detachement est visible immediatement",
  Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) == "Muran,Sedra",
  "(obtenu " .. Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) .. ")")

c4.ns.EnsureMember(c4.g, "Nova")
c4.ns.SetCharacterMain(c4.g, "Nova", "Muran")
check("un membre cree apres coup rejoint son groupe",
  Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) == "Muran,Nova,Sedra",
  "(obtenu " .. Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) .. ")")

c4.g.members["Sedra"].leftAt = NOW - DAY
c4.ns.PurgeFormerMember(c4.g, "Sedra")
check("un membre purge disparait du groupe",
  Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) == "Muran,Nova",
  "(obtenu " .. Names(c4.ns.GetLinkedCharacters(c4.g, "Muran")) .. ")")

print("== Scenario 5 : l'interface n'est rafraichie que sur un vrai changement ==")
local c5 = NewClient("Officier5")
local refreshes = 0
c5.ns.RefreshUI = function() refreshes = refreshes + 1 end

c5.SetBankLog({ { kind = "deposit", name = "Karn", gold = 5000, daysAgo = 2 } })
c5.ns.ScanBankLog()
check("un journal qui apporte du neuf rafraichit", refreshes == 1,
  string.format("(obtenu %d)", refreshes))
c5.ns.ScanBankLog()
c5.ns.ScanBankLog()
check("relire le meme journal ne rafraichit plus", refreshes == 1,
  string.format("(obtenu %d)", refreshes))

c5.SetBankLog({
  { kind = "deposit", name = "Karn", gold = 5000, daysAgo = 2 },
  { kind = "deposit", name = "Alia", gold = 1000, daysAgo = 1 },
})
c5.ns.ScanBankLog()
check("un nouveau depot rafraichit a nouveau", refreshes == 2,
  string.format("(obtenu %d)", refreshes))

refreshes = 0
c5.SetRoster({ "Karn", "Alia" })
c5.ns.ScanRoster()
check("un roster qui change rafraichit", refreshes == 1,
  string.format("(obtenu %d)", refreshes))
c5.ns.ScanRoster()
c5.ns.ScanRoster()
check("un roster identique ne rafraichit plus", refreshes == 1,
  string.format("(obtenu %d)", refreshes))
c5.SetRoster({ "Karn", "Alia", "Muran" })
c5.ns.ScanRoster()
check("un nouvel arrivant rafraichit", refreshes == 2,
  string.format("(obtenu %d)", refreshes))

print("== Scenario 6 : le cout d'un rafraichissement reste lineaire ==")
local c6 = NewClient("Officier6")
local MEMBERS, WEEKS = 60, 12
c6.ns.SetRatePeriod(c6.g, NOW - WEEKS * 7 * DAY, 500 * 10000, "S1")
local names = {}
for i = 1, MEMBERS do
  local n = string.format("Joueur%02d", i)
  names[i] = n
  local m = c6.ns.EnsureMember(c6.g, n)
  m.active = true
  m.deposits[#m.deposits + 1] = { t = NOW - 3 * DAY, a = 500 * 10000 }
end
for w = 1, WEEKS do
  local ws = c6.ns.WeekMonday(NOW - w * 7 * DAY)
  for i = 1, MEMBERS do c6.ns.SetRaids(c6.g, ws, names[i], 1) end
end

-- ResolveMain etait rappele pour chaque membre a chaque recherche de groupe,
-- soit un cout en carre du nombre de membres. L'index le ramene a un nombre
-- d'appels proportionnel au nombre de membres affiches.
local resolveCalls = 0
local realResolveMain = c6.ns.ResolveMain
c6.ns.ResolveMain = function(...)
  resolveCalls = resolveCalls + 1
  return realResolveMain(...)
end

local week = c6.ns.WeekMonday(NOW)
for _, entry in ipairs(c6.ns.GetSortedMembers(c6.g, { includeInactive = true })) do
  if not c6.ns.IsAlt(c6.g, entry.name) then
    c6.ns.GetMemberStatus(c6.g, entry.m, entry.name, NOW)
    c6.ns.GetGroupDepositsForWeek(c6.g, entry.name, week, NOW)
    c6.ns.GetAltCount(c6.g, entry.name)
  end
end
c6.ns.ResolveMain = realResolveMain

local quadratic = 5 * MEMBERS * MEMBERS
check("le rafraichissement ne balaie plus la guilde par membre",
  resolveCalls < 15 * MEMBERS,
  string.format("(obtenu %d appels, quadratique ~%d, plafond %d)",
    resolveCalls, quadratic, 15 * MEMBERS))

os.exit(H.report())
