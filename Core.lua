-- GuildCotiz - Core.lua
-- Suivi des cotisations de guilde : lecture du journal d'or du coffre de guilde,
-- accumulation des depots par joueur, calcul du statut "a jour" semaine par semaine.

local ADDON, ns = ...
local L = ns.L

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
  withdraw       = L("WITHDRAW"),
  repair         = L("REPAIR"),
  withdrawForTab = L("TAB_PURCHASE"),
  buyTab         = L("TAB_PURCHASE"),
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
    return string.format("%s%s|cffffd700%s|r %d|cffc7c7cf%s|r %d|cffeda55f%s|r",
      sign, BreakUpLargeNumbers(g), L("GOLD_SHORT"), s, L("SILVER_SHORT"), c, L("COPPER_SHORT"))
  elseif s > 0 then
    return string.format("%s%d|cffc7c7cf%s|r %d|cffeda55f%s|r",
      sign, s, L("SILVER_SHORT"), c, L("COPPER_SHORT"))
  else
    return string.format("%s%d|cffeda55f%s|r", sign, c, L("COPPER_SHORT"))
  end
end

-- Formatage court en or entier "1 234 po"
function ns.FormatGold(copper)
  local g = math.floor((copper or 0) / COPPER_PER_GOLD)
  return BreakUpLargeNumbers(g) .. " " .. L("GOLD_SHORT")
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
  ratePeriods = {},                      -- historique { start, amount } des tarifs par saison
}

local DEFAULT_SETTINGS = {
  csvSeparator = ";",        -- separateur CSV (Excel FR aime le ;)
  showFormerMembers = false, -- afficher les membres ayant quitte la guilde
  syncEnabled  = true,       -- partage des transactions entre officiers
  syncChannel  = "OFFICER",  -- "OFFICER" (recommande) ou "GUILD"
}

-- Cle unique de la guilde courante
function ns.GetGuildKey()
  if not IsInGuild() then return nil end
  local guildName, _, _, realm = GetGuildInfo("player")
  if not guildName then return nil end
  realm = realm or GetRealmName() or ""
  return guildName .. "-" .. realm
end

