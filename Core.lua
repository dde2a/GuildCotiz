-- GuildCotiz - Core.lua
-- Suivi des cotisations de guilde : lecture du journal d'or du coffre de guilde,
-- accumulation des depots par joueur, calcul du statut "a jour" semaine par semaine.

local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Constantes
--------------------------------------------------------------------------------
local WEEK_SECONDS = 7 * 24 * 60 * 60
local COPPER_PER_GOLD = 10000

ns.WEEK_SECONDS = WEEK_SECONDS
ns.COPPER_PER_GOLD = COPPER_PER_GOLD

-- Types de transaction correspondant a une SORTIE d'or du coffre.
-- Ils ne comptent JAMAIS comme cotisation : ils alimentent l'onglet Retraits.
ns.WITHDRAW_TYPES = {
  withdraw       = "Retrait",
  repair         = "Reparations",
  withdrawForTab = "Achat onglet",
  buyTab         = "Achat onglet",
}

--------------------------------------------------------------------------------
-- Utilitaires
--------------------------------------------------------------------------------

-- Nom court sans le "-Royaume"
function ns.ShortName(name)
  if not name then return nil end
  return (name:gsub("%-.*$", ""))
end

-- copper -> gold (nombre decimal)
function ns.CopperToGold(copper)
  return (copper or 0) / COPPER_PER_GOLD
end

-- gold (nombre) -> copper (entier)
function ns.GoldToCopper(gold)
  return math.floor((tonumber(gold) or 0) * COPPER_PER_GOLD + 0.5)
end

-- Formatage lisible d'un montant en cuivre -> "1234po 56pa 78pc"
function ns.FormatMoney(copper)
  copper = math.floor(copper or 0)
  local sign = ""
  if copper < 0 then sign = "-"; copper = -copper end
  local g = math.floor(copper / COPPER_PER_GOLD)
  local s = math.floor((copper % COPPER_PER_GOLD) / 100)
  local c = copper % 100
  if g > 0 then
    return string.format("%s%s|cffffd700po|r %d|cffc7c7cfpa|r %d|cffeda55fpc|r", sign, BreakUpLargeNumbers(g), s, c)
  elseif s > 0 then
    return string.format("%s%d|cffc7c7cfpa|r %d|cffeda55fpc|r", sign, s, c)
  else
    return string.format("%s%d|cffeda55fpc|r", sign, c)
  end
end

-- Formatage court en or entier "1 234 po"
function ns.FormatGold(copper)
  local g = math.floor((copper or 0) / COPPER_PER_GOLD)
  return BreakUpLargeNumbers(g) .. " po"
end

-- Timestamp du lundi 00h00 de la semaine ISO contenant t
function ns.WeekMonday(t)
  local info = date("*t", t)
  local isoWday = (info.wday == 1) and 7 or (info.wday - 1) -- Lundi=1 .. Dimanche=7
  local approx = t - (isoWday - 1) * 24 * 3600
  local mi = date("*t", approx)
  return time({ year = mi.year, month = mi.month, day = mi.day, hour = 0 })
end

-- Numero de semaine ISO 8601 et annee ISO pour le timestamp t
function ns.ISOWeek(t)
  local info = date("*t", t)
  local isoWday = (info.wday == 1) and 7 or (info.wday - 1)
  local thursday = t + (4 - isoWday) * 24 * 3600 -- le jeudi determine l'annee ISO
  local ti = date("*t", thursday)
  local week = math.floor((ti.yday - 1) / 7) + 1
  return ti.year, week
end

--------------------------------------------------------------------------------
-- Base de donnees (SavedVariables)
--------------------------------------------------------------------------------

local DEFAULT_CONFIG = {
  raidAmount  = 1000 * COPPER_PER_GOLD, -- cotisation due PAR RAID effectue (en cuivre)
  seasonStart = nil,                     -- timestamp de debut de suivi (defini au 1er lancement)
}

local DEFAULT_SETTINGS = {
  csvSeparator = ";",  -- separateur CSV (Excel FR aime le ;)
}

-- Cle unique de la guilde courante
function ns.GetGuildKey()
  if not IsInGuild() then return nil end
  local guildName, _, _, realm = GetGuildInfo("player")
  if not guildName then return nil end
  realm = realm or GetRealmName() or ""
  return guildName .. "-" .. realm
end

