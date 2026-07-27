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
  scroll:SetPoint("BOTTOMRIGHT", -48, 82)
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
    if d.pendingProfile and ns.ApplyProfile(d.pendingProfile) then
      print("|cff33ff99GuildCotiz|r : " .. L("PROFILE_IMPORTED"))
      d:Hide()
    end
  end)

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
  d.status:SetText("")
  d.apply:Hide()
  d.analyze:Show()
  d:Show()
  d.edit:SetFocus()
end

local function RegisterOptions()
  if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
  local panel = CreateFrame("Frame")
  panel.name = "Guild Cotiz"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText("Guild Cotiz")
  local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  description:SetText(L("OPTIONS_DESCRIPTION"))

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

  local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  save:SetSize(140, 26)
  save:SetPoint("TOPLEFT", amount, "BOTTOMLEFT", 0, -14)
  save:SetText(L("OPTIONS_SAVE"))
  save:SetScript("OnClick", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    local gold = tonumber((amount:GetText() or ""):gsub(",", "."))
    local y, m, day = (startDate:GetText() or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if gold and gold >= 0 then g.config.raidAmount = ns.GoldToCopper(gold) end
    if y then g.config.seasonStart = time({ year = tonumber(y), month = tonumber(m), day = tonumber(day), hour = 0 }) end
    ns.RefreshUI()
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

  panel:SetScript("OnShow", function()
    local g = ns.GetGuildDB(true)
    if not g then return end
    amount:SetText(tostring(ns.CopperToGold(g.config.raidAmount or 0)))
    startDate:SetText(g.config.seasonStart and date("%Y-%m-%d", g.config.seasonStart) or "")
  end)

  local category = Settings.RegisterCanvasLayoutCategory(panel, "Guild Cotiz")
  Settings.RegisterAddOnCategory(category)
  ns.optionsCategoryID = category:GetID()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
  if name == ADDON then RegisterOptions() end
end)
