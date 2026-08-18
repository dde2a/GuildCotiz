-- GuildCotiz - UI.lua
-- Fenetre principale : vue resume (tous les membres) et vue detail (semaine par semaine),
-- filtre par joueur, reglages, et boutons d'export. Affichage en tableau (colonnes).

local ADDON, ns = ...
local L = ns.L

local ROW_HEIGHT = 20
local NUM_ROWS = 16
local MAX_CELLS = 8

local UI = {}
ns.UI = UI

local mainFrame
local mode = "summary"        -- "summary" | "detail"
local filterText = ""         -- filtre par nom de joueur
local detailPlayer = nil      -- joueur affiche en mode detail
local detailIsGroup = true    -- main = vue consolidee ; reroll = vue individuelle
local viewWeekOffset = 0      -- 0 = semaine actuelle, negatif = semaines passees
local selectedWeekMonday      -- lundi (timestamp) de la semaine affichee en vue Resume
local expandedMains = {}      -- [nomMain] = true lorsque les rerolls sont deplies
local cachedDisplayData       -- reutilise pendant le scroll pour ne pas recalculer toute la guilde
local cachedColumns
local sortState = {
  summary = { key = "name", ascending = true },
  detail = { key = "start", ascending = false },
  withdraw = { key = "date", ascending = false },
}

--------------------------------------------------------------------------------
-- Definition des colonnes (x = offset depuis la gauche de la ligne, w = largeur)
--------------------------------------------------------------------------------
local COLUMNS = {
  summary = {
    { key = "name",      title = L("COL_PLAYER"),      x = 4,   w = 154, justify = "LEFT" },
    { key = "rank",      title = L("COL_RANK"),        x = 160, w = 88,  justify = "LEFT" },
    -- colonne editable : nb de raids du joueur sur la semaine selectionnee
    { key = "raidsWeek", title = L("COL_RAIDS_WEEK"),  x = 252, w = 64,  justify = "CENTER", edit = "raid" },
    { key = "raidsTot",  title = L("COL_RAIDS_TOTAL"), x = 320, w = 62,  justify = "RIGHT" },
    { key = "paid",      title = L("COL_DEPOSITED"),   x = 388, w = 88,  justify = "RIGHT", edit = "deposit" },
    { key = "balance",   title = L("COL_BALANCE"),     x = 482, w = 88,  justify = "RIGHT" },
    { key = "status",    title = L("COL_STATUS"),      x = 576, w = 138, justify = "LEFT" },
  },
  detail = {
    { key = "start",   title = L("COL_WEEK"),       x = 4,   w = 100, justify = "LEFT" },
    { key = "raids",   title = L("COL_RAIDS"),      x = 108, w = 48,  justify = "CENTER" },
    { key = "dueweek", title = L("COL_DUE_WEEK"),   x = 160, w = 88,  justify = "RIGHT" },
    { key = "dep",     title = L("COL_DEPOSITED"),  x = 252, w = 88,  justify = "RIGHT", edit = "deposit" },
    { key = "cumdue",  title = L("COL_TOTAL_DUE"),  x = 344, w = 96,  justify = "RIGHT" },
    { key = "cumpaid", title = L("COL_TOTAL_PAID"), x = 444, w = 96,  justify = "RIGHT" },
    { key = "status",  title = L("COL_STATUS"),     x = 544, w = 170, justify = "LEFT" },
  },
  withdraw = {
    { key = "player", title = L("COL_PLAYER"), x = 4,   w = 130, justify = "LEFT" },
    { key = "rank",   title = L("COL_RANK"),   x = 136, w = 100, justify = "LEFT" },
    { key = "date",   title = L("COL_DATE"),   x = 240, w = 100, justify = "LEFT" },
    { key = "time",   title = L("COL_TIME"),   x = 344, w = 60,  justify = "LEFT" },
    { key = "amount", title = L("COL_AMOUNT"), x = 408, w = 100, justify = "RIGHT" },
    { key = "kind",   title = L("COL_TYPE"),   x = 512, w = 130, justify = "LEFT" },
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
    local isMain = not ns.IsAlt(g, entry.name)
    local nameOk = (filterText == "" or entry.name:lower():find(filterText:lower(), 1, true))
    if isMain and nameOk and RankShown(g, entry.m.rankName or "?") then
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

  root:CreateTitle(L("RANKS_TO_SHOW"))
  root:CreateButton(L("CHECK_ALL"), function()
    wipe(g.config.hiddenRanks)
    ns.RefreshUI()
    return MenuResponse.Refresh
  end)
  root:CreateButton(L("UNCHECK_ALL"), function()
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

  -- Les membres partis sont un filtre d'affichage comme les rangs, et la barre
  -- d'outils n'a pas la largeur d'une case supplementaire.
  root:CreateDivider()
  root:CreateCheckbox(L("SHOW_FORMER_MEMBERS"),
    function() return ns.ShowFormerMembers() end,
    function()
      GuildCotizDB.settings.showFormerMembers = not ns.ShowFormerMembers()
      ns.RefreshUI()
      return MenuResponse.Refresh
    end)
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
  ok:SetText(L("OK"))
  ok:SetScript("OnClick", Accept)

  local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  cancel:SetSize(110, 24)
  cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 8, 16)
  cancel:SetText(L("CANCEL"))
  cancel:SetScript("OnClick", function() d:Hide() end)

  eb:SetScript("OnEnterPressed", Accept)
  eb:SetScript("OnEscapePressed", function() d:Hide() end)

  tinsert(UISpecialFrames, "GuildCotizInputDialog")
  ns.Theme.SkinWindow(d)
  ns.Theme.AutoSkin(d)
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
  ShowInput(L("RAID_AMOUNT_PROMPT"), current, function(txt)
    local gold = tonumber(txt)
    if gold then
      ns.SetRatePeriod(g, g.config.seasonStart or time(), ns.GoldToCopper(gold))
      ns.RefreshUI()
    end
  end)
end

local function PromptStart()
  local g = ns.GetGuildDB(true)
  if not g then return end
  local current = g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or ""
  ShowInput(L("START_DATE_PROMPT"), current, function(txt)
    local y, mo, d = txt:match("(%d+)%-(%d+)%-(%d+)")
    if y then
      ns.SetRatePeriod(g,
        time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 }),
        g.config.raidAmount or 0)
      ns.RefreshUI()
    end
  end)
end