-- Initialise la structure DB et renvoie la table de la guilde courante (ou nil)
function ns.GetGuildDB(create)
  local db = GuildCotizDB
  if not db then return nil end
  local key = ns.GetGuildKey()
  if not key then return nil end
  if not db.guilds[key] and create then
    db.guilds[key] = {
      config  = CopyTable(DEFAULT_CONFIG),
      members = {},   -- [shortName] = { rankName, rankIndex, note, startOverride, active, deposits, withdrawals }
      seen    = {},   -- clefs de dedup des transactions deja enregistrees
      raids   = {},   -- [lundiTimestamp] = { [nomJoueur] = nbRaids }
    }
  end
  local g = db.guilds[key]
  if not g then return nil end

  g.raids = g.raids or {}
  if g.config then
    -- migration : l'ancienne cotisation hebdomadaire devient la cotisation par raid
    if g.config.raidAmount == nil then
      g.config.raidAmount = g.config.weeklyAmount or DEFAULT_CONFIG.raidAmount
      g.config.weeklyAmount = nil
    end
    if g.config.seasonStart == nil then
      local now = time()
      g.config.seasonStart = now - (now % (24 * 60 * 60))
    end
  end
  return g
end

--------------------------------------------------------------------------------
-- Raids effectues (saisie manuelle, par semaine ISO et par joueur)
--------------------------------------------------------------------------------

-- Nombre de raids saisi pour un joueur sur une semaine (cle = lundi minuit)
function ns.GetRaids(g, weekTs, name)
  local w = g.raids[weekTs]
  return (w and w[name]) or 0
end

-- Definit le nombre de raids d'un joueur pour une semaine (0 = efface l'entree)
function ns.SetRaids(g, weekTs, name, count)
  count = tonumber(count) or 0
  if count < 0 then count = 0 end
  if count == 0 then
    if g.raids[weekTs] then
      g.raids[weekTs][name] = nil
      if next(g.raids[weekTs]) == nil then g.raids[weekTs] = nil end
    end
  else
    g.raids[weekTs] = g.raids[weekTs] or {}
    g.raids[weekTs][name] = count
  end
end

-- Total des raids d'un joueur jusqu'a untilT (semaines dont le lundi <= untilT)
function ns.TotalRaids(g, name, untilT)
  local total = 0
  for weekTs, players in pairs(g.raids) do
    if not untilT or weekTs <= untilT then
      total = total + (players[name] or 0)
    end
  end
  return total
end

--------------------------------------------------------------------------------
-- Membres
--------------------------------------------------------------------------------

local function EnsureMember(g, shortName)
  local m = g.members[shortName]
  if not m then
    m = { rankName = "?", rankIndex = 99, note = "", startOverride = nil, active = false }
    g.members[shortName] = m
  end
  -- init paresseuse (compatibilite avec les donnees enregistrees avant les retraits)
  m.deposits = m.deposits or {}
  m.withdrawals = m.withdrawals or {}
  return m
end
ns.EnsureMember = EnsureMember

-- Debut de suivi d'un membre : override individuel sinon debut de saison
function ns.MemberStart(g, m)
  return m.startOverride or g.config.seasonStart
end

--------------------------------------------------------------------------------
-- Scan du roster de guilde
--------------------------------------------------------------------------------

function ns.ScanRoster()
  local g = ns.GetGuildDB(true)
  if not g then return end
  local num = GetNumGuildMembers()
  -- marque tout le monde inactif, puis re-active les presents
  for _, m in pairs(g.members) do m.active = false end
  for i = 1, num do
    local name, rankName, rankIndex, _, _, _, note = GetGuildRosterInfo(i)
    if name then
      local short = ns.ShortName(name)
      local m = EnsureMember(g, short)
      m.rankName = rankName or m.rankName
      m.rankIndex = rankIndex or m.rankIndex
      if note and note ~= "" then m.note = note end
      m.active = true
    end
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

--------------------------------------------------------------------------------
-- Scan du journal d'or du coffre de guilde
--------------------------------------------------------------------------------

