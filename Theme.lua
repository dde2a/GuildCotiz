-- GuildCotiz - Theme.lua
-- Theme sombre autonome, inspire des interfaces modernes de WoW.

local _, ns = ...
local Theme = {}
ns.Theme = Theme

Theme.colors = {
  window = { 0.035, 0.045, 0.055, 0.97 },
  panel = { 0.055, 0.067, 0.080, 0.96 },
  input = { 0.025, 0.032, 0.040, 0.98 },
  button = { 0.090, 0.105, 0.120, 1.00 },
  buttonHover = { 0.145, 0.165, 0.185, 1.00 },
  accent = { 0.95, 0.67, 0.12, 1.00 },
  accentSoft = { 0.28, 0.20, 0.07, 1.00 },
  border = { 0.20, 0.23, 0.26, 1.00 },
  text = { 0.91, 0.93, 0.95, 1.00 },
}

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function SetColor(texture, color)
  texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

local function AddBorder(frame, color, size)
  if frame.GuildCotizBorder then return end
  size = size or 1
  local border = {}
  for i = 1, 4 do
    border[i] = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    SetColor(border[i], color)
  end
  border[1]:SetPoint("TOPLEFT"); border[1]:SetPoint("TOPRIGHT"); border[1]:SetHeight(size)
  border[2]:SetPoint("BOTTOMLEFT"); border[2]:SetPoint("BOTTOMRIGHT"); border[2]:SetHeight(size)
  border[3]:SetPoint("TOPLEFT"); border[3]:SetPoint("BOTTOMLEFT"); border[3]:SetWidth(size)
  border[4]:SetPoint("TOPRIGHT"); border[4]:SetPoint("BOTTOMRIGHT"); border[4]:SetWidth(size)
  frame.GuildCotizBorder = border
end


local function SetBorderColor(frame, color)
  for _, texture in ipairs(frame.GuildCotizBorder or {}) do SetColor(texture, color) end
end

local function HideTemplateTextures(frame)
  for _, region in ipairs({ frame:GetRegions() }) do
    if region:GetObjectType() == "Texture" and region ~= frame.GuildCotizBackground then
      region:SetTexture(nil)
    end
  end
end

function Theme.SkinWindow(frame)
  if not frame or frame.GuildCotizWindowSkinned then return end
  frame.GuildCotizWindowSkinned = true
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(Theme.colors.window))
    frame:SetBackdropBorderColor(unpack(Theme.colors.border))
  end
  local header = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  header:SetPoint("TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", -1, -1)
  header:SetHeight(38)
  header:SetColorTexture(0.055, 0.067, 0.080, 0.98)
  local accent = frame:CreateTexture(nil, "OVERLAY", nil, 7)
  accent:SetPoint("TOPLEFT", 1, -1)
  accent:SetPoint("TOPRIGHT", -1, -1)
  accent:SetHeight(2)
  SetColor(accent, Theme.colors.accent)
  frame.GuildCotizHeader = header
  frame.GuildCotizAccent = accent
  if frame.title then frame.title:SetTextColor(unpack(Theme.colors.accent)) end
end

function Theme.SkinPanel(frame)
  if not frame or frame.GuildCotizPanelSkinned then return end
  frame.GuildCotizPanelSkinned = true
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(Theme.colors.panel))
    frame:SetBackdropBorderColor(unpack(Theme.colors.border))
  end
end

function Theme.SkinButton(button)
  if not button or button.GuildCotizButtonSkinned or not button.GetText then return end
  if not button:GetText() or button:GetText() == "" then return end
  button.GuildCotizButtonSkinned = true
  HideTemplateTextures(button)
  local bg = button:CreateTexture(nil, "BACKGROUND", nil, -2)
  bg:SetAllPoints()
  SetColor(bg, Theme.colors.button)
  button.GuildCotizBackground = bg
  AddBorder(button, Theme.colors.border, 1)
  local font = button:GetFontString()
  if font then font:SetTextColor(unpack(Theme.colors.text)) end
  button:HookScript("OnEnter", function(self)
    if self:IsEnabled() then
      SetColor(self.GuildCotizBackground, Theme.colors.buttonHover)
      SetBorderColor(self, Theme.colors.accent)
    end
  end)
  button:HookScript("OnLeave", function(self)
    SetColor(self.GuildCotizBackground, self.GuildCotizActive and Theme.colors.accentSoft or Theme.colors.button)
    SetBorderColor(self, self.GuildCotizActive and Theme.colors.accent or Theme.colors.border)
  end)
end

function Theme.SetButtonActive(button, active)
  if not button then return end
  Theme.SkinButton(button)
  button.GuildCotizActive = active and true or false
  if button.GuildCotizBackground then
    SetColor(button.GuildCotizBackground, active and Theme.colors.accentSoft or Theme.colors.button)
    SetBorderColor(button, active and Theme.colors.accent or Theme.colors.border)
  end
  local font = button.GetFontString and button:GetFontString()
  if font then font:SetTextColor(unpack(active and Theme.colors.accent or Theme.colors.text)) end
end

function Theme.SkinEditBox(editBox)
  if not editBox or editBox.GuildCotizEditSkinned then return end
  editBox.GuildCotizEditSkinned = true
  HideTemplateTextures(editBox)
  local bg = editBox:CreateTexture(nil, "BACKGROUND", nil, -2)
  bg:SetPoint("TOPLEFT", -2, 2)
  bg:SetPoint("BOTTOMRIGHT", 2, -2)
  SetColor(bg, Theme.colors.input)
  editBox.GuildCotizBackground = bg
  AddBorder(editBox, Theme.colors.border, 1)
  editBox:SetTextColor(unpack(Theme.colors.text))
  editBox:HookScript("OnEditFocusGained", function(self) SetBorderColor(self, Theme.colors.accent) end)
  editBox:HookScript("OnEditFocusLost", function(self) SetBorderColor(self, Theme.colors.border) end)
end

function Theme.AutoSkin(root)
  if not root then return end
  local function Visit(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
      local kind = child:GetObjectType()
      if kind == "EditBox" then Theme.SkinEditBox(child)
      elseif kind == "Button" then Theme.SkinButton(child) end
      Visit(child)
    end
  end
  Visit(root)
end
