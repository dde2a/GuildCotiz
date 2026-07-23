-- GuildCotiz - UI.lua
-- Fenetre principale : vue resume (tous les membres) et vue detail (semaine par semaine),
-- filtre par joueur, reglages, et boutons d'export. Affichage en tableau (colonnes).

local ADDON, ns = ...

local ROW_HEIGHT = 20
local NUM_ROWS = 16
local MAX_CELLS = 8

local UI = {}
ns.UI = UI

local mainFrame
local mode = "summary"        -- "summary" | "detail"
local filterText = ""         -- filtre par nom de joueur
local detailPlayer = nil      -- joueur affiche en mode detail
local viewWeekOffset = 0      -- 0 = semaine actuelle, negatif = semaines passees
local selectedWeekMonday      -- lundi (timestamp) de la semaine affichee en vue Resume

--------------------------------------------------------------------------------
-- Definition des colonnes (x = offset depuis la gauche de la ligne, w = largeur)
--------------------------------------------------------------------------------
local COLUMNS = {
  summary = {
    { key = "name",      title = "Joueur",      x = 4,   w = 118, justify = "LEFT" },
    { key = "rank",      title = "Rang",        x = 124, w = 84,  justify = "LEFT" },
    -- colonne editable : nb de raids du joueur sur la semaine selectionnee
    { key = "raidsWeek", title = "Raids sem.",  x = 212, w = 64,  justify = "CENTER", edit = true },
    { key = "raidsTot",  title = "Raids tot.",  x = 282, w = 62,  justify = "RIGHT" },
    { key = "paid",      title = "Depose",      x = 350, w = 88,  justify = "RIGHT" },
    { key = "balance",   title = "Solde",       x = 444, w = 88,  justify = "RIGHT" },
    { key = "status",    title = "Statut",      x = 538, w = 176, justify = "LEFT" },
  },
  detail = {
    { key = "start",   title = "Semaine",    x = 4,   w = 100, justify = "LEFT" },
    { key = "raids",   title = "Raids",      x = 108, w = 48,  justify = "CENTER" },
    { key = "dueweek", title = "Du sem.",    x = 160, w = 88,  justify = "RIGHT" },
    { key = "dep",     title = "Depose",     x = 252, w = 88,  justify = "RIGHT" },
    { key = "cumdue",  title = "Cumul du",   x = 344, w = 96,  justify = "RIGHT" },
    { key = "cumpaid", title = "Cumul paye", x = 444, w = 96,  justify = "RIGHT" },
    { key = "status",  title = "Statut",     x = 544, w = 170, justify = "LEFT" },
  },
  withdraw = {
    { key = "player", title = "Joueur",  x = 4,   w = 130, justify = "LEFT" },
    { key = "rank",   title = "Rang",    x = 136, w = 100, justify = "LEFT" },
    { key = "date",   title = "Date",    x = 240, w = 100, justify = "LEFT" },
    { key = "time",   title = "Heure",   x = 344, w = 60,  justify = "LEFT" },
    { key = "amount", title = "Montant", x = 408, w = 100, justify = "RIGHT" },
    { key = "kind",   title = "Type",    x = 512, w = 130, justify = "LEFT" },
  },
}

--------------------------------------------------------------------------------
-- Couleurs de statut
--------------------------------------------------------------------------------
local STATUS_COLOR = {
  ajour   = { 0.45, 1.0, 0.45 },
  avance  = { 0.45, 0.8, 1.0 },
  retard  = { 1.0, 0.35, 0.35 },
  paye    = { 0.45, 1.0, 0.45 },
  couvert = { 0.6, 0.82, 1.0 },
  nonpaye = { 1.0, 0.35, 0.35 },
  norraid = { 0.55, 0.55, 0.55 },
  -- types de retrait
  withdraw       = { 1.0, 0.6, 0.45 },
  repair         = { 0.95, 0.85, 0.55 },
  withdrawForTab = { 0.8, 0.8, 0.92 },
  buyTab         = { 0.8, 0.8, 0.92 },
}

local function ColorFor(status)
  local c = STATUS_COLOR[status]
  if c then return c[1], c[2], c[3] end
  return 0.95, 0.95, 0.95
end

--------------------------------------------------------------------------------
-- Filtre par rang
--------------------------------------------------------------------------------