local function PromptDepositCorrection(item)
  if not item or not item.mainName or not item.weekTs then return end
  local g = ns.GetGuildDB(true)
  if not g then return end
  local _, isoWeek = ns.ISOWeek(item.weekTs)
  local weekLabel = string.format("S%d %s", isoWeek, date("%d/%m/%Y", item.weekTs))
  local current = ns.CopperToGold(item.deposited or 0)
  local currentText = (current == math.floor(current))
    and string.format("%.0f", current) or string.format("%.2f", current)

  local targetName = item.playerName or item.mainName
  local promptKey = item.isGroupDetail and "DEPOSIT_EDIT_PROMPT" or "DEPOSIT_EDIT_PROMPT_PLAYER"
  ShowInput(L(promptKey, weekLabel, targetName), currentText, function(txt)
    local clean = (txt or ""):gsub("%s", ""):gsub(",", ".")
    if clean == "" then
      if item.isGroupDetail then
        ns.SetDepositOverride(item.member, item.weekTs, nil)
      else
        ns.SetDepositOverride(item.member, item.weekTs, nil)
      end
    else
      local gold = tonumber(clean)
      if not gold or gold < 0 then return end
      if item.isGroupDetail then
        local desiredGroupTotal = ns.GoldToCopper(gold)
        local rerollTotal = 0
        for _, detail in ipairs(ns.GetGroupDepositsForWeek(g, item.mainName, item.weekTs, time())) do
          if not detail.isMain then rerollTotal = rerollTotal + detail.amount end
        end
        ns.SetDepositOverride(item.member, item.weekTs, math.max(0, desiredGroupTotal - rerollTotal))
      else
        ns.SetDepositOverride(item.member, item.weekTs, ns.GoldToCopper(gold))
      end
    end
    UI.Refresh()
  end)
end

local altDialog
local RefreshAltDialog

local function ConfirmGRMImport(dialog, g, preview)
  local key = "GUILDCOTIZ_GRM_IMPORT"
  StaticPopupDialogs[key] = {
    text = L("GRM_CONFIRM", preview.new, preview.changed),
    button1 = ACCEPT,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(_, data)
      local applied = ns.ApplyGRMImport(data.g, data.preview)
      print("|cff33ff99GuildCotiz|r : " .. L("GRM_IMPORTED", applied))
      data.dialog.suggestionText:SetText(L("GRM_IMPORTED", applied))
      RefreshAltDialog()
      UI.Refresh()
    end,
  }
  StaticPopup_Show(key, nil, nil, { dialog = dialog, g = g, preview = preview })
end

