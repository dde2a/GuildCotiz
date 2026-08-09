-- Geometrie des fenetres de l'addon, hors WoW.
--
-- Le panneau est construit par une chaine d'ancrages relatifs : chaque bloc se
-- place sous le precedent. Il suffit d'oublier de re-ancrer un bloc quand on en
-- insere un nouveau pour que deux sections se superposent, ce que la syntaxe ne
-- detecte pas. On rejoue donc la construction avec un faux moteur de frames,
-- on resout les positions, et on verifie qu'aucun libelle n'en recouvre un autre.
--
-- Couvre la page d'options ET la fenetre principale, dont la barre d'outils est
-- saturee : les onglets et le filtre s'enchainent depuis la gauche pendant que
-- le bouton des rangs est colle au bord droit, donc tout ajout au milieu vient
-- buter sur l'un ou sur l'autre.

local REPO = (arg[0]:match("^(.*)tests[/\\][^/\\]+$")) or "./"

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

local widgets = {}

local FONT_HEIGHT = {
  GameFontNormalHuge  = 22,
  GameFontNormalLarge = 18,
  GameFontNormal      = 14,
  GameFontHighlight    = 14,
  GameFontHighlightSmall = 12,
}

-- text n'existe pas tant que SetText n'a pas ete appele : sans rawget, le
-- fallback du metatable renverrait une fonction au lieu de nil.
local function TextOf(w) return rawget(w, "text") end
local function ParentOf(w) return rawget(w, "parent") end

local Widget = {}
Widget.__index = function(tbl, key)
  local direct = rawget(Widget, key)
  if direct then return direct end
  -- Toute autre methode de l'API WoW est sans effet sur la geometrie.
  return function() return tbl end
end