-- Liste unique des rangs presents chez les membres, triee par index de rang
local function GetRankList(g)
  local seen, list = {}, {}
  for _, m in pairs(g.members) do
    local rn = m.rankName or "?"
    if not seen[rn] then
      seen[rn] = true
      list[#list + 1] = { name = rn, index = m.rankIndex or 99 }
    end
  end
  table.sort(list, function(a, b)
    if a.index == b.index then return a.name < b.name end
    return a.index < b.index
  end)
  return list
end

-- true si le rang doit etre affiche
local function RankShown(g, rankName)
  local hidden = g.config.hiddenRanks
  return not (hidden and hidden[rankName or "?"])
end

-- Noms des joueurs actuellement visibles en vue Resume (apres filtres nom + rang)
function UI.GetVisiblePlayers()
  local g = ns.GetGuildDB(true)
  if not g then return {} end
  local out = {}
  for _, entry in ipairs(ns.GetSortedMembers(g, { includeInactive = true })) do
    local nameOk = (filterText == "" or entry.name:lower():find(filterText:lower(), 1, true))
    if nameOk and RankShown(g, entry.m.rankName or "?") then
      out[#out + 1] = entry.name
    end
  end
  return out
end

-- Generateur du menu contextuel des rangs (API MenuUtil, retail 12.0)
local function BuildRankMenu(owner, root)
  local g = ns.GetGuildDB(true)
  if not g then return end
  g.config.hiddenRanks = g.config.hiddenRanks or {}
  local ranks = GetRankList(g)

  root:CreateTitle("Rangs a afficher")
  root:CreateButton("Tout cocher", function()
    wipe(g.config.hiddenRanks)
    ns.RefreshUI()
    return MenuResponse.Refresh
  end)
  root:CreateButton("Tout decocher", function()
    for _, r in ipairs(ranks) do g.config.hiddenRanks[r.name] = true end
    ns.RefreshUI()
    return MenuResponse.Refresh
  end)
  root:CreateDivider()

  for _, r in ipairs(ranks) do
    local rn = r.name
    root:CreateCheckbox(rn,
      function() return RankShown(g, rn) end,
      function()
        if g.config.hiddenRanks[rn] then
          g.config.hiddenRanks[rn] = nil
        else
          g.config.hiddenRanks[rn] = true
        end
        ns.RefreshUI()
        return MenuResponse.Refresh
      end)
  end
end

--------------------------------------------------------------------------------
-- Fenetre de saisie personnalisee (montant hebdo, date de debut)
-- On n'utilise pas StaticPopup : son systeme d'EditBox a change en 12.0 et
-- ne se fermait plus de facon fiable.
--------------------------------------------------------------------------------
local inputDialog

local function GetInputDialog()
  if inputDialog then return inputDialog end
  local d = CreateFrame("Frame", "GuildCotizInputDialog", UIParent, "BackdropTemplate")
  d:SetSize(360, 140)
  d:SetPoint("CENTER")
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetToplevel(true)
  d:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:Hide()

  local label = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOP", 0, -22)
  label:SetWidth(320)
  label:SetJustifyH("CENTER")
  d.label = label

  local eb = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
  eb:SetSize(220, 24)
  eb:SetPoint("TOP", label, "BOTTOM", 0, -14)
  eb:SetAutoFocus(true)
  d.editBox = eb

  local function Accept()
    local cb = d.onAccept
    local txt = eb:GetText()
    d:Hide()
    if cb then cb(txt) end
  end

  local ok = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  ok:SetSize(110, 24)
  ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -8, 16)
  ok:SetText("OK")
  ok:SetScript("OnClick", Accept)

  local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  cancel:SetSize(110, 24)
  cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 8, 16)
  cancel:SetText("Annuler")
  cancel:SetScript("OnClick", function() d:Hide() end)

  eb:SetScript("OnEnterPressed", Accept)
  eb:SetScript("OnEscapePressed", function() d:Hide() end)

  tinsert(UISpecialFrames, "GuildCotizInputDialog")
  inputDialog = d
  return d
end

local function ShowInput(labelText, currentText, onAccept)
  local d = GetInputDialog()
  d.label:SetText(labelText)
  d.onAccept = onAccept
  d:Show()
  d.editBox:SetText(currentText or "")
  d.editBox:SetFocus()
  d.editBox:HighlightText()
end

local function PromptWeekly()
  local g = ns.GetGuildDB(true)
  if not g then return end
  local current = tostring(math.floor((g.config.raidAmount or 0) / ns.COPPER_PER_GOLD))
  ShowInput("Cotisation due PAR RAID effectue (en or) :", current, function(txt)
    local gold = tonumber(txt)
    if gold then
      g.config.raidAmount = ns.GoldToCopper(gold)
      ns.RefreshUI()
    end
  end)
end

