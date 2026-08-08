-- GuildCotiz - Sync.lua
-- Partage des transactions du coffre entre officiers.
--
-- Perimetre volontairement limite aux depots et aux retraits, c'est-a-dire aux
-- seules donnees purement additives de l'addon. Deux officiers qui echangent
-- leurs transactions ne peuvent pas entrer en conflit : l'union de deux
-- ensembles est commutative, associative et idempotente. L'ordre d'arrivee des
-- messages n'a donc aucune importance, et une meme donnee recue deux fois ne
-- change rien.
--
-- Les presences en raid, les corrections manuelles et la configuration ne sont
-- PAS synchronisees ici : ce sont des valeurs mutables qui demandent un
-- arbitrage (horodatage + auteur), donc un changement de schema.
--
-- Protocole (borne, sans boucle possible) :
--   1. A diffuse son empreinte  : A --D--> canal
--   2. B repond les semaines ou il a du contenu que A n'a pas : B --T--> A
--   3. si B voit que A a du contenu qu'il n'a pas, il renvoie son empreinte
--      marquee "reponse" : B --D(r)--> A, et A lui repond en T.
--   Une empreinte marquee "reponse" ne declenche jamais une autre empreinte.

local ADDON, ns = ...
local L = ns.L

local AceComm      = LibStub("AceComm-3.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate   = LibStub("LibDeflate")

local Sync = {}
ns.Sync = Sync

--------------------------------------------------------------------------------
-- Constantes
--------------------------------------------------------------------------------

local PREFIX   = "GuildCotiz"  -- 10 caracteres (la limite Blizzard est de 16)
local PROTOCOL = 1

-- Au-dela d'un mois, WoW n'exprime plus l'anciennete qu'en mois et en annees, et
-- ElapsedToSeconds les approxime (30 jours / 365 jours). Deux officiers qui
-- scannent a des dates differentes obtiennent alors des timestamps ecartes de
-- plusieurs jours pour une meme transaction, ce que la fenetre de rapprochement
-- ne peut plus absorber. On ne partage donc que la periode ou l'horodatage
-- reste fiable ; au-dela chacun garde son historique local, deja acquis.
local MAX_AGE = 30 * 24 * 3600

local MIN_BROADCAST_INTERVAL = 30   -- entre deux diffusions d'empreinte
local REPLY_COOLDOWN         = 60   -- entre deux envois de donnees au meme pair
local MAX_TX_PER_PAYLOAD     = 500  -- garde-fou a l'emission
local MAX_TX_RECEIVED        = 2000 -- garde-fou a la reception
local MAX_AMOUNT             = 1e12 -- 100 millions de po, en cuivre

--------------------------------------------------------------------------------
-- Etat runtime (jamais persiste)
--------------------------------------------------------------------------------

local state = {
  lastBroadcast = 0,
  repliedTo     = {},  -- [pair] = timestamp du dernier envoi de donnees
  digestSentTo  = {},  -- [pair] = timestamp de la derniere empreinte-reponse
  pending       = nil, -- diffusion programmee
}

local function Announce(msg)
  print("|cff33ff99GuildCotiz|r : " .. msg)
end

local function Settings()
  return (GuildCotizDB and GuildCotizDB.settings) or {}
end

function Sync.IsEnabled()
  local s = Settings()
  return s.syncEnabled ~= false
end

function Sync.Channel()
  local s = Settings()
  return (s.syncChannel == "GUILD") and "GUILD" or "OFFICER"
end

local function MyFullName()
  local name = UnitName("player")
  if not name then return nil end
  local realm = GetNormalizedRealmName and GetNormalizedRealmName()
  if not realm or realm == "" then
    realm = ((GetRealmName() or ""):gsub("%s+", ""))
  end
  return name .. "-" .. realm
end

--------------------------------------------------------------------------------
-- Encodage
--------------------------------------------------------------------------------

local function Encode(payload)
  local ok, serialized = pcall(function() return LibSerialize:Serialize(payload) end)
  if not ok or not serialized then return nil end
  local compressed = LibDeflate:CompressDeflate(serialized, { level = 7 })
  if not compressed then return nil end
  return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

local function Decode(text)
  if type(text) ~= "string" or text == "" then return nil end
  local compressed = LibDeflate:DecodeForWoWAddonChannel(text)
  if not compressed then return nil end
  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil end
  local ok, success, payload = pcall(function() return LibSerialize:Deserialize(serialized) end)
  if not ok or not success or type(payload) ~= "table" then return nil end
  return payload
end

--------------------------------------------------------------------------------
-- Empreintes
--------------------------------------------------------------------------------

-- Empreinte par semaine : { nb depots, somme depots, nb retraits, somme retraits }.
-- Comparer nombre ET somme detecte aussi bien un manque qu'une divergence.
local function BuildDigest(g, now)
  local digest = {}
  local function bump(t, slotCount, slotSum, amount)
    if (now - t) > MAX_AGE then return end
    local week = ns.WeekMonday(t)
    local entry = digest[week]
    if not entry then entry = { 0, 0, 0, 0 }; digest[week] = entry end
    entry[slotCount] = entry[slotCount] + 1
    entry[slotSum]   = entry[slotSum] + amount
  end

  for _, m in pairs(g.members or {}) do
    for _, d in ipairs(m.deposits or {}) do bump(d.t, 1, 2, d.a) end
    for _, w in ipairs(m.withdrawals or {}) do bump(w.t, 3, 4, w.a) end
  end
  return digest
end

local function Differs(mine, theirs)
  if not theirs then return true end
  return mine[1] ~= theirs[1] or mine[2] ~= theirs[2]
      or mine[3] ~= theirs[3] or mine[4] ~= theirs[4]
end

-- Semaines pour lesquelles nos donnees different de celles du pair. On les lui
-- envoie meme quand c'est lui qui semble en avoir plus : l'union est sans risque
-- et une somme differente peut cacher un manque des deux cotes.
local function DivergingWeeks(mine, theirs)
  local weeks, count = {}, 0
  for week, entry in pairs(mine) do
    if Differs(entry, theirs[week]) then
      weeks[week] = true
      count = count + 1
    end
  end
  return weeks, count
end

local function PeerHasWeeksWeLack(mine, theirs)
  for week, entry in pairs(theirs) do
    if Differs(entry, mine[week]) then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- Collecte et fusion
--------------------------------------------------------------------------------

-- Une entree porte { n = joueur, a = montant, t = horodatage } et, pour un
-- retrait uniquement, k = type de sortie. L'absence de k signifie "depot".
local function CollectTransactions(g, weeks, now)
  local out = {}
  for name, m in pairs(g.members or {}) do
    for _, d in ipairs(m.deposits or {}) do
      if weeks[ns.WeekMonday(d.t)] and (now - d.t) <= MAX_AGE then
        out[#out + 1] = { n = name, a = d.a, t = d.t }
      end
    end
    for _, w in ipairs(m.withdrawals or {}) do
      if weeks[ns.WeekMonday(w.t)] and (now - w.t) <= MAX_AGE then
        out[#out + 1] = { n = name, a = w.a, t = w.t, k = w.kind }
      end
    end
  end

  -- Si le volume explose, on privilegie les transactions les plus recentes :
  -- ce sont celles qui risquent de disparaitre du journal des autres.
  if #out > MAX_TX_PER_PAYLOAD then
    table.sort(out, function(a, b) return a.t > b.t end)
    for i = #out, MAX_TX_PER_PAYLOAD + 1, -1 do out[i] = nil end
  end
  return out
end

local function IsValidEntry(entry, now)
  if type(entry) ~= "table" then return false end
  if type(entry.n) ~= "string" or #entry.n < 2 or #entry.n > 24 then return false end
  if type(entry.a) ~= "number" or entry.a <= 0 or entry.a > MAX_AMOUNT then return false end
  if type(entry.t) ~= "number" or entry.t < 1000000000 or entry.t > (now + 86400) then return false end
  if entry.k ~= nil and not ns.WITHDRAW_TYPES[entry.k] then return false end
  return true
end

-- Fusionne une liste de transactions recues. Renvoie le nombre de depots et de
-- retraits reellement ajoutes.
function Sync.MergeTransactions(g, list)
  local now = time()
  local addedD, addedW, realigned = 0, 0, 0

  -- Regroupe avant de fusionner : deux depots identiques recus du meme pair
  -- doivent rester deux depots, ce qu'un rapprochement entree par entree
  -- perdrait. Le rapprochement compare donc des suites, comme le scan local.
  local deposits = {}     -- [joueur] = { [montant] = { instants } }
  local withdrawals = {}  -- [joueur] = { [type] = { [montant] = { instants } } }

  local function push(bucket, amount, t)
    local slot = bucket[amount]
    if not slot then slot = {}; bucket[amount] = slot end
    slot[#slot + 1] = t
  end

  for _, entry in ipairs(list or {}) do
    if IsValidEntry(entry, now) then
      local name   = ns.ShortName(entry.n)
      local amount = math.floor(entry.a)
      local t      = math.floor(entry.t)
      if entry.k then
        withdrawals[name] = withdrawals[name] or {}
        withdrawals[name][entry.k] = withdrawals[name][entry.k] or {}
        push(withdrawals[name][entry.k], amount, t)
      else
        deposits[name] = deposits[name] or {}
        push(deposits[name], amount, t)
      end
    end
  end

  for name, observed in pairs(deposits) do
    local m = ns.EnsureMember(g, name)
    local n, touched = ns.ReconcileTransactions(m.deposits, observed, nil)
    addedD = addedD + n
    if touched then realigned = realigned + 1 end
  end

  for name, byKind in pairs(withdrawals) do
    local m = ns.EnsureMember(g, name)
    for kind, observed in pairs(byKind) do
      local n, touched = ns.ReconcileTransactions(m.withdrawals, observed, kind)
      addedW = addedW + n
      if touched then realigned = realigned + 1 end
    end
  end

  if addedD > 0 or addedW > 0 or realigned > 0 then
    for _, m in pairs(g.members) do
      if m.deposits then table.sort(m.deposits, function(a, b) return a.t < b.t end) end
      if m.withdrawals then table.sort(m.withdrawals, function(a, b) return a.t < b.t end) end
    end
    if ns.RefreshUI then ns.RefreshUI() end
  end

  return addedD, addedW
end

--------------------------------------------------------------------------------
-- Emission
--------------------------------------------------------------------------------

local function Send(payload, distribution, target)
  local encoded = Encode(payload)
  if not encoded then return false end
  AceComm:SendCommMessage(PREFIX, encoded, distribution, target, "BULK")
  return true
end

-- Diffuse notre empreinte. manual = declenche par l'officier (/cotiz sync),
-- ce qui court-circuite l'anti-rafale et donne un retour ecrit.
function Sync.Broadcast(manual)
  if not Sync.IsEnabled() then
    if manual then Announce(L("SYNC_DISABLED")) end
    return
  end
  if not IsInGuild() then
    if manual then Announce(L("NOT_IN_GUILD")) end
    return
  end

  local now = time()
  if not manual and (now - state.lastBroadcast) < MIN_BROADCAST_INTERVAL then return end

  local g = ns.GetGuildDB(true)
  if not g then return end

  state.lastBroadcast = now
  local ok = Send({
    op = "D",
    p  = PROTOCOL,
    g  = ns.GetGuildKey(),
    d  = BuildDigest(g, now),
  }, Sync.Channel())

  if manual then
    Announce(ok and L("SYNC_SENT", Sync.Channel()) or L("SYNC_ENCODE_FAILED"))
  end
end

-- Programme une diffusion differee (login, fin de scan). Une seule en attente.
function Sync.Schedule(delay)
  if not Sync.IsEnabled() then return end
  if state.pending then return end
  state.pending = true
  C_Timer.After(delay or 10, function()
    state.pending = nil
    Sync.Broadcast(false)
  end)
end

--------------------------------------------------------------------------------
-- Reception
--------------------------------------------------------------------------------

local function HandleDigest(payload, sender)
  local g = ns.GetGuildDB(true)
  if not g then return end

  local now   = time()
  local mine  = BuildDigest(g, now)
  local their = payload.d

  local weeks, count = DivergingWeeks(mine, their)
  if count > 0 and (now - (state.repliedTo[sender] or 0)) >= REPLY_COOLDOWN then
    local transactions = CollectTransactions(g, weeks, now)
    if #transactions > 0 then
      state.repliedTo[sender] = now
      Send({ op = "T", p = PROTOCOL, g = payload.g, x = transactions }, "WHISPER", sender)
    end
  end

  -- Le pair detient des semaines qui nous manquent : on lui renvoie notre
  -- empreinte marquee "reponse" pour qu'il nous pousse ses donnees. Le marqueur
  -- garantit qu'il ne nous en renverra pas une a son tour.
  if not payload.r and PeerHasWeeksWeLack(mine, their) then
    if (now - (state.digestSentTo[sender] or 0)) >= REPLY_COOLDOWN then
      state.digestSentTo[sender] = now
      Send({ op = "D", p = PROTOCOL, g = payload.g, d = mine, r = true }, "WHISPER", sender)
    end
  end
end

local function HandleTransactions(payload, sender)
  local g = ns.GetGuildDB(true)
  if not g then return end

  local list = payload.x
  if type(list) ~= "table" or #list == 0 then return end
  if #list > MAX_TX_RECEIVED then return end

  local addedD, addedW = Sync.MergeTransactions(g, list)
  if addedD > 0 or addedW > 0 then
    Announce(L("SYNC_RECEIVED", ns.ShortName(sender), addedD, addedW))
  end
end

local function OnCommReceived(prefix, text, distribution, sender)
  if prefix ~= PREFIX then return end
  if not Sync.IsEnabled() then return end
  if not sender or sender == MyFullName() then return end

  local payload = Decode(text)
  if not payload or payload.p ~= PROTOCOL then return end

  -- Une empreinte calculee sur une autre guilde n'a aucun sens ici.
  if payload.g ~= ns.GetGuildKey() then return end

  if payload.op == "D" and type(payload.d) == "table" then
    HandleDigest(payload, sender)
  elseif payload.op == "T" then
    HandleTransactions(payload, sender)
  end
end

AceComm:RegisterComm(PREFIX, OnCommReceived)

--------------------------------------------------------------------------------
-- Diagnostic
--------------------------------------------------------------------------------

function Sync.Status()
  local g = ns.GetGuildDB(true)
  Announce(L("SYNC_STATUS_ENABLED", tostring(Sync.IsEnabled()), Sync.Channel()))
  if g then
    local digest, weeks, deposits, withdrawals = BuildDigest(g, time()), 0, 0, 0
    for _, entry in pairs(digest) do
      weeks = weeks + 1
      deposits = deposits + entry[1]
      withdrawals = withdrawals + entry[3]
    end
    Announce(L("SYNC_STATUS_DIGEST", weeks, deposits, withdrawals))
  end
end