local function NewWidget(kind, parent, template, fontObject)
  local w = setmetatable({
    kind = kind, parent = parent, template = template,
    width = 0, height = 0, points = {}, text = nil,
    fontHeight = FONT_HEIGHT[fontObject or ""] or 14,
    children = {},
  }, Widget)
  if template == "UICheckButtonTemplate" then w.width, w.height = 26, 26 end
  if template == "UIDropDownMenuTemplate" then w.width, w.height = 160, 32 end
  widgets[#widgets + 1] = w
  if parent and parent.children then parent.children[#parent.children + 1] = w end
  return w
end

function Widget:SetSize(width, height) self.width, self.height = width, height end
function Widget:SetWidth(width) self.width = width end
function Widget:SetHeight(height) self.height = height end
function Widget:SetText(text) self.text = text; return self end
function Widget:GetText() return rawget(self, "text") end

function Widget:ClearAllPoints() self.points = {} end
function Widget:SetPoint(point, a, b, c, d)
  local relTo, relPoint, x, y
  if type(a) == "table" then
    relTo, relPoint, x, y = a, b, c, d
  elseif type(a) == "string" then
    relTo, relPoint, x, y = self.parent, a, b, c
  else
    relTo, relPoint, x, y = self.parent, point, a, b
  end
  self.points[#self.points + 1] = {
    point = point, relTo = relTo, relPoint = relPoint or point,
    x = x or 0, y = y or 0,
  }
end
function Widget:CreateFontString(_, _, fontObject)
  return NewWidget("FontString", self, nil, fontObject)
end
function Widget:CreateTexture() return NewWidget("Texture", self) end
function Widget:GetChecked() return false end
function Widget:Hide() rawset(self, "hidden", true) end
function Widget:Show() rawset(self, "hidden", false) end
function Widget:SetShown(v) rawset(self, "hidden", not v) end
-- false pousse UI.Toggle vers la branche Show, donc vers la construction.
function Widget:IsShown() return not rawget(self, "hidden") end

local function IsVisible(w)
  while w do
    if rawget(w, "hidden") then return false end
    w = ParentOf(w)
  end
  return true
end

local function RootOf(w)
  while w and ParentOf(w) do w = ParentOf(w) end
  return w
end

--------------------------------------------------------------------------------
-- Resolution des positions (repere ecran : y croissant vers le haut)
--------------------------------------------------------------------------------

local function EffectiveHeight(w)
  if w.kind == "FontString" then return w.fontHeight end
  return (w.height > 0) and w.height or 14
end

-- Les sequences d'echappement de WoW ne sont pas rendues : les compter comme
-- des caracteres visibles gonfle la largeur et fabrique de fausses collisions.
local function VisibleText(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  return text
end

local function EffectiveWidth(w)
  if w.kind == "FontString" then return #VisibleText(TextOf(w)) * 6.2 end
  return (w.width > 0) and w.width or 100
end

local resolving = {}
local resolvedOf = {}
local function Resolve(w)
  if resolvedOf[w] then return resolvedOf[w] end
  assert(not resolving[w], "cycle d'ancrage detecte")
  resolving[w] = true

  local h, width = EffectiveHeight(w), EffectiveWidth(w)
  local top, left
  for _, p in ipairs(w.points) do
    local base = p.relTo and Resolve(p.relTo) or { top = 0, left = 0, height = 0, width = 0 }
    local anchorY = p.relPoint:find("BOTTOM") and (base.top - base.height) or base.top
    local anchorX = p.relPoint:find("RIGHT") and (base.left + base.width) or base.left
    local candidateTop = anchorY + p.y
    local candidateLeft = anchorX + p.x
    if p.point:find("BOTTOM") then candidateTop = candidateTop + h end
    if p.point:find("RIGHT") then candidateLeft = candidateLeft - width end
    top = top and math.max(top, candidateTop) or candidateTop
    left = left and math.min(left, candidateLeft) or candidateLeft
  end

  resolving[w] = nil
  resolvedOf[w] = { top = top or 0, left = left or 0, height = h, width = width }
  return resolvedOf[w]
end

--------------------------------------------------------------------------------
-- Environnement WoW minimal
--------------------------------------------------------------------------------

local loaders = {}
local env = setmetatable({}, { __index = _G })
env.time, env.date, env.print = os.time, os.date, function() end
env.CopyTable = function(t)
  local out = {}
  for k, v in pairs(t) do out[k] = (type(v) == "table") and env.CopyTable(v) or v end
  return out
end
local namedFrames = {}
env.CreateFrame = function(kind, name, parent, template)
  local w = NewWidget(kind, parent, template)
  if name then namedFrames[name] = w end
  if kind == "Frame" and not template then w.width, w.height = 0, 0 end
  w.RegisterEvent = function() end
  w.SetScript = function(self, script, fn)
    if script == "OnEvent" then loaders[#loaders + 1] = fn end
    return self
  end
  return w
end
env.IsInGuild = function() return true end
env.GetGuildInfo = function() return "TestGuild", nil, nil, "TestRealm" end
env.GetRealmName = function() return "TestRealm" end
env.GetNormalizedRealmName = function() return "TestRealm" end
env.UnitName = function() return "Officier" end
env.GetLocale = function() return "frFR" end
env.BreakUpLargeNumbers = tostring
env.GetNumGuildMembers = function() return 0 end
env.GetGuildRosterInfo = function() return nil end
env.C_GuildInfo, env.C_Timer = {}, { After = function() end }
env.UIParent = NewWidget("Frame")
env.GameTooltip = NewWidget("Frame")
env.UISpecialFrames = {}
env.tinsert = table.insert
env.UIDropDownMenu_SetWidth = function(frame, width) frame.width = width end
env.UIDropDownMenu_SetText = function() end
env.UIDropDownMenu_Initialize = function() end
env.UIDropDownMenu_CreateInfo = function() return {} end
env.UIDropDownMenu_AddButton = function() end
env.CloseDropDownMenus = function() end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.MenuUtil = { CreateContextMenu = function() end }
env.StaticPopupDialogs = {}
env.StaticPopup_Show = function() end
env.ChatFontNormal = "ChatFontNormal"
env.SlashCmdList = {}
env.Settings = {
  RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end } end,
  RegisterAddOnCategory = function() end,
}
env.LibStub = setmetatable({}, { __call = function()
  return setmetatable({}, { __index = function() return function() end end })
end })

local ns = {}
ns.Theme = setmetatable({}, { __index = function() return function() end end })
for _, file in ipairs({ "Locale.lua", "Core.lua", "Profiles.lua", "Export.lua", "UI.lua", "Options.lua" }) do
  local chunk = assert(loadfile(REPO .. file))
  setfenv(chunk, env)
  chunk("GuildCotiz", ns)
end
env.GuildCotizDB = { guilds = {}, settings = { syncEnabled = true, syncChannel = "OFFICER" } }
ns.Sync = { Channel = function() return "OFFICER" end, Broadcast = function() end }

for _, fn in ipairs(loaders) do fn(nil, "ADDON_LOADED", "GuildCotiz") end

-- Toggle construit la fenetre principale au premier appel.
local builtMain = pcall(function() ns.UI.Toggle() end)

--------------------------------------------------------------------------------
-- Verifications
--------------------------------------------------------------------------------

local failures = 0
local function check(label, condition, detail)
  if condition then
    print(string.format("  ok   %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL %s %s", label, detail or ""))
  end
end

-- Seuls les elements portant du texte sont regardes : ce sont eux que l'oeil
-- voit se chevaucher.
local labelled = {}
for _, w in ipairs(widgets) do
  local text = TextOf(w)
  if type(text) == "string" and text ~= "" and w.kind ~= "Texture"
    and #w.points > 0 and IsVisible(w) then
    local ok = pcall(Resolve, w)
    if ok and resolvedOf[w] and resolvedOf[w].top ~= 0 then
      labelled[#labelled + 1] = w
    end
  end
end

print("== Options et fenetre principale : aucun libelle n'en recouvre un autre ==")
print(string.format("  %d elements textuels positionnes", #labelled))

local function Overlaps(a, b)
  local ra, rb = resolvedOf[a], resolvedOf[b]
  local vertical = (ra.top > rb.top - rb.height) and (ra.top - ra.height < rb.top)
  local horizontal = (ra.left < rb.left + rb.width) and (ra.left + ra.width > rb.left)
  return vertical and horizontal
end

local collisions = {}
for i = 1, #labelled do
  for j = i + 1, #labelled do
    local a, b = labelled[i], labelled[j]
    -- Un parent direct englobe legitimement son enfant.
    if ParentOf(a) ~= b and ParentOf(b) ~= a and RootOf(a) == RootOf(b) and Overlaps(a, b) then
      collisions[#collisions + 1] = string.format("%q x %q", TextOf(a), TextOf(b))
    end
  end
end
check("aucune collision", #collisions == 0,
  "\n         " .. table.concat(collisions, "\n         "))

print("== Les sections se suivent de haut en bas ==")
local L = ns.L
local order = {
  { L("OPTIONS_DESCRIPTION"), "description" },
  { L("SYNC_SECTION"), "sync" },
  { L("RANK_ROLES_TITLE"), "rangs" },
  { L("PROFILE_MANAGER"), "profil actif" },
  { L("PROFILE_SHARING"), "import/export" },
}
local byText = {}
for _, w in ipairs(labelled) do byText[TextOf(w)] = byText[TextOf(w)] or w end

local previousTop, previousName
for _, entry in ipairs(order) do
  local w = byText[entry[1]]
  if not w then
    check("section presente : " .. entry[2], false, "(libelle introuvable)")
  else
    if previousTop then
      check(entry[2] .. " est sous " .. previousName,
        resolvedOf[w].top < previousTop - 10,
        string.format("(y=%.0f vs %.0f)", resolvedOf[w].top, previousTop))
    end
    previousTop, previousName = resolvedOf[w].top, entry[2]
  end
end

print("== Le panneau est assez haut pour tout contenir ==")
local lowest = 0
for _, w in ipairs(labelled) do
  lowest = math.min(lowest, resolvedOf[w].top - resolvedOf[w].height)
end
local panelHeight
for _, w in ipairs(widgets) do
  if w.height == 1060 or (w.width == 680 and w.height > 0) then panelHeight = w.height end
end
check("hauteur suffisante", panelHeight and (panelHeight >= -lowest + 20),
  string.format("(contenu %.0f px, panneau %s px)", -lowest, tostring(panelHeight)))

print("")
if failures == 0 then
  print("TOUS LES TESTS PASSENT")
  os.exit(0)
end
print(string.format("%d TEST(S) EN ECHEC", failures))
os.exit(1)
