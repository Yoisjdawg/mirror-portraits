-- Other players with Mirror Portraits see your profile name and title in your tooltip (sheets/share.json).
-- Only text travels: WoW add-ons cannot send pictures to each other.
local _, ns = ...
local PREFIX = "MIRRORPT"
local PROTO = "1"
ns.known = {}
local last = {}

local function rowById(id)
  for _, r in ipairs(ns.Data.share) do if r.id == id then return r end end
end

local function clean(s, key) return (tostring(s or ""):gsub("|", "")):sub(1, ns.Data.settings[key].max) end

local function encode(row)
  local parts = { row.code }
  for _, f in ipairs(row.fields) do
    if f == "ver" then parts[#parts + 1] = PROTO
    elseif f == "name" then parts[#parts + 1] = clean(ns.ProfileName(), "name")
    else parts[#parts + 1] = clean(MirrorPortraitsDB[f], f) end
  end
  return table.concat(parts, "|")
end

local function send(id, target)
  local row = rowById(id)
  local key = id .. (target or "")
  local now = GetTime()
  if last[key] and now - last[key] < row.throttle then return end
  last[key] = now
  local msg = encode(row)
  for _, ch in ipairs(row.channels) do
    if ch == "WHISPER" then
      if target then C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", target) end
    elseif ch == "GUILD" then
      if IsInGuild() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD") end
    elseif ch == "RAID" then
      if IsInRaid() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "RAID") end
    elseif ch == "PARTY" then
      if IsInGroup() and not IsInRaid() then C_ChatInfo.SendAddonMessage(PREFIX, msg, "PARTY") end
    end
  end
end
ns.Send = send

-- WoW Forever names are "First Last"; senders arrive in the same form GetUnitName(unit, true) returns.
local function myName() return GetUnitName("player", true) end
local function isMe(who) return who == myName() or who == UnitName("player") end

local function onMessage(_, prefix, text, channel, sender)
  if prefix ~= PREFIX then return end
  local code, ver, name, title = strsplit("|", text)
  local who = Ambiguate(sender, "none")
  if isMe(who) then
    if code == "H" and ns.onSelfEcho then ns.onSelfEcho(name, title) end
    return
  end
  if code == "H" and ver and name and name ~= "" then
    ns.known[who] = { name = clean(name, "name"), title = clean(title, "title"), at = time() }
    if GameTooltip:IsShown() and UnitExists("mouseover") and GetUnitName("mouseover", true) == who then
      local line = ns.TooltipLine("mouseover"); if line then GameTooltip:AddLine(line) GameTooltip:Show() end
    end
  elseif code == "Q" then
    send("reply", sender)
  end
end

-- The tooltip line: you, or anyone whose profile we've heard.
local function profileFor(unit)
  if not (unit and UnitIsPlayer(unit)) then return end
  if UnitIsUnit(unit, "player") then return ns.ProfileName(), MirrorPortraitsDB.title end
  local k = ns.known[GetUnitName(unit, true) or ""]
  if k then return k.name, k.title end
end

function ns.TooltipLine(unit)
  local name, title = profileFor(unit)
  if not name then return end
  local line = ("|c%sMirror:|r %s"):format(ns.COLOR, name)
  if title and title ~= "" then line = line .. ("  |cffbbbbbb%s|r"):format(title) end
  return line
end

local function addLine(tt)
  if tt ~= GameTooltip then return end
  local _, unit = tt:GetUnit()
  local line = ns.TooltipLine(unit)
  if not line then return end
  tt:AddLine(line)
  tt:Show()
end

function ns.StartShare()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, addLine)
  else
    GameTooltip:HookScript("OnTooltipSetUnit", addLine)
  end
  ns.tooltipHooked = true
  C_Timer.After(5, function() send("hello") end)
end

ns.Listen("CHAT_MSG_ADDON", onMessage)
ns.Listen("GROUP_ROSTER_UPDATE", function() send("hello") end)
ns.Listen("UPDATE_MOUSEOVER_UNIT", function()
  local u = "mouseover"
  if not (UnitIsPlayer(u) and not UnitIsUnit(u, "player")) then return end
  if UnitFactionGroup(u) ~= UnitFactionGroup("player") then return end
  local who = GetUnitName(u, true)
  if who and not ns.known[who] then send("query", who) end
end)
table.insert(ns.onChange, function(key)
  if key == "name" or key == "title" then last.hello = nil send("hello") end
end)

-- Test hook: send a hello to yourself (a whisper, and through your guild when you have one, which echoes back to
-- the sender) and call back when one arrives. Returns what each send answered.
function ns.SelfEcho(cb)
  ns.onSelfEcho = function(name, title) ns.onSelfEcho = nil cb(name, title) end
  local msg, results = encode(rowById("reply")), {}
  results[1] = "whisper " .. myName() .. "=" .. tostring(C_ChatInfo.SendAddonMessage(PREFIX, msg, "WHISPER", myName()))
  if IsInGuild() then results[#results + 1] = "guild=" .. tostring(C_ChatInfo.SendAddonMessage(PREFIX, msg, "GUILD")) end
  return table.concat(results, ", ")
end
