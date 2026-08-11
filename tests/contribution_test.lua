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

print("== Scenario 8 : le tarif change mais le solde reste continu entre saisons ==")
local s = NewClient("Saisons")
s.SetRoster({ "Karn" })
s.ns.ScanRoster()
local oldWeek = s.ns.WeekMonday(NOW - 60 * DAY)
local currentWeek = s.ns.WeekMonday(NOW - 2 * DAY)
local seasonStart = currentWeek
s.g.config.ratePeriods = {}
s.g.config.ratePeriodsMigrated = true
s.g.config.seasonStart = oldWeek
s.g.config.raidAmount = 1000 * 10000
s.ns.SetRatePeriod(s.g, oldWeek, 1000 * 10000)
s.ns.SetRaids(s.g, oldWeek, "Karn", 10)
s.ns.SetRaids(s.g, currentWeek, "Karn", 4)
s.ns.SetRatePeriod(s.g, seasonStart, 500 * 10000)
s.g.members.Karn.startOverride = NOW - 120 * DAY -- ancienne date individuelle S1
s.g.members.Karn.deposits = { { t = oldWeek + DAY, a = 15000 * 10000 } }
local status = s.ns.GetMemberStatus(s.g, s.g.members.Karn, "Karn", NOW)
check("les 14 raids des deux saisons restent visibles", status.raids == 14,
  string.format("(obtenu %d)", status.raids))
check("chaque saison conserve son tarif", status.owed == 12000 * 10000,
  string.format("(obtenu %.0f po)", status.owed / 10000))
check("le credit S1 est encore disponible en S2", status.balance == 3000 * 10000,
  string.format("(obtenu %.0f po)", status.balance / 10000))
check("l'avance est calculee depuis le solde au tarif S2", status.raidsAhead == 6,
  string.format("(obtenu %d raid(s))", status.raidsAhead))
local individualStatus = s.ns.GetIndividualStatus(s.g, s.g.members.Karn, "Karn", NOW)
check("le statut individuel utilise aussi le solde", individualStatus.raidsAhead == 6,
  string.format("(obtenu %d raid(s))", individualStatus.raidsAhead))
check("le debut de suivi reste celui de la premiere saison", status.startT == oldWeek)
local seasonalRows = s.ns.GetWeeklyBreakdown(s.g, s.g.members.Karn, "Karn", NOW)
check("l'historique commence en S1", seasonalRows[1] and seasonalRows[1].weekStart == oldWeek)

local boundary = NewClient("DateEffet")
boundary.SetRoster({ "Karn" })
boundary.ns.ScanRoster()
local beforeWeek = boundary.ns.WeekMonday(NOW - 14 * DAY)
local effectiveWednesday = beforeWeek + 2 * DAY
local afterWeek = beforeWeek + 7 * DAY
boundary.g.config.ratePeriods = {}
boundary.g.config.ratePeriodsMigrated = true
boundary.ns.SetRatePeriod(boundary.g, beforeWeek - 30 * DAY, 1000 * 10000)
boundary.ns.SetRatePeriod(boundary.g, effectiveWednesday, 500 * 10000)
check("la semaine contenant la date d'effet reste a 1000 po",
  boundary.ns.RaidAmountAt(boundary.g, beforeWeek) == 1000 * 10000)
check("la semaine suivante passe a 500 po",
  boundary.ns.RaidAmountAt(boundary.g, afterWeek) == 500 * 10000)

print("== Scenario 9 : un depot anterieur au premier raid reste dans le solde ==")
local m = NewClient("Migration")
m.SetRoster({ "Karn" })
m.ns.ScanRoster()
local earlyDeposit = NOW - 90 * DAY
local oldProfileStart = NOW - 70 * DAY
m.g.members.Karn.deposits = { { t = earlyDeposit, a = 20000 * 10000 } }
m.g.config.ratePeriods = {}
m.g.config.ratePeriodsMigrated = false
m.g.config.seasonStart = seasonStart
m.g.config.raidAmount = 500 * 10000
m.env.GuildCotizDB.profiles = {
  Default = {
    guild = "TestGuild-TestRealm",
    config = { seasonStart = tostring(oldProfileStart), raidAmount = tostring(1000 * 10000) },
  },
}
local migrated = m.ns.EnsureRatePeriods(m.g)
check("la migration remonte au premier depot", migrated[1] and migrated[1].start == earlyDeposit)
check("le tarif S1 est recupere du profil", migrated[1] and migrated[1].amount == 1000 * 10000)
check("le depot ancien reste dans le total", m.ns.TotalPaid(m.g, m.g.members.Karn, NOW) == 20000 * 10000)

os.exit(H.report())
