-- GuildCotiz - Profiles.lua
-- Import/export securise des reglages et associations main/reroll.

local ADDON, ns = ...

local PREFIX = "GC1:"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Escape(value)
  return tostring(value or ""):gsub("([^%w%-%._])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function Unescape(value)
  return (value or ""):gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

local function Base64Encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = B64:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
    out[#out + 1] = B64:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
    out[#out + 1] = b and B64:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
    out[#out + 1] = c and B64:sub(n % 64 + 1, n % 64 + 1) or "="
  end
  return table.concat(out)
end

local function Base64Decode(data)
  data = (data or ""):gsub("%s", "")
  if #data == 0 or #data % 4 ~= 0 then return nil end
  local reverse = {}
  for i = 1, #B64 do reverse[B64:sub(i, i)] = i - 1 end
  local out = {}
  for i = 1, #data, 4 do
    local c1, c2, c3, c4 = data:sub(i, i), data:sub(i + 1, i + 1), data:sub(i + 2, i + 2), data:sub(i + 3, i + 3)
    if not reverse[c1] or not reverse[c2] or (c3 ~= "=" and not reverse[c3]) or (c4 ~= "=" and not reverse[c4]) then return nil end
    local n = reverse[c1] * 262144 + reverse[c2] * 4096
      + (reverse[c3] or 0) * 64 + (reverse[c4] or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if c3 ~= "=" then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
    if c4 ~= "=" then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end

local function AddSet(lines, code, values)
  for value, enabled in pairs(values or {}) do
    if enabled then lines[#lines + 1] = code .. "|" .. Escape(value) end
  end
end

function ns.BuildProfile(scope)
  local g = ns.GetGuildDB(true)
  if not g then return nil, "NO_GUILD" end
  scope = (scope == "config" or scope == "alts") and scope or "both"
  local lines = { "VERSION|1", "SCOPE|" .. scope, "GUILD|" .. Escape(ns.GetGuildKey() or "") }
  if scope == "config" or scope == "both" then
    lines[#lines + 1] = "C|raidAmount|" .. tostring(g.config.raidAmount or 0)
    lines[#lines + 1] = "C|seasonStart|" .. tostring(g.config.seasonStart or 0)
    for _, period in ipairs(ns.EnsureRatePeriods(g)) do
      lines[#lines + 1] = "S|" .. tostring(period.start) .. "|" .. tostring(period.amount)
        .. "|" .. Escape(period.name or "")
    end
    lines[#lines + 1] = "C|csvSeparator|" .. Escape((GuildCotizDB.settings or {}).csvSeparator or ";")
    lines[#lines + 1] = "C|rankRoles|1"
    AddSet(lines, "H", g.config.hiddenRanks)
    AddSet(lines, "R", g.config.altRanks)
    AddSet(lines, "M", g.config.mainRanks)
  end
  if scope == "alts" or scope == "both" then
    for alt, main in pairs(g.altToMain or {}) do
      lines[#lines + 1] = "L|" .. Escape(alt) .. "|" .. Escape(main)
    end
  end
  local header, records = { lines[1], lines[2], lines[3] }, {}
  for i = 4, #lines do records[#records + 1] = lines[i] end
  table.sort(records)
  for _, record in ipairs(records) do header[#header + 1] = record end
  return PREFIX .. Base64Encode(table.concat(header, "\n"))
end

function ns.ParseProfile(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text:sub(1, #PREFIX) ~= PREFIX then return nil, "PREFIX" end
  local raw = Base64Decode(text:sub(#PREFIX + 1))
  if not raw then return nil, "BASE64" end
  local profile = { config = {}, ratePeriods = {}, hiddenRanks = {}, altRanks = {}, mainRanks = {}, links = {} }
  for line in raw:gmatch("[^\r\n]+") do
    local parts = {}
    for part in (line .. "|"):gmatch("(.-)|") do parts[#parts + 1] = part end
    local code = parts[1]
    if code == "VERSION" then profile.version = tonumber(parts[2])
    elseif code == "SCOPE" then profile.scope = parts[2]
    elseif code == "GUILD" then profile.guild = Unescape(parts[2])
    elseif code == "C" then profile.config[parts[2]] = Unescape(parts[3])
    elseif code == "S" then
      local startT, amount = tonumber(parts[2]), tonumber(parts[3])
      if startT and amount then
        profile.ratePeriods[#profile.ratePeriods + 1] = {
          start = startT, amount = amount, name = Unescape(parts[4] or ""),
        }
      end
    elseif code == "H" then profile.hiddenRanks[Unescape(parts[2])] = true
    elseif code == "R" then profile.altRanks[Unescape(parts[2])] = true
    elseif code == "M" then profile.mainRanks[Unescape(parts[2])] = true
    elseif code == "L" then profile.links[Unescape(parts[2])] = Unescape(parts[3]) end
  end
  if profile.version ~= 1
    or (profile.scope ~= "config" and profile.scope ~= "alts" and profile.scope ~= "both") then
    return nil, "VERSION"
  end
  profile.linkCount, profile.altRankCount, profile.hiddenRankCount = 0, 0, 0
  for _ in pairs(profile.links) do profile.linkCount = profile.linkCount + 1 end
  for _ in pairs(profile.altRanks) do profile.altRankCount = profile.altRankCount + 1 end
  for _ in pairs(profile.hiddenRanks) do profile.hiddenRankCount = profile.hiddenRankCount + 1 end
  return profile
end

function ns.ApplyProfile(profile)
  local g = ns.GetGuildDB(true)
  if not g or not profile then return false end
  if profile.scope == "config" or profile.scope == "both" then
    local raidAmount = tonumber(profile.config.raidAmount)
    local seasonStart = tonumber(profile.config.seasonStart)
    if profile.ratePeriods and #profile.ratePeriods > 0 then
      g.config.ratePeriods = CopyTable(profile.ratePeriods)
      g.config.ratePeriodsMigrated = true
      table.sort(g.config.ratePeriods, function(a, b) return a.start < b.start end)
      local current = g.config.ratePeriods[#g.config.ratePeriods]
      g.config.raidAmount, g.config.seasonStart = current.amount, current.start
    elseif raidAmount and raidAmount >= 0 and seasonStart and seasonStart > 0 then
      ns.SetRatePeriod(g, seasonStart, raidAmount)
    end
    GuildCotizDB.settings.csvSeparator = profile.config.csvSeparator or ";"
    g.config.hiddenRanks = CopyTable(profile.hiddenRanks)
    g.config.altRanks = CopyTable(profile.altRanks)
    g.config.mainRanks = CopyTable(profile.mainRanks)
    if profile.config.rankRoles ~= "1" then
      for _, member in pairs(g.members or {}) do
        local rank = member.rankName or "?"
        if not g.config.altRanks[rank] then g.config.mainRanks[rank] = true end
      end
    end
    g.config.altRanksInitialized = true
    g.config.rankRolesInitialized = true
  end
  if profile.scope == "alts" or profile.scope == "both" then
    g.altToMain = {}
    for alt, main in pairs(profile.links) do
      if g.members[alt] and g.members[main] then ns.SetCharacterMain(g, alt, main) end
    end
  end
  ns.InvalidateCaches()
  if ns.RefreshUI then ns.RefreshUI() end
  return true
end

local function CountProfile(profile)
  profile.linkCount, profile.altRankCount, profile.hiddenRankCount = 0, 0, 0
  for _ in pairs(profile.links or {}) do profile.linkCount = profile.linkCount + 1 end
  for _ in pairs(profile.altRanks or {}) do profile.altRankCount = profile.altRankCount + 1 end
  for _ in pairs(profile.hiddenRanks or {}) do profile.hiddenRankCount = profile.hiddenRankCount + 1 end
  return profile
end

local function CaptureCurrentProfile()
  local g = ns.GetGuildDB(true)
  if not g then return nil end
  ns.EnsureRankRoles(g)
  return CountProfile({
    version = 1,
    scope = "both",
    guild = ns.GetGuildKey(),
    config = {
      raidAmount = tostring(g.config.raidAmount or 0),
      seasonStart = tostring(g.config.seasonStart or 0),
      csvSeparator = (GuildCotizDB.settings or {}).csvSeparator or ";",
      rankRoles = "1",
    },
    ratePeriods = CopyTable(ns.EnsureRatePeriods(g)),
    hiddenRanks = CopyTable(g.config.hiddenRanks or {}),
    altRanks = CopyTable(g.config.altRanks or {}),
    mainRanks = CopyTable(g.config.mainRanks or {}),
    links = CopyTable(g.altToMain or {}),
  })
end

local function CleanProfileName(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or #name > 40 then return nil end
  return name
end

function ns.EnsureProfileStorage()
  GuildCotizDB.profiles = GuildCotizDB.profiles or {}
  GuildCotizDB.activeProfiles = GuildCotizDB.activeProfiles or {}
  local guildKey = ns.GetGuildKey()
  if not guildKey then return nil end
  if not GuildCotizDB.profiles.Default then
    GuildCotizDB.profiles.Default = CaptureCurrentProfile()
  end
  GuildCotizDB.activeProfiles[guildKey] = GuildCotizDB.activeProfiles[guildKey] or "Default"
  return GuildCotizDB.profiles, GuildCotizDB.activeProfiles[guildKey]
end

function ns.GetActiveProfileName()
  local _, active = ns.EnsureProfileStorage()
  return active or "Default"
end

function ns.GetProfileNames()
  local profiles = ns.EnsureProfileStorage()
  local names = {}
  for name in pairs(profiles or {}) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    if a == "Default" then return true end
    if b == "Default" then return false end
    return a:lower() < b:lower()
  end)
  return names
end

function ns.SaveActiveProfile()
  local profiles, active = ns.EnsureProfileStorage()
  if not profiles or not active then return false end
  profiles[active] = CaptureCurrentProfile()
  return true
end

function ns.SelectProfile(name)
  name = CleanProfileName(name)
  local profiles, active = ns.EnsureProfileStorage()
  if not name or not profiles or not profiles[name] then return false end
  if active ~= name then ns.SaveActiveProfile() end
  GuildCotizDB.activeProfiles[ns.GetGuildKey()] = name
  return ns.ApplyProfile(CopyTable(profiles[name]))
end

function ns.StoreImportedProfile(name, imported)
  name = CleanProfileName(name)
  local profiles = ns.EnsureProfileStorage()
  if not name or not profiles then return false, "invalid" end
  for existingName in pairs(profiles) do
    if existingName:lower() == name:lower() then return false, "exists" end
  end
  ns.SaveActiveProfile()
  if not ns.ApplyProfile(imported) then return false, "invalid" end
  profiles[name] = CaptureCurrentProfile()
  GuildCotizDB.activeProfiles[ns.GetGuildKey()] = name
  return true
end

function ns.DeleteProfile(name)
  local profiles, active = ns.EnsureProfileStorage()
  if not profiles or name == "Default" or not profiles[name] then return false end
  profiles[name] = nil
  if active == name then
    GuildCotizDB.activeProfiles[ns.GetGuildKey()] = "Default"
    ns.ApplyProfile(CopyTable(profiles.Default))
  end
  return true
end

function ns.ResetActiveProfile()
  local profiles, active = ns.EnsureProfileStorage()
  if not profiles or not active then return false end
  if active == "Default" then
    local g = ns.GetGuildDB(true)
    if not g then return false end
    local now = time()
    g.config.raidAmount = 1000 * ns.COPPER_PER_GOLD
    g.config.seasonStart = now - (now % 86400)
    g.config.ratePeriods = { { start = g.config.seasonStart, amount = g.config.raidAmount, name = "S1" } }
    g.config.ratePeriodsMigrated = true
    g.config.hiddenRanks = {}
    g.config.altRanks, g.config.mainRanks = {}, {}
    g.config.rankRolesInitialized = false
    g.config.altRanksInitialized = false
    ns.EnsureRankRoles(g)
    g.altToMain = {}
    ns.InvalidateCaches()
    profiles.Default = CaptureCurrentProfile()
    if ns.RefreshUI then ns.RefreshUI() end
    return true
  end
  profiles[active] = CopyTable(profiles.Default)
  return ns.ApplyProfile(CopyTable(profiles[active]))
end