-- Convertit "il y a X ans/mois/jours/heures" en secondes ecoulees (approx.)
local function ElapsedToSeconds(years, months, days, hours)
  return ((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 24 * 3600
       + (hours or 0) * 3600
end

-- Cle de dedup stable : nom | montant | jour absolu approximatif.
-- Resolution 1 jour : robuste au fait que WoW n'exprime l'anciennete qu'en heures
-- entieres (un meme depot scanne a deux moments differents tombe sur le meme jour).
local function DedupKey(name, amount, absTime)
  local bucket = math.floor(absTime / 86400)
  return name .. "|" .. amount .. "|" .. bucket
end

-- Lit le journal d'or (le coffre doit etre ouvert). Renvoie le nb de nouveaux depots.
function ns.ScanBankLog()
  if not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then
    return 0, "API du coffre indisponible sur cette version de WoW."
  end
  local g = ns.GetGuildDB(true)
  if not g then return 0, "Tu n'es pas dans une guilde." end

  local now = time()
  local count = GetNumGuildBankMoneyTransactions()
  local added = 0

  local addedW = 0

  for i = 1, count do
    local txType, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
    if name and amount and amount > 0 then
      local short = ns.ShortName(name)
      local absTime = now - ElapsedToSeconds(years, months, days, hours)

      -- Seuls les depots comptent comme cotisation
      if txType == "deposit" then
        local key = DedupKey(short, amount, absTime)
        if not g.seen[key] then
          g.seen[key] = true
          local m = EnsureMember(g, short)
          table.insert(m.deposits, { t = absTime, a = amount })
          added = added + 1
        end

      -- Les sorties d'or sont enregistrees a part (onglet Retraits), jamais en cotisation
      elseif ns.WITHDRAW_TYPES[txType] then
        local key = "W|" .. DedupKey(short, amount, absTime)
        if not g.seen[key] then
          g.seen[key] = true
          local m = EnsureMember(g, short)
          table.insert(m.withdrawals, { t = absTime, a = amount, kind = txType })
          addedW = addedW + 1
        end
      end
    end
  end

  -- tri par date pour l'historique
  if added > 0 or addedW > 0 then
    for _, m in pairs(g.members) do
      if m.deposits then table.sort(m.deposits, function(a, b) return a.t < b.t end) end
      if m.withdrawals then table.sort(m.withdrawals, function(a, b) return a.t < b.t end) end
    end
  end

  if ns.RefreshUI then ns.RefreshUI() end
  return added, nil, addedW
end

-- Nettoie les doublons deja enregistres (par nom+montant+jour) et reconstruit l'index.
-- Renvoie le nombre d'entrees supprimees.
function ns.Deduplicate()
  local g = ns.GetGuildDB(true)
  if not g then return 0 end
  g.seen = {}
  local removed = 0
  for name, m in pairs(g.members) do
    local localSeen = {}

    local kept = {}
    for _, d in ipairs(m.deposits or {}) do
      local key = DedupKey(name, d.a, d.t)
      if localSeen[key] then
        removed = removed + 1
      else
        localSeen[key] = true
        g.seen[key] = true
        kept[#kept + 1] = d
      end
    end
    table.sort(kept, function(a, b) return a.t < b.t end)
    m.deposits = kept

    local keptW = {}
    for _, w in ipairs(m.withdrawals or {}) do
      local key = "W|" .. DedupKey(name, w.a, w.t)
      if localSeen[key] then
        removed = removed + 1
      else
        localSeen[key] = true
        g.seen[key] = true
        keptW[#keptW + 1] = w
      end
    end
    table.sort(keptW, function(a, b) return a.t < b.t end)
    m.withdrawals = keptW
  end
  if ns.RefreshUI then ns.RefreshUI() end
  return removed
end

--------------------------------------------------------------------------------
-- Calculs de cotisation
--------------------------------------------------------------------------------

-- Nombre de semaines dues entre "start" et "now" (la semaine en cours compte des qu'elle debute)
function ns.WeeksElapsed(startT, now)
  now = now or time()
  if not startT or now < startT then return 0 end
  return math.floor((now - startT) / WEEK_SECONDS) + 1
end

-- Total depose par un membre depuis son debut de suivi.
-- untilT : si fourni, ne compte que les depots effectues jusqu'a cette date (vue historique).
function ns.TotalPaid(g, m, untilT)
  local startT = ns.MemberStart(g, m)
  local total = 0
  for _, d in ipairs(m.deposits) do
    if (not startT or d.t >= startT) and (not untilT or d.t <= untilT) then
      total = total + d.a
    end
  end
  return total
end

-- Liste a plat de tous les retraits, du plus recent au plus ancien.
-- Chaque entree : { name, rankName, t, a, kind }
function ns.GetAllWithdrawals(g)
  local list = {}
  for name, m in pairs(g.members) do
    for _, w in ipairs(m.withdrawals or {}) do
      list[#list + 1] = {
        name = name, rankName = m.rankName or "?",
        t = w.t, a = w.a, kind = w.kind,
      }
    end
  end
  table.sort(list, function(a, b) return a.t > b.t end)
  return list
end

-- Total retire par un membre (toutes sorties confondues)
function ns.TotalWithdrawn(g, m)
  local total = 0
  for _, w in ipairs(m.withdrawals or {}) do total = total + w.a end
  return total
end

-- Date du plus ancien depot enregistre (tous membres confondus), ou nil
function ns.EarliestDeposit(g)
  local earliest
  for _, m in pairs(g.members) do
    for _, d in ipairs(m.deposits) do
      if not earliest or d.t < earliest then earliest = d.t end
    end
  end
  return earliest
end

-- Statut complet d'un membre : la dette depend du NOMBRE DE RAIDS effectues.
-- name : nom court du joueur (necessaire pour retrouver ses raids)
function ns.GetMemberStatus(g, m, name, now)
  now = now or time()
  local perRaid = g.config.raidAmount or 0
  local startT = ns.MemberStart(g, m)
  local raids = ns.TotalRaids(g, name, now)
  local owed = raids * perRaid
  local paid = ns.TotalPaid(g, m, now)
  local balance = paid - owed
  local raidsCovered = (perRaid > 0) and math.floor(paid / perRaid) or 0

  local status, raidsBehind, raidsAhead, due
  if balance >= 0 then
    raidsBehind = 0
    raidsAhead = math.max(0, raidsCovered - raids)
    due = 0
    status = (raidsAhead > 0) and "avance" or "ajour"
  else
    raidsBehind = (perRaid > 0) and math.ceil(-balance / perRaid) or 0
    raidsAhead = 0
    due = -balance
    status = "retard"
  end

  return {
    perRaid      = perRaid,
    startT       = startT,
    raids        = raids,        -- total de raids effectues
    owed         = owed,
    paid         = paid,
    balance      = balance,
    raidsCovered = raidsCovered, -- nb de raids que le total paye couvre
    status       = status,       -- "ajour" | "avance" | "retard"
    raidsBehind  = raidsBehind,
    raidsAhead   = raidsAhead,
    due          = due,          -- montant manquant (cuivre) si en retard
  }
end

-- Detail semaine par semaine (semaines ISO) pour un membre.
-- Chaque ligne : { index, weekStart, weekEnd, raids, dueWeek, deposited,
--                  cumRaids, cumOwed, cumPaid, balanceEnd, status }
function ns.GetWeeklyBreakdown(g, m, name, now)
  now = now or time()
  local perRaid = g.config.raidAmount or 0
  local startT = ns.MemberStart(g, m)
  local rows = {}
  if not startT then return rows end

  local firstMonday = ns.WeekMonday(startT)
  local lastMonday = ns.WeekMonday(now)
  local cumPaid, cumOwed, cumRaids = 0, 0, 0
  local index = 0

  local ws = firstMonday
  while ws <= lastMonday do
    local we = ws + WEEK_SECONDS
    index = index + 1

    local raids = ns.GetRaids(g, ws, name)
    local dueWeek = raids * perRaid

    local deposited = 0
    for _, d in ipairs(m.deposits) do
      if d.t >= ws and d.t < we and d.t >= startT then
        deposited = deposited + d.a
      end
    end

    cumRaids = cumRaids + raids
    cumOwed = cumOwed + dueWeek
    cumPaid = cumPaid + deposited
    local balanceEnd = cumPaid - cumOwed

    local st
    if raids == 0 and deposited == 0 then
      st = "norraid"                       -- rien a payer, rien de verse
    elseif balanceEnd >= 0 then
      st = (deposited > 0) and "paye" or "couvert"
    else
      st = "nonpaye"
    end

    rows[#rows + 1] = {
      index = index, weekStart = ws, weekEnd = we,
      raids = raids, dueWeek = dueWeek, deposited = deposited,
      cumRaids = cumRaids, cumOwed = cumOwed, cumPaid = cumPaid,
      balanceEnd = balanceEnd, status = st,
    }
    ws = we
  end
  return rows
end

--------------------------------------------------------------------------------
-- Liste triee des membres (pour l'affichage / export)
--------------------------------------------------------------------------------

function ns.GetSortedMembers(g, opts)
  opts = opts or {}
  local list = {}
  for name, m in pairs(g.members) do
    if opts.includeInactive or m.active or #m.deposits > 0 then
      table.insert(list, { name = name, m = m })
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return list
end

--------------------------------------------------------------------------------
-- Evenements
--------------------------------------------------------------------------------

-- Demande au serveur le journal d'or (onglet "argent" = MAX_GUILDBANK_TABS + 1)
function ns.QueryMoneyLog()
  if QueryGuildBankLog then
    QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1)
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("GUILDBANKFRAME_OPENED")
f:RegisterEvent("GUILDBANKLOG_UPDATE")

f:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    GuildCotizDB = GuildCotizDB or {}
    GuildCotizDB.guilds = GuildCotizDB.guilds or {}
    GuildCotizDB.settings = GuildCotizDB.settings or CopyTable(DEFAULT_SETTINGS)
    for k, v in pairs(DEFAULT_SETTINGS) do
      if GuildCotizDB.settings[k] == nil then GuildCotizDB.settings[k] = v end
    end

  elseif event == "PLAYER_LOGIN" then
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
      C_GuildInfo.GuildRoster()
    end
    ns.ScanRoster()

  elseif event == "GUILD_ROSTER_UPDATE" then
    ns.ScanRoster()

  elseif event == "GUILDBANKFRAME_OPENED" then
    -- demande le journal d'or ; le scan se fera au GUILDBANKLOG_UPDATE qui suit
    ns.QueryMoneyLog()

  elseif event == "GUILDBANKLOG_UPDATE" then
    -- on scanne a chaque mise a jour (le dedoublonnage evite les doublons),
    -- ce qui capte aussi un depot fait pendant que le coffre est deja ouvert
    local added, _, addedW = ns.ScanBankLog()
    if (added or 0) > 0 or (addedW or 0) > 0 then
      print(string.format("|cff33ff99GuildCotiz|r : %d depot(s) et %d retrait(s) enregistre(s).",
        added or 0, addedW or 0))
    end
  end
end)

ns.eventFrame = f

--------------------------------------------------------------------------------
-- Diagnostic (/cotiz debug)
--------------------------------------------------------------------------------
function ns.DebugDump()
  local p = function(...) print("|cff33ff99GuildCotiz|r " .. string.format(...)) end
  p("=== DIAGNOSTIC ===")
  p("Dans une guilde : %s | cle : %s", tostring(IsInGuild()), tostring(ns.GetGuildKey()))
  p("API GetNumGuildBankMoneyTransactions : %s", tostring(GetNumGuildBankMoneyTransactions ~= nil))
  p("API GetGuildBankMoneyTransaction : %s", tostring(GetGuildBankMoneyTransaction ~= nil))

  if GetNumGuildBankMoneyTransactions then
    local n = GetNumGuildBankMoneyTransactions()
    p("Transactions dans le journal : %d (0 = coffre ferme ou journal non charge)", n or 0)
    for i = 1, math.min(n or 0, 8) do
      local t, name, amount, y, mo, d, h = GetGuildBankMoneyTransaction(i)
      p("  #%d type=%s nom=%s montant=%s il y a %sa %sm %sj %sh",
        i, tostring(t), tostring(name), tostring(amount),
        tostring(y), tostring(mo), tostring(d), tostring(h))
    end
  end

  local g = ns.GetGuildDB(true)
  if g then
    local nm, nd = 0, 0
    for name, m in pairs(g.members) do
      nm = nm + 1
      nd = nd + #m.deposits
    end
    p("Membres connus : %d | depots enregistres (total) : %d", nm, nd)
    p("Debut de suivi : %s | cotisation : %s/raid",
      g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or "?",
      ns.FormatGold(g.config.raidAmount))
    -- detail du joueur courant
    local me = ns.ShortName(UnitName("player"))
    local mine = g.members[me]
    if mine then
      p("Toi (%s) : %d depot(s), total (depuis debut) %s",
        me, #mine.deposits, ns.FormatGold(ns.TotalPaid(g, mine)))
      for _, d in ipairs(mine.deposits) do
        p("   depot %s le %s (%s le debut)",
          ns.FormatGold(d.a), date("%Y-%m-%d %H:%M", d.t),
          (g.config.seasonStart and d.t >= g.config.seasonStart) and "APRES" or "AVANT")
      end
    else
      p("Toi (%s) : aucun enregistrement", me)
    end
  end
  p("=== FIN ===")
end
