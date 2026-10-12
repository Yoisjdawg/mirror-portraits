-- The profile (opens only with /mp): your picture, your name and title, face framing, and /mp (sheets/commands.json).
local _, ns = ...
local PHOTO = 200
local PX = PHOTO -- pixels per texture unit (the photo shows the whole square picture)

local function label(parent, font, text, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY", font)
  fs:SetText(text or "")
  return fs
end

local function checkbox(parent, text, key)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  local t = label(cb, "GameFontHighlightSmall", text)
  t:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  cb:SetScript("OnClick", function(self) ns.Set(key, self:GetChecked() and true or false) end)
  cb.key = key
  return cb
end

local function textBox(parent, width, key, placeholder)
  local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  edit:SetSize(width, 22)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(ns.Data.settings[key].max)
  local hint = label(edit, "GameFontDisableSmall", placeholder)
  hint:SetPoint("LEFT", 2, 0)
  edit:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
  edit:SetScript("OnEnterPressed", function(self) ns.Set(key, self:GetText()) self:ClearFocus() end)
  edit:SetScript("OnEditFocusLost", function(self) if self:GetText() ~= MirrorPortraitsDB[key] then ns.Set(key, self:GetText()) end end)
  edit:SetScript("OnEscapePressed", function(self) self:SetText(MirrorPortraitsDB[key]) self:ClearFocus() end)
  edit.key = key
  return edit
end

function ns.BuildProfile()
  local f = CreateFrame("Frame", "MirrorPortraitsProfile", UIParent)
  ns.profile = f
  f:SetSize(PHOTO + 40, 580)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()
  table.insert(UISpecialFrames, "MirrorPortraitsProfile")

  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.04, 0.09, 1)
  for _, edge in ipairs({ "TOP", "BOTTOM" }) do
    local e = f:CreateTexture(nil, "BORDER")
    e:SetPoint(edge .. "LEFT"); e:SetPoint(edge .. "RIGHT"); e:SetHeight(2)
    e:SetColorTexture(0.62, 0.83, 1, 0.9)
  end

  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", 2, -2); header:SetPoint("TOPRIGHT", -2, -2); header:SetHeight(30)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() f:StartMoving() end)
  header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  local title = label(header, "GameFontNormal", "Mirror Portraits")
  title:SetPoint("LEFT", 10, 0)
  local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
  close:SetPoint("RIGHT", 4, 0)

  local name = label(f, "GameFontNormalLarge")
  name:SetPoint("TOP", header, "BOTTOM", 0, -4)
  f.nameText = name
  local sub = label(f, "GameFontHighlightSmall")
  sub:SetPoint("TOP", name, "BOTTOM", 0, -2)
  f.titleText = sub

  -- Photo: the whole picture.
  local photo = CreateFrame("Button", nil, f)
  photo:SetSize(PHOTO, PHOTO)
  photo:SetPoint("TOP", sub, "BOTTOM", 0, -8)
  local well = photo:CreateTexture(nil, "BACKGROUND")
  well:SetAllPoints()
  well:SetColorTexture(0.08, 0.1, 0.18, 1)
  -- Under the picture: shows through only while there is none yet (Portrait.tga is transparent until then).
  local hint = label(photo, "GameFontHighlightSmall", "", "BORDER")
  hint:SetPoint("LEFT", 10, 0); hint:SetPoint("RIGHT", -10, 0)
  f.hint = hint
  local img = photo:CreateTexture(nil, "ARTWORK")
  img:SetAllPoints()
  local crop = ns.Data.crops.photo
  img:SetTexCoord(crop.x, crop.x + crop.w, crop.y, crop.y + crop.h)
  ns.UsePicture(img)
  f.photo = img

  -- Face framing: drag the square to move it, mouse wheel to resize.
  local box = CreateFrame("Frame", nil, photo)
  box:Hide()
  for _, s4 in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local l = box:CreateTexture(nil, "OVERLAY")
    l:SetColorTexture(0.62, 0.83, 1, 1)
    l:SetPoint(s4[1]); l:SetPoint(s4[2])
    if s4[3] then l:SetHeight(2) else l:SetWidth(2) end
  end
  local function placeBox()
    local x, y, s = MirrorPortraitsDB.faceX, MirrorPortraitsDB.faceY, MirrorPortraitsDB.faceS
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", photo, "TOPLEFT", (x - crop.x) * PX, -(y - crop.y) * PX)
    box:SetSize(s * PX, s * PX)
  end
  local function setFace(x, y, s)
    s = math.max(0.06, math.min(1, s))
    x = math.max(0, math.min(1 - s, x))
    y = math.max(0, math.min(1 - s, y))
    MirrorPortraitsDB.faceX, MirrorPortraitsDB.faceY = x, y
    ns.Set("faceS", s)
    placeBox()
  end
  photo:EnableMouseWheel(true)
  photo:SetScript("OnMouseWheel", function(_, delta)
    if not box:IsShown() then return end
    local x, y, s = MirrorPortraitsDB.faceX, MirrorPortraitsDB.faceY, MirrorPortraitsDB.faceS
    local s2 = s - delta * 0.03
    setFace(x + (s - s2) / 2, y + (s - s2) / 2, s2)
  end)
  photo:SetScript("OnMouseDown", function(self)
    if not box:IsShown() then return end
    local cx, cy = GetCursorPosition()
    self.drag = { cx, cy, MirrorPortraitsDB.faceX, MirrorPortraitsDB.faceY, self:GetEffectiveScale() }
  end)
  photo:SetScript("OnMouseUp", function(self) self.drag = nil end)
  photo:SetScript("OnUpdate", function(self)
    local d = self.drag
    if not d then return end
    local cx, cy = GetCursorPosition()
    setFace(d[3] + (cx - d[1]) / d[5] / PX, d[4] - (cy - d[2]) / d[5] / PX, MirrorPortraitsDB.faceS)
  end)

  -- Face preview (exactly what your portraits show), framing and reload buttons.
  local face = f:CreateTexture(nil, "ARTWORK")
  face:SetSize(46, 46)
  face:SetPoint("TOPLEFT", photo, "BOTTOMLEFT", 0, -8)
  local fmask = f:CreateMaskTexture()
  fmask:SetTexture(ns.MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  fmask:SetAllPoints(face)
  face:AddMaskTexture(fmask)
  ns.UsePicture(face)
  f.face = face
  local frameBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  frameBtn:SetSize(PHOTO - 54, 22)
  frameBtn:SetPoint("TOPLEFT", face, "TOPRIGHT", 8, 0)
  frameBtn:SetText("Frame my portrait")
  frameBtn:SetScript("OnClick", function(self)
    box:SetShown(not box:IsShown())
    self:SetText(box:IsShown() and "Done" or "Frame my portrait")
    placeBox()
  end)
  local refresh = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refresh:SetSize(PHOTO - 54, 22)
  refresh:SetPoint("TOPLEFT", frameBtn, "BOTTOMLEFT", 0, -2)
  refresh:SetText("Load newest picture")
  refresh:SetScript("OnClick", function() ns.RefreshPicture() end)

  local nameBox = textBox(f, PHOTO - 6, "name", "Name (Enter to save)")
  nameBox:SetPoint("TOPLEFT", face, "BOTTOMLEFT", 6, -10)
  local titleBox = textBox(f, PHOTO - 6, "title", "Title, e.g. the Good Boy")
  titleBox:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -6)
  f.boxes = { nameBox, titleBox }

  local cbPortrait = checkbox(f, "My picture as my portrait", "portrait")
  cbPortrait:SetPoint("TOPLEFT", titleBox, "BOTTOMLEFT", -10, -4)
  f.checks = { cbPortrait }

  local folder = label(f, "GameFontDisableSmall")
  folder:SetPoint("TOPLEFT", cbPortrait, "BOTTOMLEFT", 4, -4)
  folder:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  folder:SetJustifyH("LEFT")
  f.folderText = folder

  -- Picture folder: WoW add-ons can't open Windows folders, so the button shows the path selected for Ctrl+C
  -- (paste it in File Explorer's address bar) and points to the Mirror Portraits icon by the clock, which opens it.
  local folderBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  folderBtn:SetSize(PHOTO - 6, 22)
  folderBtn:SetPoint("TOPLEFT", folder, "BOTTOMLEFT", 2, -6)
  folderBtn:SetText("Picture folder")
  local pathBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  pathBox:SetSize(PHOTO - 12, 22)
  pathBox:SetPoint("TOPLEFT", folderBtn, "BOTTOMLEFT", 6, -4)
  pathBox:SetAutoFocus(false)
  pathBox:Hide()
  local pathHint = label(f, "GameFontHighlightSmall", ns.Manual()
    and "That's inside your World of Warcraft folder. Save your Portrait.tga there, then restart WoW."
    or "Ctrl+C, then paste in File Explorer's address bar. Or click the Mirror Portraits icon by the Windows clock.")
  pathHint:SetPoint("TOPLEFT", pathBox, "BOTTOMLEFT", -6, -4)
  pathHint:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  pathHint:SetJustifyH("LEFT")
  pathHint:Hide()
  local function selectPath() pathBox:SetText(ns.FolderHint()) pathBox:HighlightText() end
  pathBox:SetScript("OnTextChanged", function(self, user) if user then selectPath() end end)
  pathBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() pathHint:Hide() end)
  pathBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  folderBtn:SetScript("OnClick", function()
    local show = not pathBox:IsShown()
    pathBox:SetShown(show)
    pathHint:SetShown(show)
    if show then pathBox:SetFocus() selectPath() else pathBox:ClearFocus() end
  end)
  f.folderButton = folderBtn

  function ns.UpdateProfile()
    name:SetText(("|c%s%s|r"):format(ns.COLOR, ns.ProfileName()))
    local t = MirrorPortraitsDB.title
    sub:SetText(t ~= "" and t or " ")
    for _, b in ipairs(f.boxes) do if not b:HasFocus() then b:SetText(MirrorPortraitsDB[b.key]) end end
    local l, r, tp, bt = ns.FaceCoords()
    face:SetTexCoord(l, r, tp, bt)
    for _, cb in ipairs(f.checks) do cb:SetChecked(MirrorPortraitsDB[cb.key]) end
    hint:SetText("Put " .. ns.PictureHint() .. " in\n\n|cffffffff" .. ns.FolderHint() .. "|r\n\nIt shows here and on your portrait.")
    folder:SetText((ns.Manual() and "Your picture: Portrait.tga in " or "New picture: drop it in ") .. ns.FolderHint())
  end
  table.insert(ns.onChange, function() ns.UpdateProfile() end)
  f:SetScript("OnShow", ns.UpdateProfile)
  ns.UpdateProfile()