local function PromptStart()
  local g = ns.GetGuildDB(true)
  if not g then return end
  local current = g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or ""
  ShowInput("Debut de suivi (format AAAA-MM-JJ) :", current, function(txt)
    local y, mo, d = txt:match("(%d+)%-(%d+)%-(%d+)")
    if y then
      g.config.seasonStart = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 })
      ns.RefreshUI()
    end
  end)
end

--------------------------------------------------------------------------------
-- Construction de la fenetre principale
--------------------------------------------------------------------------------
local function BuildFrame()
  local f = CreateFrame("Frame", "GuildCotizFrame", UIParent, "BackdropTemplate")
  f:SetSize(780, 520)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  tinsert(UISpecialFrames, "GuildCotizFrame") -- fermeture avec Echap

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Guild Cotiz")
  f.title = title

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  info:SetPoint("TOPLEFT", 20, -44)
  f.info = info

  local setAmount = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  setAmount:SetSize(130, 22)
  setAmount:SetPoint("TOPRIGHT", -20, -40)
  setAmount:SetText("Montant / raid")
  setAmount:SetScript("OnClick", PromptWeekly)

  local setStart = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  setStart:SetSize(130, 22)
  setStart:SetPoint("RIGHT", setAmount, "LEFT", -6, 0)
  setStart:SetText("Debut de suivi")
  setStart:SetScript("OnClick", PromptStart)

  -- Onglets de mode
  local tabSummary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tabSummary:SetSize(100, 22)
  tabSummary:SetPoint("TOPLEFT", 20, -70)
  tabSummary:SetText("Resume")
  tabSummary:SetScript("OnClick", function()
    f.filter:SetText("") -- affiche a nouveau toute la liste
    UI.SetMode("summary")
  end)
  f.tabSummary = tabSummary

  local tabDetail = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tabDetail:SetSize(130, 22)
  tabDetail:SetPoint("LEFT", tabSummary, "RIGHT", 6, 0)
  tabDetail:SetText("Detail semaine")
  tabDetail:SetScript("OnClick", function() UI.SetMode("detail") end)
  f.tabDetail = tabDetail

  local tabWithdraw = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tabWithdraw:SetSize(100, 22)
  tabWithdraw:SetPoint("LEFT", tabDetail, "RIGHT", 6, 0)
  tabWithdraw:SetText("Retraits")
  tabWithdraw:SetScript("OnClick", function()
    f.filter:SetText("") -- liste complete des retraits
    UI.SetMode("withdraw")
  end)
  f.tabWithdraw = tabWithdraw

  -- Bouton filtre par rang (menu a cases a cocher)
  local rankBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  rankBtn:SetSize(150, 22)
  rankBtn:SetPoint("TOPRIGHT", -20, -70)
  rankBtn:SetText("Rangs")
  rankBtn:SetScript("OnClick", function(self)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, BuildRankMenu)
    else
      print("|cff33ff99GuildCotiz|r : menu des rangs indisponible sur cette version.")
    end
  end)
  f.rankBtn = rankBtn

  -- Barre de navigation semaine (vue Resume) : statut a une semaine donnee
  local weekPrev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  weekPrev:SetSize(40, 22)
  weekPrev:SetPoint("TOPLEFT", 20, -94)
  weekPrev:SetText("<")
  weekPrev:SetScript("OnClick", function()
    viewWeekOffset = viewWeekOffset - 1
    UI.Refresh()
  end)
  f.weekPrev = weekPrev

  local weekLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  weekLabel:SetPoint("LEFT", weekPrev, "RIGHT", 8, 0)
  weekLabel:SetWidth(240)
  weekLabel:SetJustifyH("CENTER")
  f.weekLabel = weekLabel

  local weekNext = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  weekNext:SetSize(40, 22)
  weekNext:SetPoint("LEFT", weekLabel, "RIGHT", 8, 0)
  weekNext:SetText(">")
  weekNext:SetScript("OnClick", function()
    viewWeekOffset = math.min(0, viewWeekOffset + 1)
    UI.Refresh()
  end)
  f.weekNext = weekNext

  local weekNow = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  weekNow:SetSize(90, 22)
  weekNow:SetPoint("LEFT", weekNext, "RIGHT", 12, 0)
  weekNow:SetText("Actuelle")
  weekNow:SetScript("OnClick", function()
    viewWeekOffset = 0
    UI.Refresh()
  end)
  f.weekNow = weekNow

  -- Applique le meme nombre de raids a tous les joueurs actuellement affiches
  local applyAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  applyAll:SetSize(140, 22)
  applyAll:SetPoint("LEFT", weekNow, "RIGHT", 12, 0)
  applyAll:SetText("Appliquer a tous")
  applyAll:SetScript("OnClick", function()
    if not selectedWeekMonday then return end
    ShowInput("Nombre de raids a appliquer a tous les joueurs affiches :", "", function(txt)
      local n = tonumber(txt)
      if not n then return end
      local g = ns.GetGuildDB(true)
      if not g then return end
      local count = 0
      for _, name in ipairs(UI.GetVisiblePlayers()) do
        ns.SetRaids(g, selectedWeekMonday, name, n)
        count = count + 1
      end
      print(string.format("|cff33ff99GuildCotiz|r : %d raid(s) applique(s) a %d joueur(s).", n, count))
      UI.Refresh()
    end)
  end)
  f.applyAll = applyAll

  local weekSub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  weekSub:SetPoint("LEFT", applyAll, "RIGHT", 14, 0)
  f.weekSub = weekSub

  -- Champ de filtre
  local filterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  filterLabel:SetPoint("LEFT", tabWithdraw, "RIGHT", 16, 0)
  filterLabel:SetText("Joueur :")

  local filter = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  filter:SetSize(150, 20)
  filter:SetPoint("LEFT", filterLabel, "RIGHT", 10, 0)
  filter:SetAutoFocus(false)
  filter:SetScript("OnTextChanged", function(self)
    filterText = self:GetText() or ""
    UI.Refresh()
  end)
  filter:SetScript("OnEnterPressed", function(self)
    if (self:GetText() or "") ~= "" then
      UI.SetMode("detail")
    end
    self:ClearFocus()
  end)
  f.filter = filter

  -- Barre d'en-tete du tableau (fond + cellules)
  local headerBar = f:CreateTexture(nil, "ARTWORK")
  headerBar:SetColorTexture(0, 0, 0, 0.35)
  headerBar:SetPoint("TOPLEFT", 18, -124)
  headerBar:SetPoint("TOPRIGHT", -34, -124)
  headerBar:SetHeight(ROW_HEIGHT)
  f.headerBar = headerBar

  f.headerCells = {}
  for i = 1, MAX_CELLS do
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetHeight(ROW_HEIGHT)
    fs:Hide()
    f.headerCells[i] = fs
  end

  -- Zone de liste (scroll)
  local scroll = CreateFrame("ScrollFrame", "GuildCotizListScroll", f, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -144)
  scroll:SetPoint("BOTTOMRIGHT", -34, 50)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UI.Refresh)
  end)
  f.scroll = scroll

  -- Lignes du tableau
  f.rows = {}
  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetHeight(ROW_HEIGHT)
    if i == 1 then
      row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    else
      row:SetPoint("TOPLEFT", f.rows[i - 1], "BOTTOMLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", f.rows[i - 1], "BOTTOMRIGHT", 0, 0)
    end

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    row.hl = hl

    -- cellules (colonnes)
    row.cells = {}
    for c = 1, MAX_CELLS do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetHeight(ROW_HEIGHT)
      fs:Hide()
      row.cells[c] = fs
    end

    -- case de saisie du nombre de raids (colonne editable, vue Resume)
    local raidEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    raidEdit:SetAutoFocus(false)
    raidEdit:SetNumeric(true)
    raidEdit:SetMaxLetters(2)
    raidEdit:SetJustifyH("CENTER")
    raidEdit:SetHeight(18)
    raidEdit:Hide()
    local function CommitRaid(self)
      -- on n'ecrit que si la valeur a reellement change (evite les boucles de refresh)
      local newVal = tonumber(self:GetText()) or 0
      if not self.playerName or not self.weekTs then return end
      if newVal == (self.currentValue or 0) then return end
      local g = ns.GetGuildDB(true)
      if not g then return end
      ns.SetRaids(g, self.weekTs, self.playerName, newVal)
      self.currentValue = newVal
      UI.Refresh()
    end
    raidEdit:SetScript("OnEnterPressed", function(self) CommitRaid(self); self:ClearFocus() end)
    raidEdit:SetScript("OnEditFocusLost", CommitRaid)
    raidEdit:SetScript("OnEscapePressed", function(self)
      self:SetText(tostring(self.currentValue or 0))
      self:ClearFocus()
    end)
    row.raidEdit = raidEdit

    -- texte pleine largeur (messages / synthese)
    local full = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    full:SetPoint("LEFT", 6, 0)
    full:SetPoint("RIGHT", -6, 0)
    full:SetJustifyH("LEFT")
    full:Hide()
    row.full = full

    row:Hide()
    f.rows[i] = row
  end

  -- Boutons du bas
  local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scanBtn:SetSize(170, 24)
  scanBtn:SetPoint("BOTTOMLEFT", 20, 16)
  scanBtn:SetText("Scanner le coffre")
  scanBtn:SetScript("OnClick", function()
    local added, err = ns.ScanBankLog()
    if err then
      print("|cff33ff99GuildCotiz|r : " .. err .. " Ouvre le coffre de guilde d'abord.")
    else
      print(string.format("|cff33ff99GuildCotiz|r : scan termine, %d nouveau(x) depot(s).", added or 0))
    end
  end)

  local exportSummary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  exportSummary:SetSize(150, 24)
  exportSummary:SetPoint("BOTTOMRIGHT", -30, 16)
  exportSummary:SetText("Export resume")
  exportSummary:SetScript("OnClick", function()
    ns.ShowExport(ns.BuildSummaryCSV(), "Export CSV - Resume par joueur")
  end)

  local exportWeekly = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  exportWeekly:SetSize(170, 24)
  exportWeekly:SetPoint("RIGHT", exportSummary, "LEFT", -6, 0)
  exportWeekly:SetText("Export semaine")
  exportWeekly:SetScript("OnClick", function()
    if mode == "withdraw" then
      local only = (filterText ~= "") and filterText or nil
      ns.ShowExport(ns.BuildWithdrawCSV(only),
        only and ("Export CSV - Retraits de " .. only) or "Export CSV - Retraits")
    else
      local only = (mode == "detail") and detailPlayer or nil
      local titleTxt = only and ("Export CSV - Semaines de " .. only) or "Export CSV - Toutes les semaines"
      ns.ShowExport(ns.BuildWeeklyCSV(only), titleTxt)
    end
  end)
  f.exportWeekly = exportWeekly

  mainFrame = f
  return f