local function FindKnownName(g, text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  for name in pairs(g.members or {}) do
    if name:lower() == text:lower() then return name end
  end
  return nil
end

local function IsRerollMember(g, member)
  return ns.GetRankRole(g, member and member.rankName or "?") == "alt"
end

local function CharacterBaseName(name)
  return ((name or ""):match("^([^-]+)") or name or ""):lower():gsub("[^%w]", "")
end

local function CommonPrefixLength(a, b)
  local limit = math.min(#a, #b)
  local n = 0
  for i = 1, limit do
    if a:sub(i, i) ~= b:sub(i, i) then break end
    n = i
  end
  return n
end

local function FindBestAltSuggestion(g)
  local best
  for altName, altMember in pairs(g.members or {}) do
    if altMember.active and IsRerollMember(g, altMember) and not (g.altToMain and g.altToMain[altName]) then
      local altBase = CharacterBaseName(altName)
      local notes = ((altMember.note or "") .. " " .. (altMember.officerNote or "")):lower()
      for mainName, mainMember in pairs(g.members or {}) do
        if mainMember.active and mainName ~= altName
          and ns.GetRankRole(g, mainMember.rankName or "?") == "main"
          and not ns.IsAlt(g, mainName) then
          local mainBase = CharacterBaseName(mainName)
          local score, reason = 0, nil
          if #mainBase >= 4 and notes:find(mainBase, 1, true) then
            score, reason = 98, L("SUGGESTION_NOTE")
          else
            local longest = math.max(#altBase, #mainBase)
            local prefix = CommonPrefixLength(altBase, mainBase)
            if longest > 0 and prefix >= 4 then
              score = math.floor(55 + (40 * prefix / longest))
              reason = L("SUGGESTION_NAME")
            end
          end
          if score >= 72 and (not best or score > best.score) then
            best = { alt = altName, main = mainName, score = score, reason = reason }
          end
        end
      end
    end
  end
  return best
end

-- Champ de recherche avec une liste filtree des membres de guilde.
-- Un clic dans le champ affiche tous les choix autorises ; la saisie reduit la liste.
local function AddMemberAutocomplete(dialog, edit, predicate)
  local list = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
  list:SetWidth(190)
  list:SetFrameStrata("TOOLTIP")
  list:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  list:SetPoint("TOPLEFT", edit, "TOPRIGHT", 6, 0)
  list:Hide()

  list.buttons = {}
  for i = 1, 8 do
    local button = CreateFrame("Button", nil, list)
    button:SetHeight(20)
    button:SetPoint("TOPLEFT", 6, -5 - ((i - 1) * 20))
    button:SetPoint("TOPRIGHT", -6, -5 - ((i - 1) * 20))
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 3, 0)
    text:SetJustifyH("LEFT")
    button.text = text
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.12)
    button:SetScript("OnMouseDown", function(self)
      edit:SetText(self.memberName or "")
      edit:SetCursorPosition(0)
      edit:ClearFocus()
      list:Hide()
    end)
    list.buttons[i] = button
  end

  local choices = {}
  local offset = 0

  local function RenderSuggestions()
    local remaining = math.max(0, #choices - offset)
    local shown = math.min(remaining, #list.buttons)
    for i, button in ipairs(list.buttons) do
      local name = choices[offset + i]
      if name then
        button.memberName = name
        button.text:SetText(name)
        button:Show()
      else
        button.memberName = nil
        button:Hide()
      end
    end
    if shown > 0 and edit:HasFocus() then
      list:SetHeight(10 + shown * 20)
      list:Show()
    else
      list:Hide()
    end
  end

  local function RefreshSuggestions()
    local g = ns.GetGuildDB(true)
    if not g then list:Hide(); return end
    local query = (edit:GetText() or ""):lower()
    choices = {}
    offset = 0
    for name, member in pairs(g.members or {}) do
      if predicate(name, member, g) and (query == "" or name:lower():find(query, 1, true)) then
        choices[#choices + 1] = name
      end
    end
    table.sort(choices, function(a, b) return a:lower() < b:lower() end)
    RenderSuggestions()
  end

  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    local maxOffset = math.max(0, #choices - #list.buttons)
    offset = math.max(0, math.min(maxOffset, offset - delta))
    RenderSuggestions()
  end)

  edit:SetScript("OnEditFocusGained", RefreshSuggestions)
  edit:SetScript("OnTextChanged", RefreshSuggestions)
  edit:SetScript("OnEscapePressed", function(self)
    list:Hide()
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusLost", function()
    if C_Timer and C_Timer.After then
      C_Timer.After(0.1, function() list:Hide() end)
    else
      list:Hide()
    end
  end)
  edit.suggestionList = list
end

RefreshAltDialog = function()
  if not altDialog then return end
  local g = ns.GetGuildDB(true)
  if not g then return end
  local mappings = {}
  for alt, main in pairs(g.altToMain or {}) do
    mappings[#mappings + 1] = string.format("%s -> %s", alt, ns.ResolveMain(g, main))
  end
  table.sort(mappings)
  altDialog.mappingText:SetText(#mappings > 0 and table.concat(mappings, "\n") or L("NO_ALT_LINKS"))
  local total, linked = 0, 0
  for name, member in pairs(g.members or {}) do
    if member.active and IsRerollMember(g, member) then
      total = total + 1
      if g.altToMain and g.altToMain[name] then linked = linked + 1 end
    end
  end
  altDialog.progressText:SetText(L("ALT_PROGRESS", linked, total, math.max(0, total - linked)))
end

local function GetAltDialog()
  if altDialog then return altDialog end
  local d = CreateFrame("Frame", "GuildCotizAltDialog", UIParent, "BackdropTemplate")
  d:SetSize(560, 365)
  d:SetPoint("CENTER")
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetToplevel(true)
  d:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  -- Le fond de BackdropTemplate peut etre translucide selon la version de WoW.
  -- Cette couche empeche le tableau principal de rester visible sous les textes.
  local solidBackground = d:CreateTexture(nil, "BACKGROUND", nil, -8)
  solidBackground:SetPoint("TOPLEFT", 12, -12)
  solidBackground:SetPoint("BOTTOMRIGHT", -12, 12)
  solidBackground:SetColorTexture(0.025, 0.025, 0.025, 0.97)
  d.solidBackground = solidBackground
  d:SetFrameLevel(100)
  d:SetMovable(true)
  d:EnableMouse(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  d:Hide()
  tinsert(UISpecialFrames, "GuildCotizAltDialog")

  local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -20)
  title:SetText(L("ALT_MANAGER_TITLE"))

  local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local help = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  help:SetPoint("TOP", title, "BOTTOM", 0, -8)
  help:SetWidth(410)
  help:SetText(L("ALT_MAPPING_HELP"))

  local altLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  altLabel:SetPoint("TOPLEFT", 30, -82)
  altLabel:SetText(L("ALT_CHARACTER"))
  local altEdit = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
  altEdit:SetSize(200, 22)
  altEdit:SetPoint("LEFT", altLabel, "RIGHT", 12, 0)
  altEdit:SetAutoFocus(false)
  AddMemberAutocomplete(d, altEdit, function(name, member, g)
    return member.active and IsRerollMember(g, member) and not (g.altToMain and g.altToMain[name])
  end)
  d.altEdit = altEdit

  local mainLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  mainLabel:SetPoint("TOPLEFT", 30, -116)
  mainLabel:SetText(L("MAIN_CHARACTER"))
  local mainEdit = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
  mainEdit:SetSize(200, 22)
  mainEdit:SetPoint("LEFT", mainLabel, "RIGHT", 12, 0)
  mainEdit:SetAutoFocus(false)
  AddMemberAutocomplete(d, mainEdit, function(_, member, g)
    return member.active and ns.GetRankRole(g, member.rankName or "?") == "main"
  end)
  d.mainEdit = mainEdit

  local link = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  link:SetSize(110, 24)
  link:SetPoint("TOPLEFT", 88, -154)
  link:SetText(L("LINK_ALT"))
  link:SetScript("OnClick", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    local alt = FindKnownName(g, altEdit:GetText())
    local main = FindKnownName(g, mainEdit:GetText())
    if not alt or not main then
      print("|cff33ff99GuildCotiz|r : " .. L("ALT_LINK_ERROR"))
      return
    end
    local ok = ns.SetCharacterMain(g, alt, main)
    if not ok then
      print("|cff33ff99GuildCotiz|r : " .. L("ALT_LINK_ERROR"))
      return
    end
    print("|cff33ff99GuildCotiz|r : " .. L("ALT_LINKED", alt, ns.ResolveMain(g, main)))
    RefreshAltDialog()
    UI.Refresh()
  end)

  local unlink = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  unlink:SetSize(110, 24)
  unlink:SetPoint("LEFT", link, "RIGHT", 12, 0)
  unlink:SetText(L("UNLINK_ALT"))
  unlink:SetScript("OnClick", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    local alt = FindKnownName(g, altEdit:GetText())
    if not alt then
      print("|cff33ff99GuildCotiz|r : " .. L("ALT_LINK_ERROR"))
      return
    end
    ns.SetCharacterMain(g, alt, nil)
    print("|cff33ff99GuildCotiz|r : " .. L("ALT_UNLINKED", alt))
    RefreshAltDialog()
    UI.Refresh()
  end)

  local suggest = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  suggest:SetSize(140, 24)
  suggest:SetPoint("LEFT", unlink, "RIGHT", 12, 0)
  suggest:SetText(L("SUGGEST_ALT"))
  suggest:SetScript("OnClick", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    local result = FindBestAltSuggestion(g)
    if not result then
      d.suggestionText:SetText(L("NO_ALT_SUGGESTION"))
      return
    end
    altEdit:SetText(result.alt)
    mainEdit:SetText(result.main)
    d.suggestionText:SetText(L(
      "SUGGESTION_RESULT", result.alt, result.main, result.score, result.reason
    ))
  end)

  local importGRM = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  importGRM:SetSize(180, 24)
  importGRM:SetPoint("TOPLEFT", 30, -184)
  importGRM:SetText(L("GRM_IMPORT"))
  importGRM:SetScript("OnClick", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    local preview = ns.BuildGRMImportPreview(g)
    if not preview then
      d.suggestionText:SetText(L("GRM_NOT_AVAILABLE"))
      return
    end
    d.suggestionText:SetText(L(
      "GRM_PREVIEW", preview.new, preview.changed, preview.unchanged, preview.skipped
    ))
    if preview.new + preview.changed == 0 then
      d.suggestionText:SetText(L("GRM_NO_LINKS"))
      return
    end
    ConfirmGRMImport(d, g, preview)
  end)
  d.importGRM = importGRM

  local suggestionText = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  suggestionText:SetPoint("TOPLEFT", 30, -216)
  suggestionText:SetPoint("TOPRIGHT", -30, -216)
  suggestionText:SetJustifyH("LEFT")
  d.suggestionText = suggestionText

  local progressText = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  progressText:SetPoint("TOPLEFT", 30, -239)
  progressText:SetPoint("TOPRIGHT", -30, -239)
  progressText:SetJustifyH("LEFT")
  d.progressText = progressText

  local mappingText = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mappingText:SetPoint("TOPLEFT", 30, -262)
  mappingText:SetPoint("BOTTOMRIGHT", -30, 28)
  mappingText:SetJustifyH("LEFT")
  mappingText:SetJustifyV("TOP")
  d.mappingText = mappingText

  ns.Theme.SkinWindow(d)
  ns.Theme.AutoSkin(d)
  altDialog = d
  return d
end

local function ShowAltDialog(prefillAlt)
  local d = GetAltDialog()
  d.altEdit:SetText(prefillAlt or "")
  d.mainEdit:SetText("")
  d.suggestionText:SetText("")
  RefreshAltDialog()
  d:Show()
end

--------------------------------------------------------------------------------
-- Construction de la fenetre principale
--------------------------------------------------------------------------------
local function BuildFrame()
  local f = CreateFrame("Frame", "GuildCotizFrame", UIParent, "BackdropTemplate")
  f:SetSize(780, 540)
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

  -- Onglets de mode
  local tabSummary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tabSummary:SetSize(100, 22)
  tabSummary:SetPoint("TOPLEFT", 20, -70)
  tabSummary:SetText(L("SUMMARY"))
  tabSummary:SetScript("OnClick", function()
    f.filter:SetText("") -- affiche a nouveau toute la liste
    UI.SetMode("summary")
  end)
  f.tabSummary = tabSummary

  local tabDetail = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tabDetail:SetSize(130, 22)
  tabDetail:SetPoint("LEFT", tabSummary, "RIGHT", 6, 0)
  tabDetail:SetText(L("WEEKLY_DETAIL"))
  tabDetail:SetScript("OnClick", function() UI.SetMode("detail") end)
  f.tabDetail = tabDetail

  local tabWithdraw = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  tabWithdraw:SetSize(100, 22)
  tabWithdraw:SetPoint("LEFT", tabDetail, "RIGHT", 6, 0)
  tabWithdraw:SetText(L("WITHDRAWALS"))
  tabWithdraw:SetScript("OnClick", function()
    f.filter:SetText("") -- liste complete des retraits
    UI.SetMode("withdraw")
  end)
  f.tabWithdraw = tabWithdraw

  -- Bouton filtre par rang (menu a cases a cocher)
  local rankBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  rankBtn:SetSize(150, 22)
  rankBtn:SetPoint("TOPRIGHT", -20, -70)
  rankBtn:SetText(L("RANKS"))
  rankBtn:SetScript("OnClick", function(self)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, BuildRankMenu)
    else
      print("|cff33ff99GuildCotiz|r : " .. L("RANK_MENU_UNAVAILABLE"))
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
  weekNow:SetText(L("CURRENT_WEEK_BUTTON"))
  weekNow:SetScript("OnClick", function()
    viewWeekOffset = 0
    UI.Refresh()
  end)
  f.weekNow = weekNow

  -- Applique le meme nombre de raids a tous les joueurs actuellement affiches
  local applyAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  applyAll:SetSize(140, 22)
  applyAll:SetPoint("LEFT", weekNow, "RIGHT", 12, 0)
  applyAll:SetText(L("APPLY_TO_ALL"))
  applyAll:SetScript("OnClick", function()
    if not selectedWeekMonday then return end
    ShowInput(L("APPLY_RAIDS_PROMPT"), "", function(txt)
      local n = tonumber(txt)
      if not n then return end
      local g = ns.GetGuildDB(true)
      if not g then return end
      local count = 0
      for _, name in ipairs(UI.GetVisiblePlayers()) do
        ns.SetRaids(g, selectedWeekMonday, name, n)
        count = count + 1
      end
      print("|cff33ff99GuildCotiz|r : " .. L("RAIDS_APPLIED", n, count))
      UI.Refresh()
    end)
  end)
  f.applyAll = applyAll

  local weekSub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  weekSub:SetPoint("LEFT", applyAll, "RIGHT", 14, 0)
  f.weekSub = weekSub

  local historyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  historyBtn:SetSize(170, 22)
  historyBtn:SetPoint("TOPLEFT", 20, -94)
  historyBtn:SetText(L("DEPOSIT_HISTORY"))
  historyBtn:SetScript("OnClick", function()
    if not detailPlayer then return end
    ns.ShowExport(
      ns.BuildDepositHistoryCSV(detailPlayer, not detailIsGroup),
      L("DEPOSIT_HISTORY_TITLE", detailPlayer)
    )
  end)
  historyBtn:Hide()
  f.historyBtn = historyBtn

  -- Champ de filtre
  local filterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  filterLabel:SetPoint("LEFT", tabWithdraw, "RIGHT", 16, 0)
  filterLabel:SetText(L("PLAYER_FILTER"))

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
    local button = CreateFrame("Button", nil, f)
    button:SetHeight(ROW_HEIGHT)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints()
    button.label = label
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.10)
    button:SetScript("OnClick", function(self)
      if not self.sortKey then return end
      local state = sortState[mode]
      if state.key == self.sortKey then
        state.ascending = not state.ascending
      else
        state.key = self.sortKey
        state.ascending = true
      end
      UI.Refresh()
    end)
    button:Hide()
    f.headerCells[i] = button
  end

  -- Zone de liste (scroll)
  local scroll = CreateFrame("ScrollFrame", "GuildCotizListScroll", f, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -144)
  scroll:SetPoint("BOTTOMRIGHT", -34, 50)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
      UI.Refresh(true)
    end)
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
      fs:SetWordWrap(false)
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

    -- Correction manuelle du montant depose pour une semaine (en pieces d'or).
    -- Une saisie vide retire la correction et restaure la valeur lue dans le coffre.
    local depositEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    depositEdit:SetAutoFocus(false)
    depositEdit:SetMaxLetters(12)
    depositEdit:SetJustifyH("RIGHT")
    depositEdit:SetHeight(18)
    depositEdit:Hide()

    local function DepositText(copper, overridden)
      local gold = ns.CopperToGold(copper or 0)
      local text
      if gold == math.floor(gold) then
        text = string.format("%.0f", gold)
      else
        text = string.format("%.2f", gold)
      end
      return overridden and (text .. " *") or text
    end

    local function CommitDeposit(self)
      if not self.member or not self.weekTs then return end
      local text = (self:GetText() or ""):gsub("%s", ""):gsub("%*", ""):gsub(",", ".")
      if text == "" then
        if not self.isOverride then return end
        ns.SetDepositOverride(self.member, self.weekTs, nil)
        self.isOverride = false
      else
        local gold = tonumber(text)
        if not gold or gold < 0 then
          self:SetText(DepositText(self.currentValue, self.isOverride))
          return
        end
        local copper = ns.GoldToCopper(gold)
        if copper == (self.currentValue or 0) then return end
        ns.SetDepositOverride(self.member, self.weekTs, copper)
        self.currentValue = copper
        self.isOverride = true
      end
      UI.Refresh()
    end

    depositEdit:SetScript("OnEnterPressed", function(self)
      CommitDeposit(self)
      self:ClearFocus()
    end)
    depositEdit:SetScript("OnEditFocusLost", CommitDeposit)
    depositEdit:SetScript("OnEscapePressed", function(self)
      self:SetText(DepositText(self.currentValue, self.isOverride))
      self:ClearFocus()
    end)
    depositEdit:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L("COL_DEPOSITED"))
      GameTooltip:AddLine(L("DEPOSIT_OVERRIDE_TOOLTIP"), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    depositEdit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.depositEdit = depositEdit
    row.DepositText = DepositText

    -- Bouton crayon : le montant reste en lecture seule tant que ce bouton n'est pas utilise.
    local depositPencil = CreateFrame("Button", nil, row)
    depositPencil:SetSize(18, 18)
    depositPencil:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    depositPencil:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
    depositPencil:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Highlight")
    depositPencil:Hide()
    depositPencil:SetScript("OnClick", function(self)
      PromptDepositCorrection(self.item)
    end)
    depositPencil:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L("DEPOSIT_EDIT_TITLE"))
      GameTooltip:AddLine(L("DEPOSIT_OVERRIDE_TOOLTIP"), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    depositPencil:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.depositPencil = depositPencil

    local expandButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    expandButton:SetSize(18, 18)
    expandButton:SetPoint("LEFT", row, "LEFT", 2, 0)
    expandButton:Hide()
    expandButton:SetScript("OnClick", function(self)
      if not self.mainName then return end
      expandedMains[self.mainName] = not expandedMains[self.mainName]
      UI.Refresh()
    end)
    expandButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.expanded and L("COLLAPSE_ALTS") or L("EXPAND_ALTS"))
      GameTooltip:Show()
    end)
    expandButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.expandButton = expandButton

    local unlinkAltButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    unlinkAltButton:SetSize(20, 20)
    unlinkAltButton:SetPoint("LEFT", row, "LEFT", 0, 0)
    unlinkAltButton:Hide()
    unlinkAltButton:SetScript("OnClick", function(self)
      if not self.altName then return end
      local g = ns.GetGuildDB(true)
      if not g then return end
      ns.SetCharacterMain(g, self.altName, nil)
      print("|cff33ff99GuildCotiz|r : " .. L("ALT_UNLINKED", self.altName))
      RefreshAltDialog()
      UI.Refresh()
    end)
    unlinkAltButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L("UNLINK_ALT"))
      if self.altName then GameTooltip:AddLine(self.altName, 1, 1, 1) end
      GameTooltip:Show()
    end)
    unlinkAltButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.unlinkAltButton = unlinkAltButton

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
  scanBtn:SetText(L("SCAN_BANK"))
  scanBtn:SetScript("OnClick", function()
    local added, err = ns.ScanBankLog()
    if err then
      print("|cff33ff99GuildCotiz|r : " .. err .. " " .. L("OPEN_BANK_FIRST"))
    else
      print("|cff33ff99GuildCotiz|r : " .. L("SCAN_COMPLETE", added or 0))
    end
  end)

  local altsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  altsBtn:SetSize(130, 24)
  altsBtn:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
  altsBtn:SetText(L("MANAGE_ALTS"))
  altsBtn:SetScript("OnClick", function()
    local prefill = (mode == "detail") and detailPlayer or nil
    ShowAltDialog(prefill)
  end)
  f.altsBtn = altsBtn

  local exportSummary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  exportSummary:SetSize(150, 24)
  exportSummary:SetPoint("BOTTOMRIGHT", -30, 16)
  exportSummary:SetText(L("EXPORT_SUMMARY"))
  exportSummary:SetScript("OnClick", function()
    ns.ShowExport(ns.BuildSummaryCSV(), L("EXPORT_SUMMARY_TITLE"))
  end)

  local exportWeekly = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  exportWeekly:SetSize(170, 24)
  exportWeekly:SetPoint("RIGHT", exportSummary, "LEFT", -6, 0)
  exportWeekly:SetText(L("EXPORT_WEEK"))
  exportWeekly:SetScript("OnClick", function()
    if mode == "withdraw" then
      local only = (filterText ~= "") and filterText or nil
      ns.ShowExport(ns.BuildWithdrawCSV(only),
        only and L("EXPORT_PLAYER_WITHDRAWALS", only) or L("EXPORT_ALL_WITHDRAWALS"))
    else
      local only = (mode == "detail") and detailPlayer or nil
      local titleTxt = only and L("EXPORT_PLAYER_WEEKS", only) or L("EXPORT_ALL_WEEKS")
      ns.ShowExport(ns.BuildWeeklyCSV(only, mode == "detail" and not detailIsGroup), titleTxt)
    end
  end)
  f.exportWeekly = exportWeekly

  -- Version lue directement depuis le .toc pour rester toujours synchronisee.
  local version
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
  elseif GetAddOnMetadata then
    version = GetAddOnMetadata(ADDON, "Version")
  end
  local versionText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  versionText:SetPoint("BOTTOMRIGHT", -30, 45)
  versionText:SetText("v" .. (version or "?"))
  f.versionText = versionText

  ns.Theme.SkinWindow(f)
  ns.Theme.AutoSkin(f)
  headerBar:SetColorTexture(0.055, 0.067, 0.080, 0.98)
  mainFrame = f
  return f
end

--------------------------------------------------------------------------------
-- Mise en page des cellules d'en-tete selon le mode
--------------------------------------------------------------------------------
local function LayoutHeader()
  local cols = COLUMNS[mode]
  for i = 1, MAX_CELLS do
    local button = mainFrame.headerCells[i]
    local col = cols[i]
    if col then
      button:ClearAllPoints()
      button:SetPoint("LEFT", mainFrame.headerBar, "LEFT", col.x, 0)
      button:SetWidth(col.w)
      button.sortKey = col.key
      button.label:SetJustifyH(col.justify)
      local state = sortState[mode]
      local indicator = state.key == col.key and (state.ascending and " ^" or " v") or ""
      button.label:SetText(col.title .. indicator)
      button.label:SetTextColor(1, 0.82, 0)
      button:Show()
    else
      button.sortKey = nil
      button:Hide()
    end
  end
end

--------------------------------------------------------------------------------
-- Rendu de la barre d'infos
--------------------------------------------------------------------------------
local function UpdateInfoBar()
  local g = ns.GetGuildDB(true)
  if not g then
    mainFrame.info:SetText("|cffff5555" .. L("NOT_IN_GUILD") .. "|r")
    return
  end
  local perRaid = ns.FormatGold(g.config.raidAmount)
  local startStr = g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or "?"
  mainFrame.info:SetText(L("INFO_BAR", perRaid, startStr))
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
  if g and ns.TrackingStart(g) then
    local mondayStart = ns.WeekMonday(ns.TrackingStart(g))
    minOffset = -math.floor((mondayNow - mondayStart) / ns.WEEK_SECONDS)
  end
  if viewWeekOffset > 0 then viewWeekOffset = 0 end
  if viewWeekOffset < minOffset then viewWeekOffset = minOffset end

  local selMonday = ns.WeekMonday(mondayNow + viewWeekOffset * ns.WEEK_SECONDS)
  local selEnd = selMonday + ns.WEEK_SECONDS - 1
  local refTime = math.min(selEnd, now)
  selectedWeekMonday = selMonday

  local y, wk = ns.ISOWeek(selMonday)
  mainFrame.weekLabel:SetText(L("WEEK_LABEL",
    wk, y, date("%d/%m", selMonday), date("%d/%m", selEnd)))
  if viewWeekOffset == 0 then
    mainFrame.weekSub:SetText(L("CURRENT_WEEK"))
  else
    mainFrame.weekSub:SetText(L("STATUS_ON_DATE", date("%d/%m/%Y", refTime)))
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
local function ApplyColumnSort(data)
  local state = sortState[mode]
  if not state or not state.key then return data end
  table.sort(data, function(a, b)
    if a.full ~= nil or b.full ~= nil then
      if a.full ~= nil and b.full ~= nil then return false end
      return b.full ~= nil
    end
    local av = (a.sortValues and a.sortValues[state.key]) or (a.cols and a.cols[state.key]) or ""
    local bv = (b.sortValues and b.sortValues[state.key]) or (b.cols and b.cols[state.key]) or ""
    if av == bv then
      if a.sortGroup and b.sortGroup and a.sortGroup == b.sortGroup then
        return (a.sortChild or 0) < (b.sortChild or 0)
      end
      return tostring(a.sortGroup or ""):lower() < tostring(b.sortGroup or ""):lower()
    end
    if type(av) == "string" then av = av:lower() end
    if type(bv) == "string" then bv = bv:lower() end
    if state.ascending then return av < bv end
    return av > bv
  end)
  return data
end

local function BuildDisplayData(refTime)
  local g = ns.GetGuildDB(true)
  if not g then return {} end
  local now = refTime or time()

  g.config.hiddenRanks = g.config.hiddenRanks or {}

  if mode == "summary" then
    local data = {}
    for _, entry in ipairs(ns.GetSortedMembers(g, { includeInactive = true })) do
      local isMain = not ns.IsAlt(g, entry.name)
      local nameOk = (filterText == "")
      if not nameOk and isMain then
        for _, linked in ipairs(ns.GetLinkedCharacters(g, entry.name)) do
          if linked.name:lower():find(filterText:lower(), 1, true) then
            nameOk = true
            break
          end
        end
      end
      if isMain and nameOk and RankShown(g, entry.m.rankName or "?") then
        local s = ns.GetMemberStatus(g, entry.m, entry.name, now)
        local statusStr
        if s.status == "retard" then
          statusStr = L("BEHIND_RAIDS", s.raidsBehind, ns.FormatGold(s.due))
        elseif s.status == "avance" then
          statusStr = L("AHEAD_RAIDS", s.raidsAhead)
        else
          statusStr = L("CURRENT")
        end
        local weekRaids = selectedWeekMonday and ns.GetRaids(g, selectedWeekMonday, entry.name) or 0
        local weekDeposited, weekDepositOverridden = 0, false
        if selectedWeekMonday then
          for _, detail in ipairs(ns.GetGroupDepositsForWeek(g, entry.name, selectedWeekMonday, now)) do
            weekDeposited = weekDeposited + detail.amount
            if detail.overridden then weekDepositOverridden = true end
          end
        end
        local altCount = ns.GetAltCount(g, entry.name)
        local mainSortValues = {
          name = entry.name, rank = entry.m.rankName or "?", raidsWeek = weekRaids,
          raidsTot = s.raids, paid = s.paid, balance = s.balance, status = statusStr,
        }
        data[#data + 1] = {
          color = s.status,
          click = entry.name,
          player = entry.name,
          raidsWeek = weekRaids,
          member = entry.m,
          mainName = entry.name,
          playerName = entry.name,
          isGroupDetail = true,
          weekTs = selectedWeekMonday,
          deposited = weekDeposited,
          depositOverridden = weekDepositOverridden,
          depositDisplay = ns.FormatGold(s.paid),
          altCount = altCount,
          expanded = expandedMains[entry.name] or false,
          sortValues = mainSortValues,
          sortGroup = entry.name,
          sortChild = 0,
          cols = {
            name      = ns.IsFormerMember(entry.m)
                        and L("FORMER_MEMBER_ROW", entry.name) or entry.name,
            rank      = entry.m.rankName or "?",
            raidsWeek = tostring(weekRaids),
            raidsTot  = tostring(s.raids),
            paid      = ns.FormatGold(s.paid),
            balance   = ns.FormatGold(s.balance),
            status    = statusStr,
          },
        }

        if altCount > 0 and expandedMains[entry.name] then
          for _, linked in ipairs(ns.GetLinkedCharacters(g, entry.name)) do
            if not linked.isMain then
              local altStatus = ns.GetIndividualStatus(g, linked.m, linked.name, now)
              local altPaid = altStatus.paid
              local altWeekRaids = selectedWeekMonday and ns.GetRaids(g, selectedWeekMonday, linked.name) or 0
              local altWeekDeposited, altWeekOverridden = 0, false
              if selectedWeekMonday then
                altWeekDeposited, altWeekOverridden = ns.GetDepositedForWeek(
                  linked.m, selectedWeekMonday, ns.MemberStart(g, linked.m), now)
              end
              local altTotalRaids = altStatus.raids
              local altBalance = altStatus.balance
              data[#data + 1] = {
                color = nil,
                isAltRow = true,
                altName = linked.name,
                mainName = entry.name,
                click = linked.name,
                player = linked.name,
                raidsWeek = altWeekRaids,
                member = linked.m,
                playerName = linked.name,
                isGroupDetail = false,
                weekTs = selectedWeekMonday,
                deposited = altWeekDeposited,
                depositOverridden = altWeekOverridden,
                depositDisplay = ns.FormatGold(altPaid),
                sortValues = mainSortValues,
                sortGroup = entry.name,
                sortChild = 1,
                cols = {
                  name = L("ALT_ROW", linked.name),
                  rank = linked.m.rankName or "?",
                  raidsWeek = tostring(altWeekRaids),
                  raidsTot = tostring(altTotalRaids),
                  paid = ns.FormatGold(altPaid),
                  balance = ns.FormatGold(altBalance),
                  status = entry.name,
                },
              }
            end
          end
        end
      end
    end
    if #data == 0 then
      local hasMembers = next(g.members) ~= nil
      if hasMembers then
        data[1] = { full = L("NO_MEMBERS_FILTERED"), color = nil }
      else
        data[1] = { full = L("NO_MEMBERS"), color = nil }
      end
    end
    return ApplyColumnSort(data)

  elseif mode == "withdraw" then
    -- Sorties d'or du coffre, du plus recent au plus ancien.
    -- Ces montants ne sont jamais comptes dans les cotisations.
    local data = {}
    for _, w in ipairs(ns.GetAllWithdrawals(g)) do
      local nameOk = (filterText == "" or w.name:lower():find(filterText:lower(), 1, true))
      if nameOk and RankShown(g, w.rankName) then
        data[#data + 1] = {
          color = w.kind,
          sortValues = {
            player = w.name, rank = w.rankName or "?", date = w.t,
            time = date("%H:%M", w.t), amount = w.a, kind = ns.WITHDRAW_TYPES[w.kind] or w.kind or "?",
          },
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
      data[1] = { full = L("NO_WITHDRAWALS"), color = nil }
    end
    return ApplyColumnSort(data)

  else -- detail : toujours l'historique complet jusqu'a aujourd'hui
    now = time()
    local target = filterText -- le champ 'Joueur' est la seule source
    if not target or target == "" then
      detailPlayer = nil
      return { { full = L("ENTER_PLAYER"), color = nil } }
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
      return { { full = L("PLAYER_NOT_FOUND", target), color = "retard" } }
    end

    detailPlayer = found.name
    detailIsGroup = not ns.IsAlt(g, found.name)
    mainFrame.title:SetText(L("DETAIL_TITLE", found.name))
    local s = detailIsGroup
      and ns.GetMemberStatus(g, found.m, found.name, now)
      or ns.GetIndividualStatus(g, found.m, found.name, now)
    local data = {}
    local breakdown = detailIsGroup
      and ns.GetWeeklyBreakdown(g, found.m, found.name, now)
      or ns.GetIndividualWeeklyBreakdown(g, found.m, found.name, now)
    for _, r in ipairs(breakdown) do
      local isoY, wk = ns.ISOWeek(r.weekStart)
      data[#data + 1] = {
        color = r.status,
        member = found.m,
        mainName = ns.ResolveMain(g, found.name),
        playerName = found.name,
        isGroupDetail = detailIsGroup,
        weekTs = r.weekStart,
        deposited = r.deposited,
        depositOverridden = r.depositOverridden,
        sortValues = {
          start = r.weekStart, raids = r.raids, dueweek = r.dueWeek,
          dep = r.deposited, cumdue = r.cumOwed, cumpaid = r.cumPaid,
          status = ns.StatusText(r.status),
        },
        cols = {
          start   = string.format("S%d  %s", wk, date("%d/%m", r.weekStart)),
          raids   = tostring(r.raids),
          dueweek = r.dueWeek > 0 and ns.FormatGold(r.dueWeek) or "-",
          dep     = r.deposited > 0 and ns.FormatGold(r.deposited) or "0",
          cumdue  = ns.FormatGold(r.cumOwed),
          cumpaid = ns.FormatGold(r.cumPaid),
          status  = ns.StatusText(r.status),
        },
      }
    end
    -- ligne de synthese
    local summaryLine
    if s.status == "retard" then
      summaryLine = L("DETAIL_BEHIND", s.raids, s.raidsBehind, ns.FormatGold(s.due))
    elseif s.status == "avance" then
      summaryLine = L("DETAIL_AHEAD", s.raids, s.raidsAhead)
    else
      summaryLine = L("DETAIL_CURRENT", s.raids)
    end
    data[#data + 1] = { full = "" }
    data[#data + 1] = { full = summaryLine, color = s.status }
    return ApplyColumnSort(data)
  end
end

--------------------------------------------------------------------------------
-- Rafraichissement
--------------------------------------------------------------------------------
function UI.Refresh(scrollOnly)
  if not mainFrame or not mainFrame:IsShown() then return end
  local cols, data

  if scrollOnly and cachedDisplayData and cachedColumns then
    cols = cachedColumns
    data = cachedDisplayData
  else
    UpdateInfoBar()
    LayoutHeader()

    mainFrame.tabSummary:SetEnabled(mode ~= "summary")
    mainFrame.tabDetail:SetEnabled(mode ~= "detail")
    mainFrame.tabWithdraw:SetEnabled(mode ~= "withdraw")
    ns.Theme.SetButtonActive(mainFrame.tabSummary, mode == "summary")
    ns.Theme.SetButtonActive(mainFrame.tabDetail, mode == "detail")
    ns.Theme.SetButtonActive(mainFrame.tabWithdraw, mode == "withdraw")
    if mode == "summary" then
      mainFrame.title:SetText("Guild Cotiz")
    elseif mode == "withdraw" then
      mainFrame.title:SetText(L("WITHDRAW_TITLE"))
    end

    -- le bouton d'export s'adapte a l'onglet actif
    if mainFrame.exportWeekly then
      mainFrame.exportWeekly:SetText(mode == "withdraw" and L("EXPORT_WITHDRAWALS") or L("EXPORT_WEEK"))
    end

    -- compteur de rangs affiches sur le bouton
    local g0 = ns.GetGuildDB(true)
    if g0 and mainFrame.rankBtn then
      g0.config.hiddenRanks = g0.config.hiddenRanks or {}
      local ranks = GetRankList(g0)
      local shown = 0
      for _, r in ipairs(ranks) do if RankShown(g0, r.name) then shown = shown + 1 end end
      if #ranks > 0 and shown < #ranks then
        mainFrame.rankBtn:SetText(L("RANKS") .. string.format(" (%d/%d)", shown, #ranks))
      else
        mainFrame.rankBtn:SetText(L("RANKS"))
      end
    end

    local refTime = UpdateWeekBar()
    cols = COLUMNS[mode]
    data = BuildDisplayData(refTime)
    cachedColumns = cols
    cachedDisplayData = data
    if mainFrame.historyBtn then
      if mode == "detail" and detailPlayer then
        mainFrame.historyBtn:Show()
      else
        mainFrame.historyBtn:Hide()
      end
    end
  end
  local scroll = mainFrame.scroll
  FauxScrollFrame_Update(scroll, #data, NUM_ROWS, ROW_HEIGHT)
  local offset = FauxScrollFrame_GetOffset(scroll)

  for i = 1, NUM_ROWS do
    local row = mainFrame.rows[i]
    local idx = i + offset
    local item = data[idx]
    if item then
      local r, gg, b = ColorFor(item.color)
      if idx % 2 == 0 then
        row.bg:SetColorTexture(0.075, 0.090, 0.105, 0.72)
      else
        row.bg:SetColorTexture(0.040, 0.050, 0.060, 0.48)
      end

      if item.full ~= nil then
        row.full:SetText(item.full)
        row.full:SetTextColor(r, gg, b)
        row.full:Show()
        for c = 1, MAX_CELLS do row.cells[c]:Hide() end
        row.raidEdit:Hide()
        row.depositEdit:Hide()
        row.depositPencil:Hide()
        row.expandButton:Hide()
        row.unlinkAltButton:Hide()
        row:SetScript("OnClick", nil)
        row.hl:SetAlpha(0)
      else
        row.full:Hide()
        local editShown = false
        for c = 1, MAX_CELLS do
          local cell = row.cells[c]
          local col = cols[c]
          if col and col.edit == "raid" and item.player then
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
          elseif col and col.edit == "deposit" and item.member and item.weekTs then
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", col.x, 0)
            cell:SetWidth(col.w - 22)
            cell:SetJustifyH(col.justify)
            cell:SetText(item.depositDisplay
              or row.DepositText(item.deposited or 0, item.depositOverridden))
            cell:SetTextColor(r, gg, b)
            cell:Show()
            row.depositEdit:Hide()
            local pencil = row.depositPencil
            pencil:ClearAllPoints()
            pencil:SetPoint("LEFT", row, "LEFT", col.x + col.w - 19, 0)
            pencil.item = item
            pencil:Show()
          elseif col then
            cell:ClearAllPoints()
            local nameOffset = 0
            if col.key == "name" and ((item.altCount and item.altCount > 0) or item.isAltRow) then
              nameOffset = 20
            end
            cell:SetPoint("LEFT", row, "LEFT", col.x + nameOffset, 0)
            cell:SetWidth(col.w - nameOffset)
            cell:SetJustifyH(col.justify)
            cell:SetText(item.cols[col.key] or "")
            cell:SetTextColor(r, gg, b)
            cell:Show()
          else
            cell:Hide()
          end
        end
        if mode ~= "summary" then row.raidEdit:Hide() end
        -- Le depot est editable dans le detail et dans le resume pour la
        -- semaine selectionnee. Seul l'onglet Retraits ne propose pas ce crayon.
        if mode == "withdraw" then
          row.depositEdit:Hide()
          row.depositPencil:Hide()
        end
        if item.altCount and item.altCount > 0 then
          row.expandButton.mainName = item.mainName
          row.expandButton.expanded = item.expanded
          row.expandButton:SetText(item.expanded and "-" or "+")
          row.expandButton:Show()
        else
          row.expandButton:Hide()
        end
        if item.isAltRow and item.altName then
          row.unlinkAltButton.altName = item.altName
          row.unlinkAltButton:Show()
        else
          row.unlinkAltButton.altName = nil
          row.unlinkAltButton:Hide()
        end
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
      row.raidEdit:Hide()
      row.depositEdit:Hide()
      row.depositPencil:Hide()
      row.expandButton:Hide()
      row.unlinkAltButton:Hide()
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
    -- Le scan precede l'affichage : la fenetre encore masquee, le
    -- rafraichissement interne de ScanRoster ne coute rien, et la vue n'est
    -- reconstruite qu'une seule fois, juste apres.
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    ns.ScanRoster()
    mainFrame:Show()
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
      ns.SetRatePeriod(g, g.config.seasonStart or time(), ns.GoldToCopper(gold))
      print("|cff33ff99GuildCotiz|r : " .. L("SET_AMOUNT_SUCCESS", gold))
      ns.RefreshUI()
    else
      print("|cff33ff99GuildCotiz|r : " .. L("SET_AMOUNT_USAGE"))
    end
  elseif cmd == "start" then
    local g = ns.GetGuildDB(true)
    if g then
      local y, mo, d = rest:match("(%d+)%-(%d+)%-(%d+)")
      local newStart
      if y then
        newStart = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 0 })
      elseif rest:lower() == "auto" or rest:lower() == "first" then
        local e = ns.EarliestDeposit(g)
        if e then
          newStart = e - (e % 86400)
        else
          print("|cff33ff99GuildCotiz|r : " .. L("NO_DEPOSIT_RECORDED"))
          return
        end
      else
        local now = time()
        newStart = now - (now % 86400)
      end
      ns.SetRatePeriod(g, newStart, g.config.raidAmount or 0)
      print("|cff33ff99GuildCotiz|r : " .. L("START_DATE_SUCCESS",
        date("%Y-%m-%d", g.config.seasonStart)))
      ns.RefreshUI()
    end
  elseif cmd == "scan" then
    local added, err = ns.ScanBankLog()
    if err then print("|cff33ff99GuildCotiz|r : " .. err)
    else print("|cff33ff99GuildCotiz|r : " .. L("NEW_DEPOSITS", added or 0)) end
  elseif cmd == "fix" then
    local kept = ns.Deduplicate()
    print("|cff33ff99GuildCotiz|r : " .. L("INDEX_REBUILT", kept))
  elseif cmd == "export" then
    ns.ShowExport(ns.BuildSummaryCSV(), L("EXPORT_SUMMARY_TITLE"))
  elseif cmd == "roster" then
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    local complete, departures, returns = ns.ScanRoster()
    if not complete then
      print("|cff33ff99GuildCotiz|r : " .. L("ROSTER_INCOMPLETE"))
    else
      print("|cff33ff99GuildCotiz|r : " .. L("ROSTER_SCANNED", departures, returns))
      local g = ns.GetGuildDB(true)
      local former = g and ns.GetFormerMembers(g) or {}
      if #former > 0 then
        print("|cff33ff99GuildCotiz|r : " .. L("ROSTER_FORMER_COUNT", #former))
        for _, entry in ipairs(former) do
          print(L("ROSTER_FORMER_LINE", entry.name,
            date("%Y-%m-%d", entry.leftAt), entry.deposits))
        end
      end
    end
  elseif cmd == "purge" then
    local g = ns.GetGuildDB(true)
    if not g then
      print("|cff33ff99GuildCotiz|r : " .. L("NOT_IN_GUILD"))
    else
      -- "all" inclut ceux qui ont depose ; par defaut on ne purge que les
      -- anciens membres sans aucun depot, ce qui ne touche pas la comptabilite.
      local purgeAll = (rest:lower() == "all")
      local former = ns.GetFormerMembers(g)
      if #former == 0 then
        print("|cff33ff99GuildCotiz|r : " .. L("PURGE_NONE"))
      else
        local removed = ns.PurgeFormerMembers(g, not purgeAll)
        print("|cff33ff99GuildCotiz|r : " .. L("PURGE_DONE", removed))
        local left = #ns.GetFormerMembers(g)
        if left > 0 then
          print("|cff33ff99GuildCotiz|r : " .. L("PURGE_KEPT", left))
        end
      end
    end
  elseif cmd == "sync" then
    if rest:lower() == "status" then
      ns.Sync.Status()
    else
      ns.Sync.Broadcast(true)
    end
  elseif cmd == "debug" then
    ns.DebugDump()
  else
    print("|cff33ff99GuildCotiz|r " .. L("HELP_TITLE"))
    print(L("HELP_SHOW"))
    print(L("HELP_SET"))
    print(L("HELP_START"))
    print(L("HELP_START_AUTO"))
    print(L("HELP_SCAN"))
    print(L("HELP_FIX"))
    print(L("HELP_EXPORT"))
    print(L("HELP_ROSTER"))
    print(L("HELP_PURGE"))
    print(L("HELP_SYNC"))
    print(L("HELP_SYNC_STATUS"))
    print(L("HELP_DEBUG"))
  end
end
