-- Banc d'essai hors WoW : deux officiers, une meme guilde, des journaux partiels.
-- Objectif : verifier convergence, idempotence, independance a l'ordre, et rejet
-- des donnees invalides.

-- Lancement : lua5.1 tests/sync_test.lua (depuis la racine du depot)
local REPO = (arg and arg[0] or ""):match("^(.*)tests[/\\][^/\\]+$") or "./"

-- Libs reelles, chargees une fois et partagees (elles sont sans etat).
local libs = {}
_G.LibStub = setmetatable({}, {
  __call = function(_, name) return libs[name] end,
})
function LibStub:NewLibrary(name, minor)
  libs[name] = libs[name] or {}
  return libs[name], minor
end
function LibStub:GetLibrary(name, silent) return libs[name] end
dofile(REPO .. "Libs/LibSerialize/LibSerialize.lua")
dofile(REPO .. "Libs/LibDeflate/LibDeflate.lua")

-- Reseau simule : file de messages { from, distribution, target, text }
local net = { queue = {}, clients = {}, sent = 0, maxPayload = 0 }

libs["AceComm-3.0"] = {
  RegisterComm = function(self, prefix, handler) self.handler = handler end,
  SendCommMessage = function(self, prefix, text, distribution, target)
    net.sent = net.sent + 1
    if #text > net.maxPayload then net.maxPayload = #text end
    table.insert(net.queue, {
      from = self.owner, prefix = prefix, text = text,
      distribution = distribution, target = target,
    })
  end,
}

--------------------------------------------------------------------------------

local function DummyFrame()
  local f = {}
  setmetatable(f, { __index = function() return function() return f end end })
  return f
end

local function NewClient(charName)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.GuildCotizDB = nil

  env.time = os.time   -- WoW expose time/date en globales
  env.date = os.date
  env.print = function() end
  env.CopyTable = function(t)
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and env.CopyTable(v) or v end
    return out
  end
  env.CreateFrame = function() return DummyFrame() end
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return "TestGuild", nil, nil, "TestRealm" end
  env.GetRealmName = function() return "TestRealm" end
  env.GetNormalizedRealmName = function() return "TestRealm" end
  env.UnitName = function() return charName end
  env.BreakUpLargeNumbers = tostring
  env.GetLocale = function() return "enUS" end
  env.C_GuildInfo = {}
  env.C_Timer = { After = function(_, fn) fn() end }
  env.MAX_GUILDBANK_TABS = 8
  env.QueryGuildBankLog = function() end

  -- Chaque client a sa propre instance d'AceComm pour garder son handler.
  local comm = {
    owner = charName,
    RegisterComm = function(self, prefix, handler) self.handler = handler end,
    SendCommMessage = libs["AceComm-3.0"].SendCommMessage,
  }
  env.LibStub = setmetatable({}, {
    __call = function(_, name)
      if name == "AceComm-3.0" then return comm end
      return libs[name]
    end,
  })

  local ns = {}
  for _, file in ipairs({ "Locale.lua", "Core.lua", "Sync.lua" }) do
    local chunk = assert(loadfile(REPO .. file))
    setfenv(chunk, env)
    chunk("GuildCotiz", ns)
  end

  local client = { name = charName, env = env, ns = ns, comm = comm }
  client.fullName = charName .. "-TestRealm"
  net.clients[client.fullName] = client
  table.insert(net.clients, client)

  env.GuildCotizDB = { guilds = {}, settings = { syncEnabled = true, syncChannel = "OFFICER" } }
  client.g = ns.GetGuildDB(true)
  return client
end

-- Achemine la file jusqu'a epuisement (le protocole doit terminer).
local function Pump(maxRounds)
  local rounds = 0
  while #net.queue > 0 do
    rounds = rounds + 1
    assert(rounds <= (maxRounds or 50), "le protocole ne termine pas (boucle de messages)")
    local batch = net.queue
    net.queue = {}
    for _, msg in ipairs(batch) do
      for _, client in ipairs(net.clients) do
        local isTarget = (msg.distribution == "WHISPER")
          and (msg.target == client.fullName)
          or (msg.distribution ~= "WHISPER")
        if isTarget and client.fullName ~= msg.from .. "-TestRealm" then
          client.comm.handler(msg.prefix, msg.text, msg.distribution, msg.from .. "-TestRealm")
        end
      end
    end
  end
  return rounds
end

-- Chaque scenario repart d'un reseau vide : sinon les clients des scenarios
-- precedents recoivent les diffusions et y repondent.
local function ResetNetwork()
  net.queue = {}
  net.clients = {}
  net.sent = 0
end

-- Remet un client deja cree sur le reseau courant.
local function Join(client)
  net.clients[client.fullName] = client
  table.insert(net.clients, client)
end

local function AddDeposit(client, player, goldAmount, t)
  local m = client.ns.EnsureMember(client.g, player)
  table.insert(m.deposits, { t = t, a = goldAmount * 10000 })
  client.g.seen[client.ns.DedupKey(player, goldAmount * 10000, t)] = true
end

local function AddWithdrawal(client, player, goldAmount, t)
  local m = client.ns.EnsureMember(client.g, player)
  table.insert(m.withdrawals, { t = t, a = goldAmount * 10000, kind = "withdraw" })
end

local function Snapshot(client)
  local rows = {}
  for name, m in pairs(client.g.members or {}) do
    for _, d in ipairs(m.deposits or {}) do
      rows[#rows + 1] = string.format("D|%s|%d|%d", name, d.a, math.floor(d.t / 3600))
    end
    for _, w in ipairs(m.withdrawals or {}) do
      rows[#rows + 1] = string.format("W|%s|%d|%d", name, w.a, math.floor(w.t / 3600))
    end
  end
  table.sort(rows)
  return table.concat(rows, "\n"), #rows
end

--------------------------------------------------------------------------------
-- Scenario
--------------------------------------------------------------------------------

local NOW = os.time()
local DAY = 86400
local failures = 0
local function check(label, condition, detail)
  if condition then
    print(string.format("  ok   %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL %s %s", label, detail or ""))
  end
end

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

print("")
if failures == 0 then
  print("TOUS LES TESTS PASSENT")
else
  print(string.format("%d TEST(S) EN ECHEC", failures))
  os.exit(1)
end
