-- GuildCotiz - Options.lua
-- Page native Options > AddOns > GuildCotiz et interface de partage des profils.

local ADDON, ns = ...
local L = ns.L

local selectedScope = "both"
local profileDialog

local function ScopeLabel(scope)
  if scope == "config" then return L("PROFILE_CONFIG") end
  if scope == "alts" then return L("PROFILE_ALTS") end
  return L("PROFILE_BOTH")
end

local function GetProfileDialog()
  if profileDialog then return profileDialog end
  local d = CreateFrame("Frame", "GuildCotizProfileDialog", UIParent, "BackdropTemplate")
  d:SetSize(620, 460)
  d:SetPoint("CENTER")
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetToplevel(true)
  d:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  local bg = d:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetPoint("TOPLEFT", 12, -12)
  bg:SetPoint("BOTTOMRIGHT", -12, 12)
  bg:SetColorTexture(0.025, 0.025, 0.025, 0.98)
  d:Hide()
  tinsert(UISpecialFrames, "GuildCotizProfileDialog")

  local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -20)
  d.title = title
  local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local hint = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 28, -50)
  hint:SetPoint("TOPRIGHT", -28, -50)
  hint:SetJustifyH("LEFT")
  d.hint = hint

  local scroll = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 28, -78)
  scroll:SetPoint("BOTTOMRIGHT", -48, 112)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(530)
  edit:SetHeight(300)
  edit:SetTextInsets(6, 6, 6, 6)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); d:Hide() end)
  scroll:SetScrollChild(edit)
  d.edit = edit

  local nameLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  nameLabel:SetPoint("BOTTOMLEFT", 30, 76)
  nameLabel:SetText(L("PROFILE_NAME"))
  nameLabel:Hide()
  d.nameLabel = nameLabel
  local nameEdit = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
  nameEdit:SetSize(220, 24)
  nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
  nameEdit:SetAutoFocus(false)
  nameEdit:Hide()
  d.nameEdit = nameEdit

  local analyze = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  analyze:SetSize(150, 26)
  analyze:SetPoint("BOTTOMLEFT", 30, 30)
  analyze:SetText(L("PROFILE_ANALYZE"))
  d.analyze = analyze

  local apply = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  apply:SetSize(150, 26)
  apply:SetPoint("LEFT", analyze, "RIGHT", 12, 0)
  apply:SetText(L("PROFILE_APPLY"))
  apply:Hide()
  d.apply = apply

  local status = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("LEFT", apply, "RIGHT", 14, 0)
  status:SetPoint("RIGHT", -30, 0)
  status:SetJustifyH("LEFT")
  d.status = status

  analyze:SetScript("OnClick", function()
    local profile = ns.ParseProfile(edit:GetText())
    d.pendingProfile = profile
    if not profile then
      status:SetText("|cffff5555" .. L("PROFILE_INVALID") .. "|r")
      apply:Hide()
      return
    end
    status:SetText(L("PROFILE_SUMMARY", ScopeLabel(profile.scope), profile.linkCount, profile.altRankCount))
    apply:Show()
  end)
  apply:SetScript("OnClick", function()
    local profileName = d.nameEdit:GetText()
    if not profileName or profileName:gsub("%s", "") == "" then
      status:SetText("|cffff5555" .. L("PROFILE_NAME_REQUIRED") .. "|r")
      return
    end
    local ok, err = ns.StoreImportedProfile(profileName, d.pendingProfile)
    if ok then
      print("|cff33ff99GuildCotiz|r : " .. L("PROFILE_IMPORTED"))
      if ns.RefreshOptions then ns.RefreshOptions() end
      d:Hide()
    elseif err == "exists" then
      status:SetText("|cffff5555" .. L("PROFILE_EXISTS") .. "|r")
    end
  end)

  ns.Theme.SkinWindow(d)
  ns.Theme.AutoSkin(d)
  profileDialog = d
  return d
end

local function ShowExport()
  local text, err = ns.BuildProfile(selectedScope)
  if not text then print("|cff33ff99GuildCotiz|r : " .. tostring(err)); return end
  local d = GetProfileDialog()
  d.title:SetText(L("PROFILE_EXPORT_TITLE"))
  d.hint:SetText(L("PROFILE_EXPORT_HINT"))
  d.edit:SetText(text)
  d.edit:SetCursorPosition(0)
  d.edit:EnableMouse(true)
  d.analyze:Hide()
  d.apply:Hide()
  d.nameLabel:Hide()
  d.nameEdit:Hide()
  d.status:SetText("")
  d:Show()
  d.edit:SetFocus()
  d.edit:HighlightText()
end

