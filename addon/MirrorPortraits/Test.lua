-- Melty test mode (sheets/checks.json). MirrorLink writes Generated\Test.lua while Melty is testing; the add-on
-- runs each check and stores the lines in MirrorPortraitsDB.test; a typed /reload writes them to disk, where
-- MirrorLink reads them and hands them to Melty.
local _, ns = ...

local function near(a, b) return math.abs((a or -1) - (b or -2)) < 0.002 end

-- The tooltip line is checked through the same function the tooltip hook uses: setting the tooltip from add-on
-- code here would read protected values (health) from tainted code.
local function tooltipHasLine()
  local line = ns.tooltipHooked and ns.TooltipLine("player")
  return line and line:find("Mirror:", 1, true) ~= nil
end

local checks = {}
checks["picture-loaded"] = function(done)
  local info = ns.Info()
  if not info.link then return done(false, "MirrorLink did not run") end
  if not info.picture then return done(false, "no picture found in " .. ns.FolderHint()) end
  local p = ns.profile
  if not (p and p.photo:GetTexture()) then return done(false, "Portrait.tga did not load") end
  done(true)
end
checks["portrait-overlay"] = function(done)
  local o
  for _, x in ipairs(ns.overlays) do if x.row.id == "player-portrait" then o = x end end
  if not o then return done(false, "player portrait not found") end
  if not o.tex:IsShown() then return done(false, "overlay hidden") end
  if o.tex:GetNumMaskTextures() < 1 then return done(false, "overlay not masked") end
  local l, t = o.tex:GetTexCoord()
  local fl, _, ft = ns.FaceCoords()
  if not (near(l, fl) and near(t, ft)) then return done(false, "overlay not using the face crop") end
  if not o.tex:GetTexture() then return done(false, "Portrait.tga not loaded") end
  done(true)
end
checks["profile-panel"] = function(done)
  -- Opening the character sheet from add-on code taints it (WoW Forever protects health values), so the
  -- test opens the profile the way /mp does.
  if ns.profile and not ns.profile:IsShown() then SlashCmdList.MIRRORPORTRAITS("") end
  C_Timer.After(1, function()
    local p = ns.profile
    if not p then return done(false, "profile not built") end
    if not p:IsShown() then return done(false, "profile did not open") end
    local c = ns.Data.crops.photo
    local l, t = p.photo:GetTexCoord()
    if not (near(l, c.x) and near(t, c.y)) then return done(false, "photo crop wrong") end
    if (p.nameText:GetText() or "") == "" or not p.titleText:GetText() then return done(false, "name/title empty") end
    done(true)
  end)
end
checks["tooltip-share"] = function(done)
  local finished = false
  local sent = ns.SelfEcho(function(name)
    if finished then return end
    finished = true
    if not name or name == "" then return done(false, "echo had no name") end
    if not tooltipHasLine() then return done(false, "tooltip has no Mirror line") end
    done(true)
  end)
  C_Timer.After(8, function()
    if finished then return end
    finished = true
    done(false, "hello to yourself never came back (" .. tostring(sent) .. ")")
  end)
end

function ns.RunTests()
  local T = MirrorPortraits_Test
  if type(T) ~= "table" or not T.testId then return end
  local rec = MirrorPortraitsDB.test
  if rec and rec.testId == T.testId and rec.run == T.run and rec.done then
    ns.Print(("test run %s reported."):format(tostring(T.run)))
    if ns.profile and not ns.profile:IsShown() then ns.ToggleProfile() end
    return
  end
  local lines, i = {}, 0
  local rows = ns.Data.checks
  local function nextCheck()
    i = i + 1
    local row = rows[i]
    if not row then
      MirrorPortraitsDB.test = { testId = T.testId, run = T.run, seed = T.seed, done = true, lines = lines, at = time() }
      -- WoW Forever blocks add-ons from reloading the UI by themselves; a /reload (typed) saves the results.
      ns.Print("test checks done: type |cffffffff/reload|r to save them for Melty.")
      return
    end
    checks[row.id](function(ok, why)
      lines[#lines + 1] = ok and ("pass " .. row.id) or ("fail " .. row.id .. ": " .. (why or "?"))
      ns.Print("test " .. lines[#lines])
      C_Timer.After(0.5, nextCheck)
    end)
  end
  C_Timer.After(6, nextCheck)
end