end

--------------------------------------------------------------------------------
-- Mise en page des cellules d'en-tete selon le mode
--------------------------------------------------------------------------------
local function LayoutHeader()
  local cols = COLUMNS[mode]
  for i = 1, MAX_CELLS do
    local fs = mainFrame.headerCells[i]
    local col = cols[i]
    if col then
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", mainFrame.headerBar, "LEFT", col.x, 0)
      fs:SetWidth(col.w)
      fs:SetJustifyH(col.justify)
      fs:SetText(col.title)
      fs:SetTextColor(1, 0.82, 0)
      fs:Show()
    else
      fs:Hide()
    end
  end
end

--------------------------------------------------------------------------------
-- Rendu de la barre d'infos
--------------------------------------------------------------------------------
local function UpdateInfoBar()
  local g = ns.GetGuildDB(true)
  if not g then
    mainFrame.info:SetText("|cffff5555Tu n'es pas dans une guilde.|r")
    return
  end
  local perRaid = ns.FormatGold(g.config.raidAmount)
  local startStr = g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or "?"
  mainFrame.info:SetText(string.format(
    "Cotisation : |cffffd700%s|r par raid   |   Debut du suivi : |cff88ccff%s|r",
    perRaid, startStr))
end

--------------------------------------------------------------------------------
-- Barre de navigation semaine : renvoie le temps de reference (fin de semaine choisie)
--------------------------------------------------------------------------------
local function UpdateWeekBar()
  local now = time()
  local widgets = {
    mainFrame.weekPrev, mainFrame.weekNext, mainFrame.weekNow,
    mainFrame.weekLabel, mainFrame.weekSub, mainFrame.applyAll,
  }
  -- La navigation semaine ne concerne que la vue Resume
  if mode ~= "summary" then
    for _, w in ipairs(widgets) do w:Hide() end
    selectedWeekMonday = nil
    return now
  end
  for _, w in ipairs(widgets) do w:Show() end

  local g = ns.GetGuildDB(true)
  local mondayNow = ns.WeekMonday(now)
  local minOffset = 0
  if g and g.config.seasonStart then
    local mondayStart = ns.WeekMonday(g.config.seasonStart)
    minOffset = -math.floor((mondayNow - mondayStart) / ns.WEEK_SECONDS)
  end
  if viewWeekOffset > 0 then viewWeekOffset = 0 end
  if viewWeekOffset < minOffset then viewWeekOffset = minOffset end

  local selMonday = ns.WeekMonday(mondayNow + viewWeekOffset * ns.WEEK_SECONDS)
  local selEnd = selMonday + ns.WEEK_SECONDS - 1
  local refTime = math.min(selEnd, now)
  selectedWeekMonday = selMonday

  local y, wk = ns.ISOWeek(selMonday)
  mainFrame.weekLabel:SetText(string.format("Semaine %d / %d  (%s - %s)",
    wk, y, date("%d/%m", selMonday), date("%d/%m", selEnd)))
  if viewWeekOffset == 0 then
    mainFrame.weekSub:SetText("|cff88ff88Semaine en cours|r")
  else
    mainFrame.weekSub:SetText("Statut au " .. date("%d/%m/%Y", refTime))
  end

  mainFrame.weekPrev:SetEnabled(viewWeekOffset > minOffset)
  mainFrame.weekNext:SetEnabled(viewWeekOffset < 0)
  mainFrame.weekNow:SetEnabled(viewWeekOffset < 0)
  return refTime
