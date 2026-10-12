-- Saved settings, media paths, events. MirrorLink (the Melty version) writes Generated\Info.lua (which picture it used)
-- before WoW starts. Without it (the add-on-only download), the player saves Portrait.tga in the add-on folder.
local ADDON, ns = ...
ns.VERSION = "1.0.4"
ns.ROOT = "Interface\\AddOns\\MirrorPortraits\\"
ns.MEDIA = ns.ROOT .. "Generated\\"
ns.MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.COLOR = "ff9fd4ff"
ns.TAG = "|cff9fd4ffMirror Portraits|r"

function ns.Print(msg) print(ns.TAG .. ": " .. msg) end

function ns.Info() return MirrorPortraits_Info or {} end

-- No MirrorLink: the add-on-only download, where the player supplies the TGA by hand.
function ns.Manual() return not ns.Info().link end

function ns.Path(mediaId)
  local m = ns.Data.media[mediaId]
  if ns.Manual() then return ns.ROOT .. (m.manual:gsub("%.tga$", "")) end
  return ns.MEDIA .. (m.file:gsub("%.tga$", ""))
end

ns.onChange = {}
function ns.Set(key, value)
  local row = ns.Data.settings[key]
  if row and row.type == "string" then value = tostring(value or ""):gsub("[|\r\n]", ""):sub(1, row.max) end
  MirrorPortraitsDB[key] = value
  for _, fn in ipairs(ns.onChange) do fn(key, value) end
end

function ns.ProfileName()
  local n = MirrorPortraitsDB.name
  if n and n ~= "" then return n end
  return UnitName("player")
end

function ns.FaceCoords()
  local x, y, s = MirrorPortraitsDB.faceX, MirrorPortraitsDB.faceY, MirrorPortraitsDB.faceS
  return x, x + s, y, y + s
end

function ns.FolderHint()
  if ns.Manual() then return "World of Warcraft\\_classic_beta_\\Interface\\AddOns\\MirrorPortraits" end
  local f = ns.Info().folder
  return f and f ~= "" and f or "Pictures\\Mirror Portraits"
end

-- What to put in the folder, for the hints.
function ns.PictureHint()
  if ns.Manual() then
    return "a 512x512 picture saved as |cffffffffPortrait.tga|r (then restart WoW). The Melty version takes any photo by itself."
  end
  return "any picture (you, your dog, a screenshot from another game)"
end

local function initDB()
  MirrorPortraitsDB = MirrorPortraitsDB or {}
  for _, row in ipairs(ns.Data.settings) do
    local v = MirrorPortraitsDB[row.key]
    local ok = (row.type == "string" and type(v) == "string")
      or (row.type == "number" and type(v) == "number")
      or (row.type == "bool" and type(v) == "boolean")
    if not ok then MirrorPortraitsDB[row.key] = row.default end
  end
end

local ev = CreateFrame("Frame")
ns.listeners = {}
function ns.Listen(event, fn)
  if not ns.listeners[event] then
    ns.listeners[event] = {}
    pcall(ev.RegisterEvent, ev, event)
  end
  table.insert(ns.listeners[event], fn)
end
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, ...)
  local arg1 = ...
  if event == "ADDON_LOADED" and arg1 == ADDON then
    initDB()
  elseif event == "PLAYER_LOGIN" then
    ns.BuildPortraits()
    ns.BuildProfile()
    ns.StartShare()
    local info = ns.Info()
    if not info.link then
      ns.Print("save " .. ns.PictureHint() .. " in |cffffffff" .. ns.FolderHint() .. "|r. Type /mp for your profile.")
    elseif not info.picture then
      ns.Print("put a picture (you, your dog, a screenshot) in |cffffffff" .. ns.FolderHint() .. "|r. Type /mp for your profile.")
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if ns.RunTests then ns.RunTests() end
  end
  local list = ns.listeners[event]
  if list then for _, fn in ipairs(list) do fn(event, ...) end end
end)