end

function ns.ToggleProfile()
  local f = ns.profile
  if f:IsShown() then f:Hide() return end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
  f:Show()
end

local function onOff(arg, key)
  if arg == "on" or arg == "off" then ns.Set(key, arg == "on") end
  ns.Print(("%s is %s"):format(key, MirrorPortraitsDB[key] and "on" or "off"))
end

SLASH_MIRRORPORTRAITS1 = "/mp"
SLASH_MIRRORPORTRAITS2 = "/mirror"
SlashCmdList.MIRRORPORTRAITS = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.ToggleProfile()
  elseif cmd == "name" then
    ns.Set("name", rest)
    ns.Print("your name is " .. ns.ProfileName())
  elseif cmd == "title" then
    ns.Set("title", rest)
    ns.Print("your title is " .. (MirrorPortraitsDB.title ~= "" and MirrorPortraitsDB.title or "(none)"))
  elseif cmd == "portrait" then
    onOff(rest:lower(), "portrait")
  elseif cmd == "folder" then
    if ns.Manual() then
      ns.Print("save " .. ns.PictureHint() .. " in |cffffffff" .. ns.FolderHint() .. "|r.")
    else
      ns.Print("put your picture in |cffffffff" .. ns.FolderHint() .. "|r (PNG, JPG, BMP or GIF; the one you added last is used). The Mirror Portraits icon by the Windows clock opens it.")
    end
    if not ns.profile:IsShown() then ns.ToggleProfile() end
    ns.profile.folderButton:Click()
  elseif cmd == "refresh" then
    ns.RefreshPicture()
  elseif cmd == "reset" then
    local c = ns.Data.crops.face
    MirrorPortraitsDB.faceX, MirrorPortraitsDB.faceY = c.x, c.y
    ns.Set("faceS", c.w)
  else
    for _, row in ipairs(ns.Data.commands) do print(("  |cffffffff%s|r  %s"):format(row.usage, row.help)) end
  end
end
