-- GuildCotiz - Export.lua
-- Generation du CSV et fenetre de copier-coller (vers Excel / Google Sheets).

local ADDON, ns = ...
local L = ns.L

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
  if st == "ajour" then return L("STATUS_CURRENT")
  elseif st == "avance" then return L("STATUS_AHEAD")
  elseif st == "retard" then return L("STATUS_BEHIND")
  elseif st == "paye" then return L("STATUS_PAID")
  elseif st == "couvert" then return L("STATUS_COVERED")
  elseif st == "nonpaye" then return L("STATUS_UNPAID")
  elseif st == "norraid" then return L("STATUS_NO_RAID")
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
    L("CSV_PLAYER"), L("CSV_RANK"), L("CSV_TRACKING_START"), L("CSV_RAIDS_ATTENDED"),
    L("CSV_TOTAL_DEPOSITED"), L("CSV_TOTAL_DUE"), L("CSV_BALANCE"), L("CSV_STATUS"),
    L("CSV_RAIDS_BEHIND"), L("CSV_RAIDS_AHEAD"), L("CSV_MISSING"),
  }
  local htxt = {}
  for _, h in ipairs(header) do htxt[#htxt + 1] = CSVCell(h, sep) end
  lines[#lines + 1] = table.concat(htxt, sep)

  for _, entry in ipairs(ns.GetSortedMembers(g, { includeInactive = true })) do
    if not ns.IsAlt(g, entry.name) then
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
  end

  return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Construction du CSV : detail semaine par semaine (tous les joueurs)
--------------------------------------------------------------------------------
function ns.BuildWeeklyCSV(onlyPlayer, individual)
  local g = ns.GetGuildDB(true)
  if not g then return "" end
  local sep = GuildCotizDB.settings.csvSeparator or ";"
  local now = time()
  local lines = {}

  local header = {
    L("CSV_PLAYER"), L("CSV_WEEK_NUMBER"), L("CSV_YEAR"), L("CSV_ISO_WEEK"),
    L("CSV_WEEK_START"), L("CSV_WEEK_END"), L("CSV_SEASON"), L("CSV_RAIDS"), L("CSV_RAID_RATE"), L("CSV_WEEK_DUE"),
    L("CSV_DEPOSITED"), L("CSV_DEPOSIT_SOURCE"), L("CSV_CUMULATIVE_RAIDS"), L("CSV_CUMULATIVE_DUE"),
    L("CSV_CUMULATIVE_PAID"), L("CSV_END_BALANCE"), L("CSV_STATUS"),
  }
  local htxt = {}
  for _, h in ipairs(header) do htxt[#htxt + 1] = CSVCell(h, sep) end
  lines[#lines + 1] = table.concat(htxt, sep)

  local entries = ns.GetSortedMembers(g, { includeInactive = true })
  for _, entry in ipairs(entries) do
    local selected
    if individual and onlyPlayer then
      selected = entry.name:lower() == onlyPlayer:lower()
    else
      selected = not ns.IsAlt(g, entry.name)
        and (not onlyPlayer or entry.name:lower() == ns.ResolveMain(g, onlyPlayer):lower())
    end
    if selected then
      local rows = individual
        and ns.GetIndividualWeeklyBreakdown(g, entry.m, entry.name, now)
        or ns.GetWeeklyBreakdown(g, entry.m, entry.name, now)
      for _, r in ipairs(rows) do
        local isoYear, isoWeek = ns.ISOWeek(r.weekStart)
        local row = {
          entry.name, r.index, isoYear, isoWeek,
          DateStr(r.weekStart), DateStr(r.weekEnd - 1), r.seasonName,
          r.raids, GoldNum(r.raidAmount), GoldNum(r.dueWeek), GoldNum(r.deposited),
          r.depositOverridden and L("SOURCE_MANUAL") or L("SOURCE_BANK"),
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

  local header = {
    L("CSV_PLAYER"), L("CSV_RANK"), L("CSV_DATE"),
    L("CSV_TIME"), L("CSV_AMOUNT"), L("CSV_TYPE"),
  }
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
-- Historique lisible des transactions originales d'un main et de ses rerolls
--------------------------------------------------------------------------------
function ns.BuildDepositHistoryCSV(mainName, individual)
  local g = ns.GetGuildDB(true)
  if not g or not mainName then return "" end
  if not individual then mainName = ns.ResolveMain(g, mainName) end
  local sep = GuildCotizDB.settings.csvSeparator or ";"
  local lines = {
    table.concat({
      CSVCell(L("CSV_PLAYER"), sep),
      CSVCell(L("CSV_DATE"), sep),
      CSVCell(L("CSV_TIME"), sep),
      CSVCell(L("CSV_AMOUNT"), sep),
    }, sep),
  }
  local transactions
  if individual then
    transactions = {}
    local member = g.members[mainName]
    for _, deposit in ipairs(member and member.deposits or {}) do
      transactions[#transactions + 1] = { name = mainName, t = deposit.t, a = deposit.a }
    end
    table.sort(transactions, function(a, b) return a.t > b.t end)
  else
    transactions = ns.GetDepositTransactionsForGroup(g, mainName)
  end
  if #transactions == 0 then return L("NO_DEPOSIT_HISTORY") end
  for _, tx in ipairs(transactions) do
    lines[#lines + 1] = table.concat({
      CSVCell(tx.name, sep),
      CSVCell(date("%Y-%m-%d", tx.t), sep),
      CSVCell(date("%H:%M", tx.t), sep),
      CSVCell(GoldNum(tx.a), sep),
    }, sep)
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
  title:SetText(L("EXPORT_CSV"))
  frame.title = title

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
  hint:SetText(L("CSV_HINT"))

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
  selectBtn:SetText(L("SELECT_ALL"))
  selectBtn:SetScript("OnClick", function()
    edit:SetFocus()
    edit:HighlightText()
  end)

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetSize(120, 24)
  closeBtn:SetPoint("BOTTOMRIGHT", -30, 14)
  closeBtn:SetText(L("CLOSE"))
  closeBtn:SetScript("OnClick", function() frame:Hide() end)

  ns.Theme.SkinWindow(frame)
  ns.Theme.AutoSkin(frame)

  return frame
end

-- Affiche la fenetre avec le texte donne
function ns.ShowExport(text, titleText)
  if not exportFrame then exportFrame = CreateExportFrame() end
  exportFrame.title:SetText(titleText or L("EXPORT_CSV"))
  exportFrame.edit:SetText(text or "")
  exportFrame.edit:SetCursorPosition(0)
  exportFrame:Show()
  exportFrame.edit:SetFocus()
  exportFrame.edit:HighlightText()
end
