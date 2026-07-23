-- GuildCotiz - Export.lua
-- Generation du CSV et fenetre de copier-coller (vers Excel / Google Sheets).

local ADDON, ns = ...

local function DateStr(t)
  if not t then return "" end
  return date("%Y-%m-%d", t)
end

-- Echappe une valeur pour CSV selon le separateur choisi
local function CSVCell(value, sep)
  value = tostring(value or "")
  if value:find('[' .. sep .. '"\n]') then
    value = '"' .. value:gsub('"', '""') .. '"'
  end
  return value
end

local function StatusText(st)
  if st == "ajour" then return "A jour"
  elseif st == "avance" then return "En avance"
  elseif st == "retard" then return "En retard"
  elseif st == "paye" then return "Paye"
  elseif st == "couvert" then return "Couvert (avance)"
  elseif st == "nonpaye" then return "Non paye"
  elseif st == "norraid" then return "Aucun raid"
  end
  return st or ""
end
ns.StatusText = StatusText

-- Or en nombre decimal avec 2 decimales (point). Compatible Excel FR + sep ";"
local function GoldNum(copper)
  return string.format("%.2f", ns.CopperToGold(copper))
end

--------------------------------------------------------------------------------
-- Construction du CSV : resume par joueur
--------------------------------------------------------------------------------
function ns.BuildSummaryCSV()
  local g = ns.GetGuildDB(true)
  if not g then return "" end
  local sep = GuildCotizDB.settings.csvSeparator or ";"
  local now = time()
  local lines = {}

  local header = {
    "Joueur", "Rang", "Debut suivi", "Raids effectues", "Total depose (po)",
    "Du cumule (po)", "Solde (po)", "Statut",
    "Raids de retard", "Raids payes d'avance", "Manque (po)",
  }
  local htxt = {}
  for _, h in ipairs(header) do htxt[#htxt + 1] = CSVCell(h, sep) end
  lines[#lines + 1] = table.concat(htxt, sep)

  for _, entry in ipairs(ns.GetSortedMembers(g, { includeInactive = true })) do
    local m = entry.m
    local s = ns.GetMemberStatus(g, m, entry.name, now)
    local row = {
      entry.name,
      m.rankName or "",
      DateStr(s.startT),
      s.raids,
      GoldNum(s.paid),
      GoldNum(s.owed),
      GoldNum(s.balance),
      StatusText(s.status),
      s.raidsBehind,
      s.raidsAhead,
      GoldNum(s.due),
    }
    local rtxt = {}
    for _, v in ipairs(row) do rtxt[#rtxt + 1] = CSVCell(v, sep) end
    lines[#lines + 1] = table.concat(rtxt, sep)
  end

  return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Construction du CSV : detail semaine par semaine (tous les joueurs)
--------------------------------------------------------------------------------
function ns.BuildWeeklyCSV(onlyPlayer)
  local g = ns.GetGuildDB(true)
  if not g then return "" end
  local sep = GuildCotizDB.settings.csvSeparator or ";"
  local now = time()
  local lines = {}

  local header = {
    "Joueur", "Semaine #", "Annee", "No semaine ISO", "Debut semaine", "Fin semaine",
    "Raids", "Du semaine (po)", "Depose (po)",
    "Cumul raids", "Cumule du (po)", "Cumule paye (po)", "Solde fin (po)", "Statut",
  }
  local htxt = {}
  for _, h in ipairs(header) do htxt[#htxt + 1] = CSVCell(h, sep) end
  lines[#lines + 1] = table.concat(htxt, sep)

  for _, entry in ipairs(ns.GetSortedMembers(g, { includeInactive = true })) do
    if not onlyPlayer or entry.name:lower() == onlyPlayer:lower() then
      local rows = ns.GetWeeklyBreakdown(g, entry.m, entry.name, now)
      for _, r in ipairs(rows) do
        local isoYear, isoWeek = ns.ISOWeek(r.weekStart)
        local row = {
          entry.name, r.index, isoYear, isoWeek,
          DateStr(r.weekStart), DateStr(r.weekEnd - 1),
          r.raids, GoldNum(r.dueWeek), GoldNum(r.deposited),
          r.cumRaids, GoldNum(r.cumOwed), GoldNum(r.cumPaid),
          GoldNum(r.balanceEnd), StatusText(r.status),
        }
        local rtxt = {}
        for _, v in ipairs(row) do rtxt[#rtxt + 1] = CSVCell(v, sep) end
        lines[#lines + 1] = table.concat(rtxt, sep)
      end
    end
  end

  return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Construction du CSV : retraits (sorties d'or du coffre)
--------------------------------------------------------------------------------
function ns.BuildWithdrawCSV(onlyPlayer)
  local g = ns.GetGuildDB(true)
  if not g then return "" end
  local sep = GuildCotizDB.settings.csvSeparator or ";"
  local lines = {}

  local header = { "Joueur", "Rang", "Date", "Heure", "Montant (po)", "Type" }
  local htxt = {}
  for _, h in ipairs(header) do htxt[#htxt + 1] = CSVCell(h, sep) end
  lines[#lines + 1] = table.concat(htxt, sep)

  for _, w in ipairs(ns.GetAllWithdrawals(g)) do
    if not onlyPlayer or w.name:lower() == onlyPlayer:lower() then
      local row = {
        w.name, w.rankName,
        date("%Y-%m-%d", w.t), date("%H:%M", w.t),
        GoldNum(w.a),
        ns.WITHDRAW_TYPES[w.kind] or w.kind or "?",
      }
      local rtxt = {}
      for _, v in ipairs(row) do rtxt[#rtxt + 1] = CSVCell(v, sep) end
      lines[#lines + 1] = table.concat(rtxt, sep)
    end
  end

  return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Fenetre de copier-coller
--------------------------------------------------------------------------------
local exportFrame

local function CreateExportFrame()
  local frame = CreateFrame("Frame", "GuildCotizExportFrame", UIParent, "BackdropTemplate")
  frame:SetSize(560, 420)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Export CSV")
  frame.title = title

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
  hint:SetText("Ctrl+A pour tout selectionner, Ctrl+C pour copier, puis colle dans Excel / Google Sheets.")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local scroll = CreateFrame("ScrollFrame", "GuildCotizExportScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -60)
  scroll:SetPoint("BOTTOMRIGHT", -34, 46)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(500)
  edit:SetAutoFocus(false)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  scroll:SetScrollChild(edit)
  frame.edit = edit

  local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  selectBtn:SetSize(160, 24)
  selectBtn:SetPoint("BOTTOMLEFT", 16, 14)
  selectBtn:SetText("Tout selectionner")
  selectBtn:SetScript("OnClick", function()
    edit:SetFocus()
    edit:HighlightText()
  end)

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetSize(120, 24)
  closeBtn:SetPoint("BOTTOMRIGHT", -30, 14)
  closeBtn:SetText("Fermer")
  closeBtn:SetScript("OnClick", function() frame:Hide() end)

  return frame
end

-- Affiche la fenetre avec le texte donne
function ns.ShowExport(text, titleText)
  if not exportFrame then exportFrame = CreateExportFrame() end
  exportFrame.title:SetText(titleText or "Export CSV")
  exportFrame.edit:SetText(text or "")
  exportFrame.edit:SetCursorPosition(0)
  exportFrame:Show()
  exportFrame.edit:SetFocus()
  exportFrame.edit:HighlightText()
end
