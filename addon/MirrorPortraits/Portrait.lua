-- Your picture over WoW's own portraits (sheets/surfaces.json), and the refresh that brings in a new one.
local _, ns = ...
ns.overlays = {}
ns.pictureTextures = {}

local function resolve(path)
  local t = _G
  for part in path:gmatch("[^%.]+") do
    if type(t) ~= "table" then return end
    t = t[part]
  end
  return t
end

local function isTexture(o)
  return type(o) == "table" and o.GetObjectType and o:GetObjectType() == "Texture"
end

-- Every texture that shows Portrait.tga registers here so a new picture reaches all of them.
function ns.UsePicture(tex)
  ns.pictureTextures[#ns.pictureTextures + 1] = tex
  tex:SetTexture(ns.Path("portrait"))
end

function ns.RefreshPicture()
  local path = ns.Path("portrait")
  for _, tex in ipairs(ns.pictureTextures) do
    tex:SetTexture(nil)
    tex:SetTexture(path)
  end
end

function ns.UpdatePortraits()
  local l, r, t, b = ns.FaceCoords()
  local selfTarget = UnitExists("target") and UnitIsUnit("target", "player")
  for _, o in ipairs(ns.overlays) do
    o.tex:SetTexCoord(l, r, t, b)
    local want = MirrorPortraitsDB.portrait and (o.row.when == "always" or (o.row.when == "self-target" and selfTarget))
    o.tex:SetShown(want and true or false)
  end
end

function ns.BuildPortraits()
  for _, row in ipairs(ns.Data.surfaces) do
    local base
    for _, p in ipairs(row.paths) do
      local o = resolve(p)
      if isTexture(o) then base = o break end
    end
    if base then
      local host = base:GetParent()
      local tex = host:CreateTexture(nil, base:GetDrawLayer(), nil, row.sublevel)
      tex:SetAllPoints(base)
      local mask = host:CreateMaskTexture()
      mask:SetTexture(ns.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(base)
      tex:AddMaskTexture(mask)
      ns.UsePicture(tex)
      ns.overlays[#ns.overlays + 1] = { row = row, tex = tex, base = base }
    end
  end
  ns.UpdatePortraits()
  -- Re-read Portrait.tga now and then: MirrorLink rewrites it when a new picture lands in the folder.
  C_Timer.NewTicker(3, ns.RefreshPicture)
end

ns.Listen("PLAYER_TARGET_CHANGED", function() ns.UpdatePortraits() end)
ns.Listen("UNIT_PORTRAIT_UPDATE", function() ns.UpdatePortraits() end)
table.insert(ns.onChange, function(key)
  if key == "portrait" or key == "faceX" or key == "faceY" or key == "faceS" then ns.UpdatePortraits() end
end)