local function ShowImport()
  local d = GetProfileDialog()
  d.title:SetText(L("PROFILE_IMPORT_TITLE"))
  d.hint:SetText(L("PROFILE_IMPORT_HINT"))
  d.edit:SetText("")
  d.edit:EnableMouse(true)
  d.pendingProfile = nil
  d.nameEdit:SetText("")
  d.status:SetText("")
  d.apply:Hide()
  d.nameLabel:Show()
  d.nameEdit:Show()
  d.analyze:Show()
  d:Show()
  d.edit:SetFocus()
end

local function RegisterOptions()
  if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
  local rootPanel = CreateFrame("Frame")
  rootPanel.name = "Guild Cotiz"
  local pageScroll = CreateFrame("ScrollFrame", nil, rootPanel, "UIPanelScrollFrameTemplate")
  pageScroll:SetPoint("TOPLEFT", 0, 0)
  pageScroll:SetPoint("BOTTOMRIGHT", -24, 0)
  local panel = CreateFrame("Frame", nil, pageScroll)
  panel:SetSize(680, 900)
  pageScroll:SetScrollChild(panel)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText("Guild Cotiz")
  local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  description:SetText(L("OPTIONS_DESCRIPTION"))

  local profileManagerLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  profileManagerLabel:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -22)
  profileManagerLabel:SetText(L("PROFILE_MANAGER"))
  local profileSelect = CreateFrame("Frame", "GuildCotizProfileDropdown", panel, "UIDropDownMenuTemplate")
  profileSelect:SetPoint("LEFT", profileManagerLabel, "RIGHT", -4, 0)
  UIDropDownMenu_SetWidth(profileSelect, 160)

  local saveProfile = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  saveProfile:SetSize(110, 26)
  saveProfile:SetPoint("LEFT", profileSelect, "RIGHT", 8, 0)
  saveProfile:SetText(L("PROFILE_SAVE"))
  local resetProfile = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  resetProfile:SetSize(90, 26)
  resetProfile:SetPoint("LEFT", saveProfile, "RIGHT", 6, 0)
  resetProfile:SetText(L("PROFILE_RESET"))
  local deleteProfile = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  deleteProfile:SetSize(90, 26)
  deleteProfile:SetPoint("LEFT", resetProfile, "RIGHT", 6, 0)
  deleteProfile:SetText(L("PROFILE_DELETE"))

  local function RefreshProfileManager()
    local active = ns.GetActiveProfileName()
    UIDropDownMenu_SetText(profileSelect, active)
    deleteProfile:SetEnabled(active ~= "Default")
  end
  ns.RefreshOptions = function()
    RefreshProfileManager()
    if panel.RefreshFields then panel.RefreshFields() end
    if panel.RefreshRankLists then panel.RefreshRankLists() end
  end

  UIDropDownMenu_Initialize(profileSelect, function(_, level)
    for _, profileName in ipairs(ns.GetProfileNames()) do
      local selectedName = profileName
      local info = UIDropDownMenu_CreateInfo()
      info.text = selectedName
      info.checked = ns.GetActiveProfileName() == selectedName
      info.func = function()
        ns.SelectProfile(selectedName)
        RefreshProfileManager()
        if panel.RefreshFields then panel.RefreshFields() end
        if panel.RefreshRankLists then panel.RefreshRankLists() end
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  saveProfile:SetScript("OnClick", function()
    if ns.SaveActiveProfile() then
      print("|cff33ff99GuildCotiz|r : " .. L("PROFILE_SAVED"))
    end
  end)
  resetProfile:SetScript("OnClick", function()
    if ns.ResetActiveProfile() then
      RefreshProfileManager()
      if panel.RefreshFields then panel.RefreshFields() end
      if panel.RefreshRankLists then panel.RefreshRankLists() end
      print("|cff33ff99GuildCotiz|r : " .. L("PROFILE_RESET_DONE"))
    end
  end)
  deleteProfile:SetScript("OnClick", function()
    local active = ns.GetActiveProfileName()
    if ns.DeleteProfile(active) then
      RefreshProfileManager()
      if panel.RefreshFields then panel.RefreshFields() end
      if panel.RefreshRankLists then panel.RefreshRankLists() end
      print("|cff33ff99GuildCotiz|r : " .. L("PROFILE_DELETED"))
    end
  end)

  local amountLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  amountLabel:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -32)
  amountLabel:SetText(L("RAID_AMOUNT_PROMPT"))
  local amount = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  amount:SetSize(160, 24)
  amount:SetPoint("TOPLEFT", amountLabel, "BOTTOMLEFT", 4, -8)
  amount:SetAutoFocus(false)

  local dateLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  dateLabel:SetPoint("LEFT", amountLabel, "LEFT", 300, 0)
  dateLabel:SetText(L("START_DATE_PROMPT"))
  local startDate = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  startDate:SetSize(160, 24)
  startDate:SetPoint("TOPLEFT", dateLabel, "BOTTOMLEFT", 4, -8)
  startDate:SetAutoFocus(false)

  function panel.RefreshFields()
    local g = ns.GetGuildDB(true)
    if not g then return end
    amount:SetText(tostring(ns.CopperToGold(g.config.raidAmount or 0)))
    startDate:SetText(g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or "")
  end

  local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  save:SetSize(140, 26)
  save:SetPoint("TOPLEFT", amount, "BOTTOMLEFT", 0, -14)
  save:SetText(L("OPTIONS_SAVE"))
  save:SetScript("OnClick", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    local amountText = (amount:GetText() or ""):gsub("%s", ""):gsub(",", ".")
    local gold = tonumber(amountText)
    local y, m, day = (startDate:GetText() or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not gold or gold < 0 then
      print("|cff33ff99GuildCotiz|r : " .. L("OPTIONS_INVALID_AMOUNT"))
      return
    end
    if not y then
      print("|cff33ff99GuildCotiz|r : " .. L("OPTIONS_INVALID_DATE"))
      return
    end
    local newStart = time({ year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = 0 })
    if not newStart or date("%Y-%m-%d", newStart)
      ~= string.format("%04d-%02d-%02d", tonumber(y), tonumber(m), tonumber(day)) then
      print("|cff33ff99GuildCotiz|r : " .. L("OPTIONS_INVALID_DATE"))
      return
    end
    g.config.raidAmount = ns.GoldToCopper(gold)
    g.config.seasonStart = newStart
    ns.SaveActiveProfile()
    ns.RefreshUI()
    amount:ClearFocus()
    startDate:ClearFocus()
    panel.RefreshFields()
    print("|cff33ff99GuildCotiz|r : " .. L("OPTIONS_SAVED"))
  end)

  local profileTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  profileTitle:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -40)
  profileTitle:SetText(L("PROFILE_SHARING"))
  local scopeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  scopeLabel:SetPoint("TOPLEFT", profileTitle, "BOTTOMLEFT", 0, -12)
  scopeLabel:SetText(L("PROFILE_SCOPE"))

  local includeConfig = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  includeConfig:SetSize(26, 26)
  includeConfig:SetPoint("TOPLEFT", scopeLabel, "BOTTOMLEFT", 0, -6)
  includeConfig:SetChecked(true)
  local includeConfigText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  includeConfigText:SetPoint("LEFT", includeConfig, "RIGHT", 4, 0)
  includeConfigText:SetText(L("PROFILE_CONFIG"))

  local includeAlts = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  includeAlts:SetSize(26, 26)
  includeAlts:SetPoint("TOPLEFT", includeConfig, "BOTTOMLEFT", 0, -4)
  includeAlts:SetChecked(true)
  local includeAltsText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  includeAltsText:SetPoint("LEFT", includeAlts, "RIGHT", 4, 0)
  includeAltsText:SetText(L("PROFILE_ALTS"))

  local function UpdateSelectedScope(clicked)
    local configChecked = includeConfig:GetChecked()
    local altsChecked = includeAlts:GetChecked()
    if not configChecked and not altsChecked then
      clicked:SetChecked(true)
      if clicked == includeConfig then configChecked = true else altsChecked = true end
    end
    if configChecked and altsChecked then selectedScope = "both"
    elseif configChecked then selectedScope = "config"
    else selectedScope = "alts" end
  end
  includeConfig:SetScript("OnClick", function(self) UpdateSelectedScope(self) end)
  includeAlts:SetScript("OnClick", function(self) UpdateSelectedScope(self) end)

  local export = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  export:SetSize(180, 28)
  export:SetPoint("TOPLEFT", includeAlts, "BOTTOMLEFT", 0, -18)
  export:SetText(L("PROFILE_EXPORT"))
  export:SetScript("OnClick", ShowExport)
  local import = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  import:SetSize(180, 28)
  import:SetPoint("LEFT", export, "RIGHT", 12, 0)
  import:SetText(L("PROFILE_IMPORT"))
  import:SetScript("OnClick", ShowImport)

  local rolesTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  rolesTitle:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -38)
  rolesTitle:SetText(L("RANK_ROLES_TITLE"))

  local selectedRank
  local selectedRole
  local rankLists = {}

  local function CreateRankList(role, titleText, x)
    local titleTextFrame = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleTextFrame:SetPoint("TOPLEFT", rolesTitle, "BOTTOMLEFT", x, -14)
    titleTextFrame:SetWidth(160)
    titleTextFrame:SetJustifyH("CENTER")
    titleTextFrame:SetText(titleText)
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetSize(160, 142)
    box:SetPoint("TOPLEFT", titleTextFrame, "BOTTOMLEFT", 0, -6)
    box:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 10,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.35)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -25, 5)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(126, 132)
    scroll:SetScrollChild(content)
    box.scroll = scroll
    box.content = content
    box.rows = {}
    for i = 1, 10 do
      local row = CreateFrame("Button", nil, content)
      row:SetHeight(20)
      row:SetPoint("TOPLEFT", 2, -2 - ((i - 1) * 20))
      row:SetPoint("TOPRIGHT", -2, -2 - ((i - 1) * 20))
      local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("LEFT", 3, 0)
      row.text = text
      local highlight = row:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetColorTexture(1, 1, 1, 0.12)
      row:SetScript("OnClick", function(self)
        selectedRank = self.rankName
        selectedRole = role
        if panel.RefreshRankLists then panel.RefreshRankLists() end
      end)
      box.rows[i] = row
    end
    rankLists[role] = box
    return box
  end

  local altList = CreateRankList("alt", L("REROLL_RANKS"), 0)
  local unassignedList = CreateRankList("unassigned", L("UNASSIGNED_RANKS"), 220)
  local mainList = CreateRankList("main", L("MAIN_RANKS"), 440)

  -- Les profils sont volontairement regroupes apres tous les reglages classiques.
  profileManagerLabel:ClearAllPoints()
  profileManagerLabel:SetPoint("TOPLEFT", altList, "BOTTOMLEFT", 0, -36)
  profileTitle:ClearAllPoints()
  profileTitle:SetPoint("TOPLEFT", profileManagerLabel, "BOTTOMLEFT", 0, -42)

  local function MoveSelected(role)
    if not selectedRank then return end
    local g = ns.GetGuildDB(true)
    if not g then return end
    ns.SetRankRole(g, selectedRank, role)
    selectedRole = role
    panel.RefreshRankLists()
    ns.SaveActiveProfile()
    ns.RefreshUI()
  end

  local toAlt = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  toAlt:SetSize(38, 26)
  toAlt:SetPoint("LEFT", altList, "RIGHT", 11, 26)
  toAlt:SetText("<")
  toAlt:SetScript("OnClick", function() MoveSelected("alt") end)
  local fromAlt = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  fromAlt:SetSize(38, 26)
  fromAlt:SetPoint("TOP", toAlt, "BOTTOM", 0, -8)
  fromAlt:SetText(">")
  fromAlt:SetScript("OnClick", function() MoveSelected("unassigned") end)

  local fromMain = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  fromMain:SetSize(38, 26)
  fromMain:SetPoint("LEFT", unassignedList, "RIGHT", 11, 26)
  fromMain:SetText("<")
  fromMain:SetScript("OnClick", function() MoveSelected("unassigned") end)
  local toMain = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  toMain:SetSize(38, 26)
  toMain:SetPoint("TOP", fromMain, "BOTTOM", 0, -8)
  toMain:SetText(">")
  toMain:SetScript("OnClick", function() MoveSelected("main") end)

  function panel.RefreshRankLists()
    local g = ns.GetGuildDB(true)
    if not g then return end
    ns.EnsureRankRoles(g)
    local byRole = { alt = {}, unassigned = {}, main = {} }
    local known = {}
    for _, member in pairs(g.members or {}) do known[member.rankName or "?"] = true end
    for rankName in pairs(known) do
      local role = ns.GetRankRole(g, rankName)
      byRole[role][#byRole[role] + 1] = rankName
    end
    for role, names in pairs(byRole) do
      table.sort(names)
      local list = rankLists[role]
      list.content:SetHeight(math.max(132, 4 + (#names * 20)))
      for i, row in ipairs(list.rows) do
        local rankName = names[i]
        if rankName then
          row.rankName = rankName
          row.text:SetText(
            selectedRank == rankName and selectedRole == role and ("> " .. rankName) or rankName
          )
          row:Show()
        else
          row.rankName = nil
          row:Hide()
        end
      end
    end
  end

  rootPanel:SetScript("OnShow", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    panel.RefreshFields()
    RefreshProfileManager()
    panel.RefreshRankLists()
  end)

  for _, list in pairs(rankLists) do ns.Theme.SkinPanel(list) end
  ns.Theme.AutoSkin(panel)

  local category = Settings.RegisterCanvasLayoutCategory(rootPanel, "Guild Cotiz")
  Settings.RegisterAddOnCategory(category)
  ns.optionsCategoryID = category:GetID()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
  if name == ADDON then RegisterOptions() end
end)