end

--------------------------------------------------------------------------------
-- Construction des donnees a afficher (liste d'items)
-- item = { cols = {key=texte}, color = statut, click = nomJoueur }  ou  { full = texte, color = statut }
--------------------------------------------------------------------------------
local function BuildDisplayData(refTime)
  local g = ns.GetGuildDB(true)
  if not g then return {} end
  local now = refTime or time()

  g.config.hiddenRanks = g.config.hiddenRanks or {}

  if mode == "summary" then
    local data = {}
    for _, entry in ipairs(ns.GetSortedMembers(g, { includeInactive = true })) do
      local nameOk = (filterText == "" or entry.name:lower():find(filterText:lower(), 1, true))
      if nameOk and RankShown(g, entry.m.rankName or "?") then
        local s = ns.GetMemberStatus(g, entry.m, entry.name, now)
        local statusStr
        if s.status == "retard" then
          statusStr = string.format("En retard %d raid(s) (%s)", s.raidsBehind, ns.FormatGold(s.due))
        elseif s.status == "avance" then
          statusStr = string.format("En avance %d raid(s)", s.raidsAhead)
        else
          statusStr = "A jour"
        end
        local weekRaids = selectedWeekMonday and ns.GetRaids(g, selectedWeekMonday, entry.name) or 0
        data[#data + 1] = {
          color = s.status,
          click = entry.name,
          player = entry.name,
          raidsWeek = weekRaids,
          cols = {
            name      = entry.name,
            rank      = entry.m.rankName or "?",
            raidsWeek = tostring(weekRaids),
            raidsTot  = tostring(s.raids),
            paid      = ns.FormatGold(s.paid),
            balance   = ns.FormatGold(s.balance),
            status    = statusStr,
          },
        }
      end
    end
    if #data == 0 then
      local hasMembers = next(g.members) ~= nil
      if hasMembers then
        data[1] = { full = "Aucun membre a afficher (verifie le filtre Rangs ou le champ Joueur).", color = nil }
      else
        data[1] = { full = "Aucun membre. Ouvre le coffre de guilde pour enregistrer des depots.", color = nil }
      end
    end
    return data

  elseif mode == "withdraw" then
    -- Sorties d'or du coffre, du plus recent au plus ancien.
    -- Ces montants ne sont jamais comptes dans les cotisations.
    local data = {}
    for _, w in ipairs(ns.GetAllWithdrawals(g)) do
      local nameOk = (filterText == "" or w.name:lower():find(filterText:lower(), 1, true))
      if nameOk and RankShown(g, w.rankName) then
        data[#data + 1] = {
          color = w.kind,
          cols = {
            player = w.name,
            rank   = w.rankName,
            date   = date("%Y-%m-%d", w.t),
            time   = date("%H:%M", w.t),
            amount = ns.FormatGold(w.a),
            kind   = ns.WITHDRAW_TYPES[w.kind] or w.kind or "?",
          },
        }
      end
    end
    if #data == 0 then
      data[1] = { full = "Aucun retrait enregistre. Ouvre le coffre de guilde pour lire le journal.", color = nil }
    end
    return data

  else -- detail : toujours l'historique complet jusqu'a aujourd'hui
    now = time()
    local target = filterText -- le champ 'Joueur' est la seule source
    if not target or target == "" then
      detailPlayer = nil
      return { { full = "Tape un nom dans le champ 'Joueur' puis Entree, ou clique un joueur dans le Resume.", color = nil } }
    end
    local found
    for name, m in pairs(g.members) do
      if name:lower() == target:lower() then found = { name = name, m = m }; break end
    end
    if not found then
      for name, m in pairs(g.members) do
        if name:lower():find(target:lower(), 1, true) then found = { name = name, m = m }; break end
      end
    end
    if not found then
      detailPlayer = nil
      return { { full = "Joueur introuvable : " .. target, color = "retard" } }
    end

    detailPlayer = found.name
    mainFrame.title:SetText("Guild Cotiz - " .. found.name)
    local s = ns.GetMemberStatus(g, found.m, found.name, now)
    local data = {}
    for _, r in ipairs(ns.GetWeeklyBreakdown(g, found.m, found.name, now)) do
      local isoY, wk = ns.ISOWeek(r.weekStart)
      data[#data + 1] = {
        color = r.status,
        cols = {
          start   = string.format("S%d  %s", wk, date("%d/%m", r.weekStart)),
          raids   = tostring(r.raids),
          dueweek = r.dueWeek > 0 and ns.FormatGold(r.dueWeek) or "-",
          dep     = r.deposited > 0 and ns.FormatGold(r.deposited) or "-",
          cumdue  = ns.FormatGold(r.cumOwed),
          cumpaid = ns.FormatGold(r.cumPaid),
          status  = ns.StatusText(r.status),
        },
      }
    end
    -- ligne de synthese
    local summaryLine
    if s.status == "retard" then
      summaryLine = string.format("=> %d raid(s) effectue(s) | en retard de %d raid(s), il manque %s.",
        s.raids, s.raidsBehind, ns.FormatGold(s.due))
    elseif s.status == "avance" then
      summaryLine = string.format("=> %d raid(s) effectue(s) | a jour, %d raid(s) payes d'avance.",
        s.raids, s.raidsAhead)
    else
      summaryLine = string.format("=> %d raid(s) effectue(s) | a jour.", s.raids)
    end
    data[#data + 1] = { full = "" }
    data[#data + 1] = { full = summaryLine, color = s.status }
    return data
  end
end

--------------------------------------------------------------------------------
-- Rafraichissement
--------------------------------------------------------------------------------
function UI.Refresh()
  if not mainFrame or not mainFrame:IsShown() then return end
  UpdateInfoBar()
  LayoutHeader()

  mainFrame.tabSummary:SetEnabled(mode ~= "summary")
  mainFrame.tabDetail:SetEnabled(mode ~= "detail")
  mainFrame.tabWithdraw:SetEnabled(mode ~= "withdraw")
  if mode == "summary" then
    mainFrame.title:SetText("Guild Cotiz")
  elseif mode == "withdraw" then
    mainFrame.title:SetText("Guild Cotiz - Retraits du coffre")
  end

  -- le bouton d'export s'adapte a l'onglet actif
  if mainFrame.exportWeekly then
    mainFrame.exportWeekly:SetText(mode == "withdraw" and "Export retraits" or "Export semaine")
  end

  -- compteur de rangs affiches sur le bouton
  local g0 = ns.GetGuildDB(true)
  if g0 and mainFrame.rankBtn then
    g0.config.hiddenRanks = g0.config.hiddenRanks or {}
    local ranks = GetRankList(g0)
    local shown = 0
    for _, r in ipairs(ranks) do if RankShown(g0, r.name) then shown = shown + 1 end end
    if #ranks > 0 and shown < #ranks then
      mainFrame.rankBtn:SetText(string.format("Rangs (%d/%d)", shown, #ranks))
    else
      mainFrame.rankBtn:SetText("Rangs")
    end
  end

  local refTime = UpdateWeekBar()
  local cols = COLUMNS[mode]
  local data = BuildDisplayData(refTime)
  local scroll = mainFrame.scroll
  FauxScrollFrame_Update(scroll, #data, NUM_ROWS, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(scroll)

  for i = 1, NUM_ROWS do
    local row = mainFrame.rows[i]
    local idx = i + offset
    local item = data[idx]
    if item then
      local r, gg, b = ColorFor(item.color)
      row.bg:SetColorTexture(1, 1, 1, (idx % 2 == 0) and 0.05 or 0)

      if item.full ~= nil then
        row.full:SetText(item.full)
        row.full:SetTextColor(r, gg, b)
        row.full:Show()
        for c = 1, MAX_CELLS do row.cells[c]:Hide() end
        row.raidEdit:Hide()
        row:SetScript("OnClick", nil)
        row.hl:SetAlpha(0)
      else
        row.full:Hide()
        local editShown = false
        for c = 1, MAX_CELLS do
          local cell = row.cells[c]
          local col = cols[c]
          if col and col.edit and item.player then
            -- colonne editable : case de saisie a la place du texte
            cell:Hide()
            local eb = row.raidEdit
            eb:ClearAllPoints()
            eb:SetPoint("LEFT", row, "LEFT", col.x + 8, 0)
            eb:SetWidth(col.w - 14)
            -- on ne rebinde pas une case en cours d'edition (sinon on ecrirait sur le mauvais joueur)
            if not eb:HasFocus() then
              eb.playerName = item.player
              eb.weekTs = selectedWeekMonday
              eb.currentValue = item.raidsWeek or 0
              eb:SetText(tostring(item.raidsWeek or 0))
            end
            eb:Show()
            editShown = true
          elseif col then
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", col.x, 0)
            cell:SetWidth(col.w)
            cell:SetJustifyH(col.justify)
            cell:SetText(item.cols[col.key] or "")
            cell:SetTextColor(r, gg, b)
            cell:Show()
          else
            cell:Hide()
          end
        end
        if not editShown then row.raidEdit:Hide() end
        if item.click then
          local playerName = item.click
          row:SetScript("OnClick", function()
            mainFrame.filter:SetText(playerName) -- alimente le champ 'Joueur'
            UI.SetMode("detail")
          end)
          row.hl:SetAlpha(1)
        else
          row:SetScript("OnClick", nil)
          row.hl:SetAlpha(0)
        end
      end
      row:Show()
    else
      row:Hide()
      row:SetScript("OnClick", nil)
    end
  end
end

function UI.SetMode(m)
  mode = m
  if mainFrame and mainFrame.scroll then
    FauxScrollFrame_SetOffset(mainFrame.scroll, 0)
    local sb = mainFrame.scroll.ScrollBar or _G["GuildCotizListScrollScrollBar"]
    if sb and sb.SetValue then sb:SetValue(0) end
  end
  UI.Refresh()
end

function UI.Toggle()
  if not mainFrame then BuildFrame() end
  if mainFrame:IsShown() then
    mainFrame:Hide()
  else
    mainFrame:Show()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    ns.ScanRoster()
    UI.Refresh()
  end
end

function ns.RefreshUI()
  if UI.Refresh then UI.Refresh() end
end

--------------------------------------------------------------------------------
-- Commandes /cotiz
--------------------------------------------------------------------------------
SLASH_GUILDCOTIZ1 = "/cotiz"
SLASH_GUILDCOTIZ2 = "/gc"
SlashCmdList["GUILDCOTIZ"] = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()

  if cmd == "" or cmd == "show" then
    UI.Toggle()
  elseif cmd == "set" then
    local gold = tonumber(rest)
    local g = ns.GetGuildDB(true)
    if g and gold then
      g.config.raidAmount = ns.GoldToCopper(gold)
      print(string.format("|cff33ff99GuildCotiz|r : cotisation = %d po par raid.", gold))
      ns.RefreshUI()
    else
      print("|cff33ff99GuildCotiz|r : usage /cotiz set <montant en or par raid>")
    end
  elseif cmd == "start" then
    local g = ns.GetGuildDB(true)
    if g then
      local y, mo, d = rest:match("(%d+)%-(%d+)%-(%d+)")
      if y then
        g.config.seasonStart = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 })
      elseif rest:lower() == "auto" or rest:lower() == "first" then
        local e = ns.EarliestDeposit(g)
        if e then
          g.config.seasonStart = e - (e % 86400)
        else
          print("|cff33ff99GuildCotiz|r : aucun depot enregistre pour l'instant.")
          return
        end
      else
        local now = time()
        g.config.seasonStart = now - (now % 86400)
      end
      print("|cff33ff99GuildCotiz|r : debut de suivi = " .. date("%Y-%m-%d", g.config.seasonStart))
      ns.RefreshUI()
    end
  elseif cmd == "scan" then
    local added, err = ns.ScanBankLog()
    if err then print("|cff33ff99GuildCotiz|r : " .. err)
    else print(string.format("|cff33ff99GuildCotiz|r : %d nouveau(x) depot(s).", added or 0)) end
  elseif cmd == "fix" then
    local removed = ns.Deduplicate()
    print(string.format("|cff33ff99GuildCotiz|r : %d doublon(s) supprime(s).", removed))
  elseif cmd == "export" then
    ns.ShowExport(ns.BuildSummaryCSV(), "Export CSV - Resume par joueur")
  elseif cmd == "debug" then
    ns.DebugDump()
  else
    print("|cff33ff99GuildCotiz|r commandes :")
    print("  /cotiz            ouvre la fenetre")
    print("  /cotiz set <or>   definit la cotisation hebdomadaire")
    print("  /cotiz start [AAAA-MM-JJ]  definit le debut du suivi (defaut: aujourd'hui)")
    print("  /cotiz start auto un debut au plus ancien depot connu")
    print("  /cotiz scan       lit le journal du coffre (coffre ouvert requis)")
    print("  /cotiz fix        supprime les doublons de depots deja enregistres")
    print("  /cotiz export     ouvre l'export CSV")
    print("  /cotiz debug      diagnostic (a lancer coffre ouvert)")
  end
end
