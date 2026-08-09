-- Banc d'essai commun : charge le vrai addon hors de WoW, dans plusieurs
-- environnements isoles, relies par un reseau de messages simule.

local REPO = (...) and ((...):match("^(.*)tests[%./\\]") or "./") or "./"
if arg and arg[0] then
  REPO = arg[0]:match("^(.*)tests[/\\][^/\\]+$") or REPO
end

-- Compatibilite Lua 5.2+ / Fengari : WoW utilise Lua 5.1 et fournit setfenv.
if not setfenv then
  function setfenv(fn, env)
    local index = 1
    while true do
      local name = debug.getupvalue(fn, index)
      if name == "_ENV" then
        debug.upvaluejoin(fn, index, function() return env end, 1)
        return fn
      elseif not name then
        return fn
      end
      index = index + 1
    end
  end
end

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

  -- Journal d'or simule. WoW n'exprime l'anciennete qu'en unites entieres, la
  -- plus fine etant l'heure : deux operations faites dans la meme heure sont
  -- rigoureusement indiscernables par leur horodatage.
  local bank = {}
  env.GetNumGuildBankMoneyTransactions = function() return #bank end
  env.GetGuildBankMoneyTransaction = function(i)
    local e = bank[i]
    if not e then return nil end
    return e.kind, e.name, e.gold * 10000, 0, 0, e.daysAgo or 0, e.hoursAgo or 0
  end

  -- Roster simule. visibleCount modelise le piege reel de WoW : quand
  -- l'affichage des hors-ligne est coupe, GetNumGuildMembers annonce le total
  -- mais GetGuildRosterInfo n'indexe que les connectes.
  local roster = { total = 0, visible = {} }
  env.GetNumGuildMembers = function() return roster.total end
  env.GetGuildRosterInfo = function(i)
    local e = roster.visible[i]
    if not e then return nil end
    return e.name, e.rank, e.rankIndex, nil, nil, nil, e.note, e.officerNote
  end

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
  -- rows = { { kind = "deposit"|"withdraw", name =, gold =, hoursAgo =, daysAgo = } }
  function client.SetBankLog(rows)
    bank = {}
    for i, r in ipairs(rows) do bank[i] = r end
  end

  function client.SetRoster(names, visibleCount)
    roster.total = #names
    roster.visible = {}
    for i = 1, (visibleCount or #names) do
      roster.visible[i] = { name = names[i], rank = "Membre", rankIndex = 3 }
    end
  end
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

local function report()
  print("")
  if failures == 0 then
    print("TOUS LES TESTS PASSENT")
    return 0
  end
  print(string.format("%d TEST(S) EN ECHEC", failures))
  return 1
end

return {
  NewClient = NewClient, Pump = Pump, ResetNetwork = ResetNetwork, Join = Join,
  AddDeposit = AddDeposit, AddWithdrawal = AddWithdrawal, Snapshot = Snapshot,
  check = check, report = report, net = net,
  NOW = NOW, DAY = DAY,
}
