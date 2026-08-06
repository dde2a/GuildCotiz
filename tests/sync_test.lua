-- Synchronisation des transactions entre officiers.
local H = dofile((arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/harness.lua")
local NewClient, Pump, ResetNetwork, Join = H.NewClient, H.Pump, H.ResetNetwork, H.Join
local AddDeposit, AddWithdrawal, Snapshot = H.AddDeposit, H.AddWithdrawal, H.Snapshot
local check, net, NOW, DAY = H.check, H.net, H.NOW, H.DAY



print("== Scenario 1 : deux journaux partiels convergent ==")
local a = NewClient("Alice")
local b = NewClient("Bob")

-- Depots vus par les deux, mais horodates differemment (decalage < 1h, ce que
-- produit reellement la troncature horaire de WoW).
AddDeposit(a, "Karn",  1000, NOW - 3 * DAY)
AddDeposit(b, "Karn",  1000, NOW - 3 * DAY + 2400)   -- meme depot, +40 min
AddDeposit(a, "Lyra",  2000, NOW - 5 * DAY)
AddDeposit(b, "Lyra",  2000, NOW - 5 * DAY - 1800)   -- meme depot, -30 min

-- Depots vus par un seul officier.
AddDeposit(a, "Muran", 1500, NOW - 2 * DAY)
AddDeposit(a, "Karn",  1000, NOW - 9 * DAY)
AddDeposit(b, "Sedra",  500, NOW - 4 * DAY)
AddWithdrawal(b, "Officier", 3000, NOW - 6 * DAY)

local _, beforeA = Snapshot(a)
local _, beforeB = Snapshot(b)
print(string.format("  Alice %d transactions / Bob %d avant sync", beforeA, beforeB))

a.ns.Sync.Broadcast(true)
local rounds = Pump()

local snapA, countA = Snapshot(a)
local snapB, countB = Snapshot(b)
print(string.format("  Alice %d / Bob %d apres sync (%d rounds, %d messages, payload max %d o)",
  countA, countB, rounds, net.sent, net.maxPayload))

check("les deux officiers convergent", snapA == snapB)
check("les depots vus deux fois ne sont pas dupliques", countA == 6,
  string.format("(attendu 6, obtenu %d)", countA))

print("== Scenario 2 : rejouer la sync ne change rien (idempotence) ==")
net.sent = 0
b.ns.Sync.Broadcast(true)
Pump()
a.ns.Sync.Broadcast(true)
Pump()
local snapA2 = Snapshot(a)
local snapB2 = Snapshot(b)
check("Alice inchangee", snapA2 == snapA)
check("Bob inchange", snapB2 == snapB)

ResetNetwork()
print("== Scenario 3 : un troisieme officier arrive vierge ==")
Join(a); Join(b)
local c = NewClient("Cyra")
c.ns.Sync.Broadcast(true)
Pump()
local snapC, countC = Snapshot(c)
check("Cyra recupere tout l'historique recent", countC == countA,
  string.format("(attendu %d, obtenu %d)", countA, countC))
check("Cyra identique aux autres", snapC == snapA)

ResetNetwork()
print("== Scenario 4 : l'ordre d'arrivee est indifferent ==")
local d1 = NewClient("Dorn")
AddDeposit(d1, "Karn", 1000, NOW - 3 * DAY)
AddDeposit(d1, "Zeda", 700, NOW - DAY)
local payload = {}
for _, name in ipairs({ "Sedra", "Muran", "Lyra" }) do
  payload[#payload + 1] = { n = name, a = 800 * 10000, t = NOW - 2 * DAY }
end
d1.ns.Sync.MergeTransactions(d1.g, payload)
local forward = Snapshot(d1)

local d2 = NewClient("Dorn2")
AddDeposit(d2, "Zeda", 700, NOW - DAY)
AddDeposit(d2, "Karn", 1000, NOW - 3 * DAY)
local reversed = {}
for i = #payload, 1, -1 do reversed[#reversed + 1] = payload[i] end
d2.ns.Sync.MergeTransactions(d2.g, reversed)
local backward = Snapshot(d2)
check("fusion commutative", forward == backward)

ResetNetwork()
print("== Scenario 5 : donnees invalides rejetees ==")
local e = NewClient("Eryn")
local before = select(2, Snapshot(e))
local hostile = {
  { n = "Bad", a = -5000, t = NOW - DAY },                     -- montant negatif
  { n = "Bad", a = 1e15, t = NOW - DAY },                      -- montant aberrant
  { n = "Bad", a = 1000, t = NOW + 10 * DAY },                 -- dans le futur
  { n = "Bad", a = 1000, t = 42 },                             -- horodatage absurde
  { n = 12345, a = 1000, t = NOW - DAY },                      -- nom non textuel
  { n = "Bad", a = 1000, t = NOW - DAY, k = "notARealType" },  -- type inconnu
  { n = "X",   a = 1000, t = NOW - DAY },                      -- nom trop court
  "pas une table",
}
local addedD, addedW = e.ns.Sync.MergeTransactions(e.g, hostile)
check("toutes les entrees invalides sont ignorees", addedD == 0 and addedW == 0,
  string.format("(ajoutes : %d depots, %d retraits)", addedD, addedW))
check("base inchangee", select(2, Snapshot(e)) == before)

ResetNetwork()
print("== Scenario 6 : transactions trop anciennes non partagees ==")
local f1 = NewClient("Fian")
local f2 = NewClient("Gorm")
AddDeposit(f1, "Ancien", 9999, NOW - 200 * DAY)  -- au-dela de MAX_AGE
AddDeposit(f1, "Recent", 111, NOW - 3 * DAY)
f1.ns.Sync.Broadcast(true)
Pump()
local _, countF2 = Snapshot(f2)
check("seul le recent traverse", countF2 == 1, string.format("(obtenu %d)", countF2))

ResetNetwork()
print("== Scenario 7 : sync desactivee ==")
local h = NewClient("Hilda")
h.env.GuildCotizDB.settings.syncEnabled = false
AddDeposit(h, "Secret", 100, NOW - DAY)
net.sent = 0
h.ns.Sync.Broadcast(true)
check("aucun message emis", net.sent == 0, string.format("(emis %d)", net.sent))

ResetNetwork()
print("== Scenario 8 : volume d'une vraie guilde ==")
-- 40 joueurs, 4 semaines de depots, plus les retraits d'officiers : le pire cas
-- realiste est le premier echange avec un officier qui part de zero.
local vet = NewClient("Veteran")
local fresh = NewClient("Bleu")
for p = 1, 40 do
  for w = 0, 3 do
    AddDeposit(vet, "Joueur" .. p, 500 + (p % 7) * 250, NOW - (w * 7 + (p % 5)) * DAY)
  end
end
for w = 0, 3 do
  AddWithdrawal(vet, "Officier", 5000, NOW - (w * 7 + 2) * DAY)
end
local _, volume = Snapshot(vet)
net.maxPayload = 0
net.sent = 0
vet.ns.Sync.Broadcast(true)
Pump()
local _, got = Snapshot(fresh)
check("l'officier vierge recoit tout", got == volume,
  string.format("(attendu %d, obtenu %d)", volume, got))
-- ChatThrottleLib plafonne le debit sortant a environ 800 o/s en priorite BULK.
print(string.format("  %d transactions | %d messages | payload max %d o | ~%.1f s d'emission",
  volume, net.sent, net.maxPayload, net.maxPayload / 800))
print(string.format("  soit %d chunks AceComm de 255 o", math.ceil(net.maxPayload / 255)))

os.exit(H.report())