local function NormalizeRatePeriods(g, guildKey)
  g.config.ratePeriods = g.config.ratePeriods or {}
  local candidates = {}
  local function Add(startT, amount, name)
    startT, amount = tonumber(startT), tonumber(amount)
    if startT and startT > 0 and amount and amount >= 0 then
      candidates[#candidates + 1] = { start = startT, amount = amount, name = name }
    end
  end

  for _, period in ipairs(g.config.ratePeriods) do Add(period.start, period.amount, period.name) end
  if #g.config.ratePeriods == 0 then Add(g.config.seasonStart, g.config.raidAmount) end

  -- Migration 1.5 : les profils nommes peuvent contenir l'ancien tarif, meme
  -- si les options courantes ont deja ete remplacees par celles de la S2.
  if not g.config.ratePeriodsMigrated then
    for _, profile in pairs((GuildCotizDB and GuildCotizDB.profiles) or {}) do
      if not profile.guild or profile.guild == guildKey then
        Add(profile.config and profile.config.seasonStart,
          profile.config and profile.config.raidAmount)
      end
    end
  end

  table.sort(candidates, function(a, b) return a.start < b.start end)
  local byWeek = {}
  for _, period in ipairs(candidates) do
    byWeek[ns.WeekMonday(period.start)] = period
  end
  local periods = {}
  for _, period in pairs(byWeek) do periods[#periods + 1] = period end
  table.sort(periods, function(a, b) return a.start < b.start end)

  -- Si une activite comptable precede tous les profils retrouves, prolonge le
  -- plus ancien tarif jusqu'a cette activite. Les depots doivent rester acquis
  -- meme lorsqu'aucun raid n'avait encore ete saisi dans l'addon.
  local earliestActivity
  for weekTs in pairs(g.raids or {}) do
    if not earliestActivity or weekTs < earliestActivity then earliestActivity = weekTs end
  end
  for _, member in pairs(g.members or {}) do
    for _, deposit in ipairs(member.deposits or {}) do
      if deposit.t and (not earliestActivity or deposit.t < earliestActivity) then
        earliestActivity = deposit.t
      end
    end
    for weekTs in pairs(member.depositOverrides or {}) do
      if not earliestActivity or weekTs < earliestActivity then earliestActivity = weekTs end
    end
  end
  if earliestActivity and periods[1]
    and ns.WeekMonday(earliestActivity) < ns.WeekMonday(periods[1].start) then
    table.insert(periods, 1, { start = earliestActivity, amount = periods[1].amount })
  end

  -- Les periodes consecutives au meme tarif n'ont aucune incidence distincte.
  local compact = {}
  for _, period in ipairs(periods) do
    if #compact == 0 or compact[#compact].amount ~= period.amount
      or compact[#compact].name or period.name then
      compact[#compact + 1] = period
    end
  end
  for index, period in ipairs(compact) do
    if not period.name or period.name == "" then period.name = "S" .. index end
  end
  g.config.ratePeriods = compact
  g.config.ratePeriodsMigrated = true
end

function ns.EnsureRatePeriods(g)
  if not g or not g.config then return {} end
  NormalizeRatePeriods(g, ns.GetGuildKey())
  return g.config.ratePeriods
end

function ns.TrackingStart(g)
  local periods = ns.EnsureRatePeriods(g)
  return periods[1] and periods[1].start or g.config.seasonStart
end

function ns.RatePeriodAt(g, weekTs)
  local periods = ns.EnsureRatePeriods(g)
  local selected = periods[1]
  for _, period in ipairs(periods) do
    -- Une semaine utilise le tarif en vigueur a son lundi. Une date d'effet
    -- placee en milieu de semaine ne modifie donc que les semaines suivantes.
    if period.start <= weekTs then selected = period else break end
  end
  return selected
end

function ns.RaidAmountAt(g, weekTs)
  local period = ns.RatePeriodAt(g, weekTs)
  return period and period.amount or g.config.raidAmount or 0
end

function ns.SetRatePeriod(g, startT, amount, name)
  ns.EnsureRatePeriods(g)
  local targetWeek = ns.WeekMonday(startT)
  local kept = {}
  local existingName
  for _, period in ipairs(g.config.ratePeriods) do
    if ns.WeekMonday(period.start) ~= targetWeek then
      kept[#kept + 1] = period
    else
      existingName = period.name
    end
  end
  kept[#kept + 1] = {
    start = startT,
    amount = amount,
    name = (name and name:gsub("^%s+", ""):gsub("%s+$", "")) or existingName
      or ("S" .. (#kept + 1)),
  }
  g.config.ratePeriods = kept
  NormalizeRatePeriods(g, ns.GetGuildKey())
  local current = g.config.ratePeriods[#g.config.ratePeriods]
  if current then
    g.config.seasonStart = current.start
    g.config.raidAmount = current.amount
  end
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
  g.altToMain = g.altToMain or {}
  g.groupDepositOverrides = g.groupDepositOverrides or {}
  -- Migration 1.2.1 : les anciennes corrections de groupe deviennent des
  -- corrections propres au main. Un reroll ne doit jamais etre masque par
  -- une valeur globale qui remplace le total consolide.
  if not g.groupOverridesMigratedToMembers then
    for mainName, weeks in pairs(g.groupDepositOverrides) do
      local mainMember = g.members and g.members[mainName]
      if mainMember then
        mainMember.depositOverrides = mainMember.depositOverrides or {}
        for weekTs, amount in pairs(weeks) do
          if mainMember.depositOverrides[weekTs] == nil then
            mainMember.depositOverrides[weekTs] = amount
          end
        end
      end
    end
    g.groupDepositOverrides = {}
    g.groupOverridesMigratedToMembers = true
  end
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
    NormalizeRatePeriods(g, key)
  end
  return g
end

-- Classification explicite des rangs pour les associations main/reroll.
-- Un rang absent des deux tables reste volontairement "non classe".
function ns.EnsureRankRoles(g)
  if not g then return {}, {} end
  g.config.altRanks = g.config.altRanks or {}
  g.config.mainRanks = g.config.mainRanks or {}
  if not g.config.rankRolesInitialized then
    -- Compatibilite : conserve les rangs rerolls deja choisis, puis classe les
    -- autres rangs actuellement connus comme mains.
    if not g.config.altRanksInitialized then
      for _, member in pairs(g.members or {}) do
        local rank = member.rankName or "?"
        if rank:lower():find("reroll", 1, true) then g.config.altRanks[rank] = true end
      end
    end
    for _, member in pairs(g.members or {}) do
      local rank = member.rankName or "?"
      if not g.config.altRanks[rank] then g.config.mainRanks[rank] = true end
    end
    g.config.altRanksInitialized = true
    g.config.rankRolesInitialized = true
  end
  return g.config.altRanks, g.config.mainRanks
end

function ns.GetRankRole(g, rankName)
  local altRanks, mainRanks = ns.EnsureRankRoles(g)
  if altRanks[rankName or "?"] then return "alt" end
  if mainRanks[rankName or "?"] then return "main" end
  return "unassigned"
end

function ns.SetRankRole(g, rankName, role)
  if not g or not rankName then return end
  local altRanks, mainRanks = ns.EnsureRankRoles(g)
  altRanks[rankName] = nil
  mainRanks[rankName] = nil
  if role == "alt" then altRanks[rankName] = true end
  if role == "main" then mainRanks[rankName] = true end
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

-- Total des raids d'un joueur dans la periode demandee. La borne de debut est
-- ramenee au lundi : la saisie est hebdomadaire, elle ne peut pas couper une
-- semaine en deux lorsque la saison commence en milieu de semaine.
function ns.TotalRaids(g, name, untilT, sinceT)
  local total = 0
  local firstWeek = sinceT and ns.WeekMonday(sinceT) or nil
  for weekTs, players in pairs(g.raids) do
    if (not firstWeek or weekTs >= firstWeek) and (not untilT or weekTs <= untilT) then
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
    m = { rankName = "?", rankIndex = 99, note = "", officerNote = "", startOverride = nil, active = false }
    g.members[shortName] = m
  end
  -- init paresseuse (compatibilite avec les donnees enregistrees avant les retraits)
  m.deposits = m.deposits or {}
  m.withdrawals = m.withdrawals or {}
  m.depositOverrides = m.depositOverrides or {}
  m.officerNote = m.officerNote or ""
  return m
end

function ns.GetRaidsForGroup(g, weekTs, mainName)
  local total = 0
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    total = total + ns.GetRaids(g, weekTs, entry.name)
  end
  return total
end

function ns.TotalRaidsForGroup(g, mainName, untilT, sinceT)
  local total = 0
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    total = total + ns.TotalRaids(g, entry.name, untilT, sinceT)
  end
  return total
end

function ns.TotalOwed(g, name, untilT, sinceT)
  local total = 0
  local firstWeek = sinceT and ns.WeekMonday(sinceT) or nil
  for weekTs, players in pairs(g.raids or {}) do
    if (not firstWeek or weekTs >= firstWeek) and (not untilT or weekTs <= untilT) then
      total = total + (players[name] or 0) * ns.RaidAmountAt(g, weekTs)
    end
  end
  return total
end

function ns.TotalOwedForGroup(g, mainName, untilT, sinceT)
  local total = 0
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    total = total + ns.TotalOwed(g, entry.name, untilT, sinceT)
  end
  return total
end

--------------------------------------------------------------------------------
-- Associations personnages principaux / rerolls
--------------------------------------------------------------------------------

-- Renvoie le main final d'un personnage. La protection visited evite toute boucle.
function ns.ResolveMain(g, name)
  if not g or not name then return name end
  g.altToMain = g.altToMain or {}
  local current = name
  local visited = {}
  while g.altToMain[current] and not visited[current] do
    visited[current] = true
    current = g.altToMain[current]
  end
  return current
end

function ns.IsAlt(g, name)
  return ns.ResolveMain(g, name) ~= name
end

-- Associe un reroll a un main. mainName=nil retire l'association.
function ns.SetCharacterMain(g, altName, mainName)
  if not g or not altName then return false, "invalid" end
  g.altToMain = g.altToMain or {}
  if not mainName or mainName == "" then
    g.altToMain[altName] = nil
    return true
  end
  if altName == mainName then return false, "same" end

  -- Le main choisi est toujours ramene a son propre main final.
  local resolvedMain = ns.ResolveMain(g, mainName)
  if resolvedMain == altName then return false, "cycle" end
  g.altToMain[altName] = resolvedMain
  return true
end

-- Tous les personnages rattaches a un main, main compris.
function ns.GetLinkedCharacters(g, mainName)
  mainName = ns.ResolveMain(g, mainName)
  local list = {}
  for name, m in pairs(g.members or {}) do
    if ns.ResolveMain(g, name) == mainName then
      list[#list + 1] = { name = name, m = m, isMain = (name == mainName) }
    end
  end
  table.sort(list, function(a, b)
    if a.isMain ~= b.isMain then return a.isMain end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

function ns.GetAltCount(g, mainName)
  local count = 0
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    if not entry.isMain then count = count + 1 end
  end
  return count
end
ns.EnsureMember = EnsureMember

-- Debut de suivi d'un membre. Une date individuelle peut repousser l'entree
-- d'une recrue, mais un changement de tarif ne coupe jamais son historique.
function ns.MemberStart(g, m)
  local individual = m and m.startOverride or nil
  local trackingStart = ns.TrackingStart(g)
  if individual and trackingStart then return math.max(individual, trackingStart) end
  return individual or trackingStart
end

--------------------------------------------------------------------------------
-- Scan du roster de guilde
--------------------------------------------------------------------------------

-- Lit le roster et reconcilie la liste des membres connus avec la guilde reelle.
--
-- Piege important : GetGuildRosterInfo n'indexe que les membres actuellement
-- AFFICHES. Quand l'affichage des hors-ligne est desactive, la boucle ne voit
-- que les connectes, et conclure "les autres sont partis" viderait la guilde.
-- On ne marque donc un depart que si le roster lu est complet, c'est-a-dire si
-- l'on a effectivement obtenu autant de noms que le total annonce par le
-- serveur. Sinon on se contente de rafraichir ceux que l'on a vus.
--
-- Renvoie : roster complet (bool), nb de departs detectes, nb de retours.
function ns.ScanRoster()
  local g = ns.GetGuildDB(true)
  if not g then return false, 0, 0 end

  local numTotal = GetNumGuildMembers()
  local present, seen = {}, 0

  for i = 1, (numTotal or 0) do
    local name, rankName, rankIndex, _, _, _, note, officerNote = GetGuildRosterInfo(i)
    if name then
      local short = ns.ShortName(name)
      local m = EnsureMember(g, short)
      m.rankName = rankName or m.rankName
      m.rankIndex = rankIndex or m.rankIndex
      if note and note ~= "" then m.note = note end
      if officerNote and officerNote ~= "" then m.officerNote = officerNote end
      present[short] = true
      seen = seen + 1
    end
  end

  local complete = (numTotal or 0) > 0 and seen == numTotal
  local departures, returns = 0, 0

  for name, m in pairs(g.members) do
    if present[name] then
      m.active = true
      -- Un retour dans la guilde annule le depart sans toucher a l'historique.
      if m.leftAt then
        m.leftAt = nil
        returns = returns + 1
      end
    elseif complete then
      m.active = false
      if not m.leftAt then
        m.leftAt = time()
        departures = departures + 1
      end
    end
  end

  g.rosterComplete = complete
  if complete then g.rosterCheckedAt = time() end

  if ns.RefreshUI then ns.RefreshUI() end
  return complete, departures, returns
end

--------------------------------------------------------------------------------
-- Anciens membres
--------------------------------------------------------------------------------

-- Un membre parti reste en base : son historique de depots fait partie de la
-- comptabilite. Il est simplement masque, et purgeable explicitement.
function ns.IsFormerMember(m)
  return m ~= nil and m.leftAt ~= nil
end

function ns.ShowFormerMembers()
  local settings = GuildCotizDB and GuildCotizDB.settings
  return settings ~= nil and settings.showFormerMembers == true
end

function ns.GetFormerMembers(g)
  local out = {}
  for name, m in pairs((g or {}).members or {}) do
    if m.leftAt then
      out[#out + 1] = { name = name, m = m, leftAt = m.leftAt, deposits = #(m.deposits or {}) }
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- Efface definitivement un ancien membre : sa fiche, ses liens main/reroll et
-- ses presences saisies. Les rerolls qui lui etaient rattaches sont detaches
-- plutot que supprimes, pour ne jamais perdre de donnees en cascade.
function ns.PurgeFormerMember(g, name)
  local m = g and g.members and g.members[name]
  if not m or not m.leftAt then return false end

  g.altToMain = g.altToMain or {}
  g.altToMain[name] = nil
  for altName, mainName in pairs(g.altToMain) do
    if mainName == name then g.altToMain[altName] = nil end
  end

  for weekTs, players in pairs(g.raids or {}) do
    if players[name] then
      players[name] = nil
      if next(players) == nil then g.raids[weekTs] = nil end
    end
  end

  g.members[name] = nil
  return true
end

-- Purge tous les anciens membres. onlyWithoutDeposits limite la purge a ceux qui
-- n'ont jamais rien depose, ce qui est le cas sans risque comptable.
function ns.PurgeFormerMembers(g, onlyWithoutDeposits)
  local removed = 0
  for _, entry in ipairs(ns.GetFormerMembers(g)) do
    if not onlyWithoutDeposits or entry.deposits == 0 then
      if ns.PurgeFormerMember(g, entry.name) then removed = removed + 1 end
    end
  end
  if removed > 0 and ns.RefreshUI then ns.RefreshUI() end
  return removed
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
ns.DedupKey = DedupKey

-- Fenetre de rapprochement de deux enregistrements d'une meme transaction reelle.
--
-- WoW n'exprime l'anciennete d'une transaction qu'en heures entieres : un client
-- qui scanne calcule absTime = maintenant - anciennete_tronquee, soit l'instant
-- reel majore de 0 a 1 heure. Deux officiers qui scannent le meme depot a des
-- moments differents obtiennent donc deux timestamps distants de moins d'une
-- heure, quelle que soit la date du scan. 90 minutes couvrent ce decalage avec
-- de la marge, tout en restant bien plus strict que le bucket d'un jour utilise
-- par DedupKey.
ns.MATCH_WINDOW = 90 * 60

-- Rapproche une serie d'observations avec ce qui est deja enregistre.
--
-- WoW n'exprime l'anciennete d'une transaction qu'en unites entieres, la plus
-- fine etant l'heure. Deux depots identiques faits par le meme joueur dans la
-- meme heure sont donc rigoureusement indiscernables par leur contenu : seul le
-- NOMBRE de lignes du journal les distingue d'un unique depot relu deux fois.
-- Rapprocher "par existence" perdait donc toujours le second.
--
-- On compare donc des SUITES, pas des ensembles. Les deux listes sont
-- parcourues dans l'ordre chronologique et chaque entree deja connue n'est
-- consommee qu'une seule fois. Deux operations identiques restent deux
-- operations, alors qu'un meme journal relu n'ajoute rien.
--
-- observed est indexe par montant : { [montant] = { instant, instant, ... } }.
-- kind vaut nil pour les depots, sinon le type de sortie, et ne rapproche alors
-- que les entrees du meme type.
--
-- Renvoie le nombre d'entrees ajoutees et un booleen "donnees modifiees".
function ns.ReconcileTransactions(stored, observed, kind, window)
  window = window or ns.MATCH_WINDOW
  local added, changed = 0, false

  local byAmount = {}
  for _, entry in ipairs(stored) do
    if entry.kind == kind then
      local slot = byAmount[entry.a]
      if not slot then slot = {}; byAmount[entry.a] = slot end
      slot[#slot + 1] = entry
    end
  end
  for _, slot in pairs(byAmount) do
    table.sort(slot, function(x, y) return (x.t or 0) < (y.t or 0) end)
  end

  for amount, times in pairs(observed) do
    table.sort(times)
    local slot = byAmount[amount] or {}
    local cursor = 1
    for _, t in ipairs(times) do
      -- Les entrees trop anciennes pour correspondre sont definitivement passees.
      while slot[cursor] and slot[cursor].t < (t - window) do
        cursor = cursor + 1
      end
      local match = slot[cursor]
      if match and math.abs(match.t - t) <= window then
        -- Horodatage retenu : le plus petit des deux. Tout enregistrement majore
        -- l'instant reel de 0 a 1 heure, donc le minimum est le plus proche de la
        -- verite ; c'est aussi une operation deterministe, ce qui fait converger
        -- tous les officiers vers la meme valeur.
        if t < match.t then match.t = t; changed = true end
        cursor = cursor + 1
      else
        if kind then
          stored[#stored + 1] = { t = t, a = amount, kind = kind }
        else
          stored[#stored + 1] = { t = t, a = amount }
        end
        added = added + 1
      end
    end
  end

  return added, changed
end

-- Lit le journal d'or (le coffre doit etre ouvert). Renvoie le nb de nouveaux depots.
function ns.ScanBankLog()
  if not GetNumGuildBankMoneyTransactions or not GetGuildBankMoneyTransaction then
    return 0, L("BANK_API_UNAVAILABLE")
  end
  local g = ns.GetGuildDB(true)
  if not g then return 0, L("NOT_IN_GUILD") end

  local now = time()
  local count = GetNumGuildBankMoneyTransactions()
  local added = 0
  local addedW = 0
  local changed = false

  -- Le journal est d'abord lu en entier, puis regroupe par joueur et par
  -- montant. C'est le nombre de lignes qui distingue deux operations identiques
  -- d'une seule relue : traiter les lignes une par une perdrait cette
  -- information.
  local deposits = {}     -- [joueur] = { [montant] = { instants } }
  local withdrawals = {}  -- [joueur] = { [type] = { [montant] = { instants } } }

  local function push(bucket, amount, absTime)
    local slot = bucket[amount]
    if not slot then slot = {}; bucket[amount] = slot end
    slot[#slot + 1] = absTime
  end

  for i = 1, count do
    local txType, name, amount, years, months, days, hours = GetGuildBankMoneyTransaction(i)
    if name and amount and amount > 0 then
      local short = ns.ShortName(name)
      local absTime = now - ElapsedToSeconds(years, months, days, hours)

      -- Seuls les depots comptent comme cotisation.
      if txType == "deposit" then
        deposits[short] = deposits[short] or {}
        push(deposits[short], amount, absTime)

      -- Les sorties d'or sont enregistrees a part (onglet Retraits), jamais en cotisation
      elseif ns.WITHDRAW_TYPES[txType] then
        withdrawals[short] = withdrawals[short] or {}
        withdrawals[short][txType] = withdrawals[short][txType] or {}
        push(withdrawals[short][txType], amount, absTime)
      end
    end
  end

  for short, observed in pairs(deposits) do
    local m = EnsureMember(g, short)
    local n, touched = ns.ReconcileTransactions(m.deposits, observed, nil)
    added = added + n
    changed = changed or touched
  end

  for short, byKind in pairs(withdrawals) do
    local m = EnsureMember(g, short)
    for txType, observed in pairs(byKind) do
      local n, touched = ns.ReconcileTransactions(m.withdrawals, observed, txType)
      addedW = addedW + n
      changed = changed or touched
    end
  end

  -- tri par date pour l'historique
  if added > 0 or addedW > 0 or changed then
    for _, m in pairs(g.members) do
      if m.deposits then table.sort(m.deposits, function(a, b) return a.t < b.t end) end
      if m.withdrawals then table.sort(m.withdrawals, function(a, b) return a.t < b.t end) end
    end
  end

  -- Un scan qui apporte du neuf est le bon moment pour proposer ces donnees
  -- aux autres officiers : leur journal a peut-etre deja perdu ces lignes.
  if (added > 0 or addedW > 0) and ns.Sync then ns.Sync.Schedule(8) end

  if ns.RefreshUI then ns.RefreshUI() end
  return added, nil, addedW
end

-- Remet l'historique en ordre et reconstruit l'index de deduplication.
--
-- Cette commande supprimait auparavant toute transaction partageant nom, montant
-- et jour avec une autre. C'est precisement ce qui rendait invisible un joueur
-- deposant deux fois le meme montant dans la journee : ces deux depots sont
-- legitimes et indiscernables d'un doublon. Puisque rien dans les donnees ne
-- permet de trancher, la commande ne supprime plus rien ; le rapprochement par
-- suites empeche desormais les doublons d'apparaitre a la source.
--
-- Renvoie le nombre de transactions conservees.
function ns.Deduplicate()
  local g = ns.GetGuildDB(true)
  if not g then return 0 end
  g.seen = {}
  local kept = 0

  for name, m in pairs(g.members) do
    for _, d in ipairs(m.deposits or {}) do
      g.seen[DedupKey(name, d.a, d.t)] = true
      kept = kept + 1
    end
    for _, w in ipairs(m.withdrawals or {}) do
      g.seen["W|" .. DedupKey(name, w.a, w.t)] = true
      kept = kept + 1
    end
    if m.deposits then table.sort(m.deposits, function(a, b) return a.t < b.t end) end
    if m.withdrawals then table.sort(m.withdrawals, function(a, b) return a.t < b.t end) end
  end

  if ns.RefreshUI then ns.RefreshUI() end
  return kept
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

-- Total brut detecte dans le journal pour une semaine.
function ns.GetBankDepositedForWeek(m, weekTs, startT, untilT)
  local weekEnd = weekTs + WEEK_SECONDS
  local total = 0
  for _, d in ipairs(m.deposits or {}) do
    if d.t >= weekTs and d.t < weekEnd
      and (not startT or d.t >= startT)
      and (not untilT or d.t <= untilT) then
      total = total + d.a
    end
  end
  return total
end

-- Montant effectif d'une semaine : correction manuelle si presente, sinon journal.
function ns.GetDepositedForWeek(m, weekTs, startT, untilT)
  m.depositOverrides = m.depositOverrides or {}
  local override = m.depositOverrides[weekTs]
  if override ~= nil then return override, true end
  return ns.GetBankDepositedForWeek(m, weekTs, startT, untilT), false
end

-- Definit une correction en cuivre. nil restaure la valeur issue du journal.
function ns.SetDepositOverride(m, weekTs, copper)
  m.depositOverrides = m.depositOverrides or {}
  if copper == nil then
    m.depositOverrides[weekTs] = nil
  else
    m.depositOverrides[weekTs] = math.max(0, math.floor(tonumber(copper) or 0))
  end
end

-- Total depose par un membre depuis son debut de suivi, corrections comprises.
-- untilT : si fourni, ne compte que les depots effectues jusqu'a cette date (vue historique).
function ns.TotalPaid(g, m, untilT)
  local startT = ns.MemberStart(g, m)
  local total = 0
  for _, d in ipairs(m.deposits or {}) do
    if (not startT or d.t >= startT) and (not untilT or d.t <= untilT) then
      total = total + d.a
    end
  end

  -- Une correction remplace le total brut de sa semaine, elle ne s'y ajoute pas.
  for weekTs, override in pairs(m.depositOverrides or {}) do
    local weekEnd = weekTs + WEEK_SECONDS
    if (not startT or weekEnd > startT) and (not untilT or weekTs <= untilT) then
      local raw = ns.GetBankDepositedForWeek(m, weekTs, startT, untilT)
      total = total - raw + override
    end
  end
  return total
end

-- Total cumule du main et de tous ses rerolls.
function ns.TotalPaidForGroup(g, mainName, untilT)
  mainName = ns.ResolveMain(g, mainName)
  local total = 0
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    total = total + ns.TotalPaid(g, entry.m, untilT)
  end

  return total
end

function ns.GetGroupDepositOverride(g, mainName, weekTs)
  mainName = ns.ResolveMain(g, mainName)
  local byMain = g.groupDepositOverrides and g.groupDepositOverrides[mainName]
  if byMain and byMain[weekTs] ~= nil then return byMain[weekTs], true end
  return nil, false
end

function ns.SetGroupDepositOverride(g, mainName, weekTs, copper)
  mainName = ns.ResolveMain(g, mainName)
  g.groupDepositOverrides = g.groupDepositOverrides or {}
  g.groupDepositOverrides[mainName] = g.groupDepositOverrides[mainName] or {}
  if copper == nil then
    g.groupDepositOverrides[mainName][weekTs] = nil
    if next(g.groupDepositOverrides[mainName]) == nil then
      g.groupDepositOverrides[mainName] = nil
    end
  else
    g.groupDepositOverrides[mainName][weekTs] = math.max(0, math.floor(tonumber(copper) or 0))
  end
end

-- Detail des depots par personnage pour une semaine.
function ns.GetGroupDepositsForWeek(g, mainName, weekTs, untilT)
  local rows = {}
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    local startT = ns.MemberStart(g, entry.m)
    local amount, overridden = ns.GetDepositedForWeek(entry.m, weekTs, startT, untilT)
    rows[#rows + 1] = {
      name = entry.name,
      m = entry.m,
      amount = amount,
      overridden = overridden,
      isMain = entry.isMain,
    }
  end
  return rows
end

-- Transactions originales, conservees meme lorsqu'une correction manuelle existe.
function ns.GetDepositTransactionsForGroup(g, mainName)
  local rows = {}
  for _, entry in ipairs(ns.GetLinkedCharacters(g, mainName)) do
    for _, deposit in ipairs(entry.m.deposits or {}) do
      rows[#rows + 1] = {
        name = entry.name,
        mainName = ns.ResolveMain(g, entry.name),
        t = deposit.t,
        a = deposit.a,
      }
    end
  end
  table.sort(rows, function(a, b) return a.t > b.t end)
  return rows
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
  name = ns.ResolveMain(g, name)
  m = g.members[name] or m
  local startT = ns.MemberStart(g, m)
  local raids = ns.TotalRaidsForGroup(g, name, now, startT)
  local owed = ns.TotalOwedForGroup(g, name, now, startT)
  local paid = ns.TotalPaidForGroup(g, name, now)
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
  name = ns.ResolveMain(g, name)
  m = g.members[name] or m
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

    local raids = ns.GetRaidsForGroup(g, ws, name)
    local ratePeriod = ns.RatePeriodAt(g, ws)
    local weekRate = ratePeriod and ratePeriod.amount or g.config.raidAmount or 0
    local dueWeek = raids * weekRate

    local deposited, depositOverridden = 0, false
    local depositDetails = ns.GetGroupDepositsForWeek(g, name, ws, now)
    for _, detail in ipairs(depositDetails) do
      deposited = deposited + detail.amount
      if detail.overridden then depositOverridden = true end
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
      raids = raids, seasonName = ratePeriod and ratePeriod.name or "",
      raidAmount = weekRate, dueWeek = dueWeek, deposited = deposited,
      depositOverridden = depositOverridden,
      depositDetails = depositDetails,
      cumRaids = cumRaids, cumOwed = cumOwed, cumPaid = cumPaid,
      balanceEnd = balanceEnd, status = st,
    }
    ws = we
  end
  return rows
end

-- Statut et detail propres a un seul personnage, sans fusion avec son main.
function ns.GetIndividualStatus(g, m, name, now)
  now = now or time()
  local perRaid = g.config.raidAmount or 0
  local startT = ns.MemberStart(g, m)
  local raids = ns.TotalRaids(g, name, now, startT)
  local paid = ns.TotalPaid(g, m, now)
  local owed = ns.TotalOwed(g, name, now, startT)
  local balance = paid - owed
  local raidsCovered = (perRaid > 0) and math.floor(paid / perRaid) or 0
  local raidsBehind = balance < 0 and ((perRaid > 0) and math.ceil(-balance / perRaid) or 0) or 0
  local raidsAhead = balance >= 0 and math.max(0, raidsCovered - raids) or 0
  return {
    perRaid = perRaid, startT = startT, raids = raids, owed = owed,
    paid = paid, balance = balance, raidsCovered = raidsCovered,
    status = balance < 0 and "retard" or (raidsAhead > 0 and "avance" or "ajour"),
    raidsBehind = raidsBehind, raidsAhead = raidsAhead, due = math.max(0, -balance),
  }
end

function ns.GetIndividualWeeklyBreakdown(g, m, name, now)
  now = now or time()
  local perRaid = g.config.raidAmount or 0
  local startT = ns.MemberStart(g, m)
  local rows = {}
  if not startT then return rows end
  local ws, lastMonday = ns.WeekMonday(startT), ns.WeekMonday(now)
  local cumPaid, cumOwed, cumRaids, index = 0, 0, 0, 0
  while ws <= lastMonday do
    local we = ws + WEEK_SECONDS
    index = index + 1
    local raids = ns.GetRaids(g, ws, name)
    local ratePeriod = ns.RatePeriodAt(g, ws)
    local weekRate = ratePeriod and ratePeriod.amount or g.config.raidAmount or 0
    local dueWeek = raids * weekRate
    local deposited, overridden = ns.GetDepositedForWeek(m, ws, startT, now)
    cumRaids = cumRaids + raids
    cumOwed = cumOwed + dueWeek
    cumPaid = cumPaid + deposited
    local balanceEnd = cumPaid - cumOwed
    local status
    if raids == 0 and deposited == 0 then
      status = "norraid"
    elseif balanceEnd >= 0 then
      status = deposited > 0 and "paye" or "couvert"
    else
      status = "nonpaye"
    end
    rows[#rows + 1] = {
      index = index, weekStart = ws, weekEnd = we, raids = raids,
      seasonName = ratePeriod and ratePeriod.name or "", raidAmount = weekRate,
      dueWeek = dueWeek, deposited = deposited, depositOverridden = overridden,
      depositDetails = { { name = name, m = m, amount = deposited, overridden = overridden } },
      cumRaids = cumRaids, cumOwed = cumOwed, cumPaid = cumPaid,
      balanceEnd = balanceEnd, status = status,
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
  local showFormer = opts.includeFormer or ns.ShowFormerMembers()
  local list = {}
  for name, m in pairs(g.members) do
    local visible = opts.includeInactive or m.active or #m.deposits > 0
    -- Un ancien membre reste en base mais sort des vues tant que l'officier
    -- n'a pas demande a les voir.
    if visible and (showFormer or not m.leftAt) then
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
    -- Laisse le roster et la guilde se charger avant de parler aux autres.
    if ns.Sync then ns.Sync.Schedule(20) end

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
      print("|cff33ff99GuildCotiz|r : " .. L("BANK_SCAN_RESULT", added or 0, addedW or 0))
    end
  end
end)

ns.eventFrame = f

--------------------------------------------------------------------------------
-- Diagnostic (/cotiz debug)
--------------------------------------------------------------------------------
function ns.DebugDump()
  local p = function(...) print("|cff33ff99GuildCotiz|r " .. string.format(...)) end
  p(L("DEBUG_START"))
  p(L("DEBUG_GUILD"), tostring(IsInGuild()), tostring(ns.GetGuildKey()))
  p(L("DEBUG_API_COUNT"), tostring(GetNumGuildBankMoneyTransactions ~= nil))
  p(L("DEBUG_API_TRANSACTION"), tostring(GetGuildBankMoneyTransaction ~= nil))

  if GetNumGuildBankMoneyTransactions then
    local n = GetNumGuildBankMoneyTransactions()
    p(L("DEBUG_TRANSACTIONS"), n or 0)
    for i = 1, math.min(n or 0, 8) do
      local t, name, amount, y, mo, d, h = GetGuildBankMoneyTransaction(i)
      p(L("DEBUG_TRANSACTION_LINE"),
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
    p(L("DEBUG_MEMBERS"), nm, nd)
    p(L("DEBUG_CONFIG"),
      ns.TrackingStart(g) and date("%Y-%m-%d", ns.TrackingStart(g)) or "?",
      ns.FormatGold(g.config.raidAmount))
    -- detail du joueur courant
    local me = ns.ShortName(UnitName("player"))
    local mine = g.members[me]
    if mine then
      p(L("DEBUG_SELF"),
        me, #mine.deposits, ns.FormatGold(ns.TotalPaid(g, mine)))
      for _, d in ipairs(mine.deposits) do
        p(L("DEBUG_DEPOSIT"),
          ns.FormatGold(d.a), date("%Y-%m-%d %H:%M", d.t),
          (ns.TrackingStart(g) and d.t >= ns.TrackingStart(g))
            and L("DEBUG_AFTER") or L("DEBUG_BEFORE"))
      end
    else
      p(L("DEBUG_NO_SELF"), me)
    end
  end
  p(L("DEBUG_END"))
end
