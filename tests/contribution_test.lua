-- Comptage des cotisations : ce que l'addon retient du journal d'or.
--
-- Le piege central : WoW n'expose l'anciennete d'une transaction qu'en unites
-- entieres, la plus fine etant l'heure. Deux depots identiques faits dans la
-- meme heure par le meme joueur sont donc indiscernables par leur contenu. Seul
-- le NOMBRE de lignes du journal les distingue d'un unique depot relu deux fois.
local H = dofile((arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/harness.lua")
local NewClient, Pump, ResetNetwork = H.NewClient, H.Pump, H.ResetNetwork
local check, NOW, DAY = H.check, H.NOW, H.DAY

local function Deposits(client, player)
  local m = client.g.members[player]
  return m and #(m.deposits or {}) or 0
end

local function Total(client, player)
  local m = client.g.members[player]
  if not m then return 0 end
  local sum = 0
  for _, d in ipairs(m.deposits or {}) do sum = sum + d.a end
  return sum / 10000
end

print("== Scenario 1 : deux depots identiques le meme jour ==")
local o = NewClient("Officier")
o.SetBankLog({
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 2 },
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 2 },
})
o.ns.ScanBankLog()
check("les deux depots sont comptes", Deposits(o, "Karn") == 2,
  string.format("(obtenu %d)", Deposits(o, "Karn")))
check("le total est de 40000 po", Total(o, "Karn") == 40000,
  string.format("(obtenu %d)", Total(o, "Karn")))

print("== Scenario 2 : re-scanner le meme journal n'invente rien ==")
o.ns.ScanBankLog()
o.ns.ScanBankLog()
check("toujours deux depots", Deposits(o, "Karn") == 2,
  string.format("(obtenu %d)", Deposits(o, "Karn")))

print("== Scenario 3 : un troisieme depot identique apparait ==")
o.SetBankLog({
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 2 },
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 2 },
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 1 },
})
o.ns.ScanBankLog()
check("le troisieme est ajoute", Deposits(o, "Karn") == 3,
  string.format("(obtenu %d)", Deposits(o, "Karn")))
check("le total est de 60000 po", Total(o, "Karn") == 60000,
  string.format("(obtenu %d)", Total(o, "Karn")))

print("== Scenario 4 : montants et joueurs distincts ==")
local p = NewClient("Officier2")
p.SetBankLog({
  { kind = "deposit", name = "Lyra",  gold = 5000, hoursAgo = 3 },
  { kind = "deposit", name = "Lyra",  gold = 7000, hoursAgo = 3 },
  { kind = "deposit", name = "Muran", gold = 5000, hoursAgo = 3 },
  { kind = "withdraw", name = "Sedra", gold = 1000, hoursAgo = 4 },
  { kind = "withdraw", name = "Sedra", gold = 1000, hoursAgo = 4 },
})
p.ns.ScanBankLog()
check("Lyra a deux depots distincts", Deposits(p, "Lyra") == 2)
check("Muran a son depot", Deposits(p, "Muran") == 1)
check("les deux retraits identiques sont comptes",
  #(p.g.members.Sedra.withdrawals or {}) == 2,
  string.format("(obtenu %d)", #(p.g.members.Sedra.withdrawals or {})))

print("== Scenario 5 : la sync preserve la multiplicite ==")
ResetNetwork()
local a = NewClient("Alice")
local b = NewClient("Bob")
a.SetBankLog({
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 2 },
  { kind = "deposit", name = "Karn", gold = 20000, hoursAgo = 2 },
})
a.ns.ScanBankLog()
check("Alice a bien deux depots", Deposits(a, "Karn") == 2,
  string.format("(obtenu %d)", Deposits(a, "Karn")))
a.ns.Sync.Broadcast(true)
Pump()
check("Bob recoit les deux depots", Deposits(b, "Karn") == 2,
  string.format("(obtenu %d)", Deposits(b, "Karn")))
check("Bob totalise 40000 po", Total(b, "Karn") == 40000,
  string.format("(obtenu %d)", Total(b, "Karn")))

print("== Scenario 6 : re-synchroniser n'ajoute pas de doublon ==")
b.ns.Sync.Broadcast(true)
Pump()
a.ns.Sync.Broadcast(true)
Pump()
check("Alice reste a deux", Deposits(a, "Karn") == 2,
  string.format("(obtenu %d)", Deposits(a, "Karn")))
check("Bob reste a deux", Deposits(b, "Karn") == 2,
  string.format("(obtenu %d)", Deposits(b, "Karn")))

print("== Scenario 7 : /cotiz fix ne detruit pas de vrais depots ==")
local removed = o.ns.Deduplicate()
check("aucun depot legitime supprime", Deposits(o, "Karn") == 3,
  string.format("(obtenu %d, %d supprime(s))", Deposits(o, "Karn"), removed))

print("== Scenario 8 : une nouvelle saison ne refacture pas les anciens raids ==")
local s = NewClient("Saisons")
s.SetRoster({ "Karn" })
s.ns.ScanRoster()
local oldWeek = s.ns.WeekMonday(NOW - 60 * DAY)
local seasonStart = NOW - 3 * DAY
local currentWeek = s.ns.WeekMonday(NOW - 2 * DAY)
s.ns.SetRaids(s.g, oldWeek, "Karn", 10)
s.ns.SetRaids(s.g, currentWeek, "Karn", 4)
s.g.config.seasonStart = seasonStart
s.g.members.Karn.startOverride = NOW - 120 * DAY -- ancienne date individuelle S1
s.g.config.raidAmount = 500 * 10000
local status = s.ns.GetMemberStatus(s.g, s.g.members.Karn, "Karn", NOW)
check("seuls les 4 raids de la nouvelle saison comptent", status.raids == 4,
  string.format("(obtenu %d)", status.raids))
check("le nouveau tarif produit 2000 po dus", status.owed == 2000 * 10000,
  string.format("(obtenu %.0f po)", status.owed / 10000))
check("une ancienne date individuelle ne depasse pas la borne de saison",
  status.startT == seasonStart)
check("le total historique reste disponible explicitement",
  s.ns.TotalRaids(s.g, "Karn", NOW) == 14)

os.exit(H.report())
