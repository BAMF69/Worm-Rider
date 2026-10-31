-- Headless play-through of the whole tame-and-ride loop against the mock.
local M = dofile(TESTDIR .. "/mock_ue4ss.lua")
package.path = MODDIR .. "/?.lua;" .. package.path
dofile(MODDIR .. "/main.lua")

local results, fails = {}, 0
local function check(name, cond, extra)
  results[#results + 1] = (cond and "PASS " or "FAIL ") .. name .. (extra and ("  (" .. tostring(extra) .. ")") or "")
  if not cond then fails = fails + 1 end
end
local GLYPH_KEY = { UP = "UP_ARROW", DOWN = "DOWN_ARROW", LEFT = "LEFT_ARROW", RIGHT = "RIGHT_ARROW" }
local function currentArrow() return M.hudText:match(">(%u+)[/<]") end
local ALT = { UP = "W", DOWN = "S", LEFT = "A", RIGHT = "D" }
local function stage() local l = M.lastLog("stage .- %-> ([%w_]+)") return l and l:match("%-> ([%w_]+)") or "idle" end

M.wormBackup = {}
for k, v in pairs(M.worm) do if type(v) == "function" then M.wormBackup[k] = v end end
-- 1. load
M.step(0.5)
check("loaded log", M.lastLog("loaded") ~= nil)
check("HUD in viewport", M.inViewport == true)
check("loaded message", M.hudText:find("Worm Rider loaded") ~= nil, M.hudText)

-- 2. radar, ready the hook, auto-leap when the worm arrives
local wormStart = { X = M.worm.loc.X, Y = M.worm.loc.Y, Z = M.worm.loc.Z }
M.worm.loc = { X = 30000, Y = 0, Z = 1000 }
M.step(3.0)
check("radar shows far worm", M.hudText:find("300 m") ~= nil and M.hudText:find("ready your hook") ~= nil, M.hudText)
M.press("G") M.step(0.2)
check("hook ready", M.hudText:find("HOOK READY") ~= nil, M.hudText)
check("still idle while far", M.lastLog("stage %w+ %->") == nil)
M.worm.loc = wormStart
M.step(0.2)

-- the worm has an attack queued (this is what crashed the real game)
M.attackAt = M.t + 1.0
-- 3. auto leap -> stunned
check("stage stunned", stage() == "stunned", stage())
check("AI paused", M.aiOn == false)
check("controller never detached", M.detached == nil and M.worm.Controller == M.ai)
check("worm stunned dilation", math.abs(M.worm.CustomTimeDilation - 0.05) < 1e-6, M.worm.CustomTimeDilation)
check("rider collision off", M.pawn.collision == false)
check("rider movement none", M.move.mode == 0)

-- 4. stun ends -> wild ride
for _ = 1, 40 do if M.playing == M.animNamed("SardPull_01_Out_Air") then break end M.step(0.05) end
check("landing animation", M.playing == M.animNamed("SardPull_01_Out_Air"), M.playing and M.playing:GetFullName())
check("wire gone after landing", M.wire.__valid == false)
M.step(0.8)
check("cross-legged riding pose after landing", M.playing == M.animNamed("Sit_Ground_01_In_01"), M.playing and M.playing:GetFullName())
check("riding pose held on its last frame", M.looping == false and M.playRate == 0 and math.abs(M.animPos - 2.37) < 0.01, string.format("loop=%s rate=%s pos=%s", tostring(M.looping), tostring(M.playRate), tostring(M.animPos)))
check("stage wild_ride", stage() == "wild_ride", stage())
check("queued worm attack fired with controller attached (no crash)", M.attackFiredWithController == true, M.attackFiredWithController)
check("AI steering held every tick", (M.stopMoves or 0) > 50, M.stopMoves)
check("arrow prompt shown", currentArrow() ~= nil, M.hudText)
local w0 = { X = M.worm.loc.X, Y = M.worm.loc.Y }
M.step(1.0)
local moved = math.sqrt((M.worm.loc.X - w0.X) ^ 2 + (M.worm.loc.Y - w0.Y) ^ 2)
check("wild worm surfs", moved > 800, moved)
local depth0 = M.worm.loc.Z - M.ground(M.worm.loc.X, M.worm.loc.Y)
check("worm keeps its natural depth", math.abs(depth0 - (-3000)) < 400, depth0)
check("rider sits at least 19 m above the neck bone", M.pawn.loc.Z >= M.boneWorld("neck_03").Z + 1900 - 160, M.pawn.loc.Z - M.boneWorld("neck_03").Z)
M.step(2.6)
check("mount logged heights", M.lastLog("mount: pawnZ") ~= nil)

-- 5. a wrong arrow resets the sequence but does not throw
local a = currentArrow()
local wrong = (a == "UP") and "DOWN_ARROW" or "UP_ARROW"
M.press(wrong) M.step(0.05)
check("wrong arrow keeps you on", stage() == "wild_ride")

check("prompt shows WASD letter", M.hudText:find(">%u+/[WASD]<") ~= nil, M.hudText)
-- 6. land 8 sequences -> tamed (odd sequences with WASD, even with arrows)
for i = 1, 8 do
  for _ = 1, 4 do
    local g = currentArrow()
    if not g then break end
    M.press(i % 2 == 1 and ALT[g] or GLYPH_KEY[g]) M.step(0.05)
  end
  M.step(0.2)
end
check("tamed", stage() == "tamed_ride", stage())
check("tamed message", M.hudText:find("IS YOURS") ~= nil, M.hudText)
check("cross-legged pose while tamed", M.playing == M.animNamed("Sit_Ground_01_In_01"), M.playing and M.playing:GetFullName())

-- 7. steer: hold W and D
M.step(1.0)
check("seat on neck_03 facing head_01", M.lastLog("ride bone: neck_03, facing head_01") ~= nil, M.lastLog("ride bone:"))
check("double is traceable but ignores the world", M.double.SkeletalMeshComponent.coll == 1 and M.double.SkeletalMeshComponent.resp == 0)
local maxOff, maxSink, maxYawErr = 0, 0, 0
for i = 1, 30 do
  M.step(0.05)
  local b = M.boneWorld("neck_03")
  maxOff = math.max(maxOff, math.sqrt((M.pawn.loc.X - b.X) ^ 2 + (M.pawn.loc.Y - b.Y) ^ 2))
  maxSink = math.max(maxSink, (M.bodyTopZ + 120) - M.pawn.loc.Z)
  local h = M.boneWorld("head_01")
  local want = math.deg(math.atan(h.Y - b.Y, h.X - b.X))
  maxYawErr = math.max(maxYawErr, math.abs(((M.pawn.rot.Yaw - want + 180) % 360) - 180))
end
check("rider stays over the seat bone as the body sways", maxOff < 150, maxOff)
check("rider never sinks into the body", maxSink < 160, maxSink)
check("body trace works (no out-param error)", M.lastLog("body trace failed") == nil and M.lastLog("body surface traced") ~= nil, M.lastLog("body"))
check("rider faces along the neck toward the head", maxYawErr < 2, maxYawErr)
local z0 = M.pawn.loc.Z - M.boneWorld("neck_03").Z
M.press("END") M.press("END") M.step(0.3)
local z1 = M.pawn.loc.Z - M.boneWorld("neck_03").Z
check("End lowers you 2 m on the worm", math.abs((z0 - z1) - 200) < 60, z0 - z1)
check("seat height shown", M.hudText:find("Seat height %-2 m") ~= nil, M.hudText)
M.press("HOME") M.press("HOME") M.step(0.3)
M.step(2.0)
M.held.W, M.held.D = true, true
local yaw0 = M.worm.rot.Yaw
M.step(2.0)
check("same pose at speed (no switching)", M.playing == M.animNamed("Sit_Ground_01_In_01"), M.playing and M.playing:GetFullName())
check("throttle speeds up", M.hudText:match("(%d+) km/h") and tonumber(M.hudText:match("(%d+) km/h")) > 80, M.hudText:match("(%d+) km/h"))
check("D turns right", M.worm.rot.Yaw > yaw0 + 60, M.worm.rot.Yaw - yaw0)
check("rider turns with the worm's head, not ahead of it", math.abs(((M.pawn.rot.Yaw - M.worm.rot.Yaw + 180) % 360) - 180) > 1, M.pawn.rot.Yaw - M.worm.rot.Yaw)
M.held.D = nil

check("controls listed while riding", M.hudText:find("%[W/S%] speed") ~= nil, M.hudText)
M.press("F6") M.step(0.1)
check("F6 hides the controls", M.hudText:find("%[W/S%] speed") == nil and M.hudText:find("%[F6%] controls") ~= nil, M.hudText)
M.press("F6") M.step(0.1)
check("F6 shows them again", M.hudText:find("%[W/S%] speed") ~= nil, M.hudText)
-- 8. breach arc
local zBefore = M.wormTop()
M.press("SPACE") M.step(0.8)
check("breach never moves the worm vertically", math.abs(M.wormTop() - zBefore) < 50, M.wormTop() - zBefore)
check("rider leaps on breach", M.riderUp() > 1500, M.riderUp())
M.step(1.0)
check("breach lands back on the body", math.abs(M.pawn.loc.Z - (M.bodyTopZ + 120)) < 200, M.pawn.loc.Z - M.bodyTopZ)

-- 9. dive + tricks -> boost
M.held.SHIFT, M.held.LeftShift = true, true
M.step(1.0)
check("dive never moves the worm vertically", math.abs(M.wormTop() - zBefore) < 50, M.wormTop() - zBefore)
check("rider sand-surfs", math.abs(M.pawn.loc.Z - (M.ground(M.pawn.loc.X, M.pawn.loc.Y) + 120)) < 200, M.pawn.loc.Z)
for i = 1, 3 do
  for _ = 1, 4 do local g = currentArrow() if g then M.press(GLYPH_KEY[g]) M.step(0.05) end end
end
M.step(0.1)
check("boost active", M.hudText:find("BOOST!") ~= nil or M.hudText:find("BOOST %d") ~= nil, M.hudText)
M.held.LeftShift, M.held.SHIFT, M.held.W = nil, nil, nil

-- 9b. experimental: worm double and body height
check("mount found the body directly", M.lastLog("mount: worm body .*SandwormSkeletalMesh") ~= nil, M.lastLog("mount: worm body"))
check("never crouches", M.crouched == nil)
M.press("F7") M.step(0.1)
check("F7 offers loaded human riding poses (best first)", M.playing == M.anims[4], M.playing and M.playing:GetFullName())
check("grenade/crouch/dropship not offered", M.lastLog("pose candidate.*Grenade") == nil and M.lastLog("pose candidate.*Crouch") == nil and M.lastLog("pose candidate.*DropShip") == nil)
M.press("F7") M.step(0.1)
check("F7 next pose", M.playing == M.anims[2], M.playing and M.playing:GetFullName())
M.press("F7") M.step(0.1)
check("F7 past last = back to the cross-legged pose", M.playing == M.animNamed("Sit_Ground_01_In_01"), M.hudText)
local autoD = M.double
M.press("F8") M.step(0.1)
check("F8 turns the automatic double off", autoD and autoD.__valid == false)
M.press("F8") M.step(0.1)
local D = M.double
check("double spawned", D ~= nil and D.__valid and D.finished, M.lastLog("double"))
check("double uses the worm's own model", D and D.SkeletalMeshComponent.mesh == M.wormMesh)
check("double copies the worm animation", D and D.SkeletalMeshComponent.leader == M.body)
M.step(0.1)
check("double faces the same way as the real body", D and D.SkeletalMeshComponent.worldRot and math.abs(D.SkeletalMeshComponent.worldRot.Yaw - (M.worm.rot.Yaw - 90)) < 0.01)

check("double matches body size", D and D.SkeletalMeshComponent.scale and D.SkeletalMeshComponent.scale.X == 2)
M.step(0.1)
local sandZ = M.ground(M.worm.loc.X, M.worm.loc.Y)
check("double sits 2 m under the sand", D and math.abs(D.loc.Z - (sandZ - 200)) < 60, D and (D.loc.Z - sandZ))
local wz = M.worm.loc.Z
M.press("PAGE_UP") M.step(0.1)
check("PgUp raises the double", D and math.abs(D.loc.Z - (M.ground(M.worm.loc.X, M.worm.loc.Y) + 0)) < 60, D and (D.loc.Z - M.ground(M.worm.loc.X, M.worm.loc.Y)))
check("PgUp leaves the real worm alone", math.abs(M.worm.loc.Z - wz) < 400 and M.body.RelativeLocation.Z == 2500)
M.step(1.0)
check("double follows while riding", D and math.abs(D.loc.X - M.worm.loc.X) < 5)
M.press("F8") M.step(0.1)
check("F8 removes the double", D and D.__valid == false)
M.press("PAGE_UP") M.step(0.1)
check("PgUp without double moves the real body part", M.body.RelativeLocation.Z == 2700, M.body.RelativeLocation.Z)
M.press("F8") M.step(0.1)
local D2 = M.double

-- 10. dismount, walk away, call, remount
M.press("G") M.step(0.1)
check("dismounted", stage() == "tamed_wait", stage())
check("dismount restores normal animation", M.playing == nil and M.animMode == 0 and M.playRate == 1, string.format("mode=%s rate=%s", tostring(M.animMode), tostring(M.playRate)))
check("HUD never takes clicks or focus", M.textVis == 3)
local wx, wy = M.worm.loc.X, M.worm.loc.Y
M.step(1.0)
check("waiting worm stays put", math.abs(M.worm.loc.X - wx) + math.abs(M.worm.loc.Y - wy) < 50)
check("rider collision back", M.pawn.collision == true)
check("rider can walk", M.move.mode == 1)
M.pawn.loc = { X = M.worm.loc.X + 20000, Y = M.worm.loc.Y, Z = M.ground(M.worm.loc.X + 20000, 0) + 100 }
M.step(0.2)
M.press("G") M.step(0.1)
check("too far to remount", stage() == "tamed_wait")
M.press("H")
M.step(8.0)
local d = math.sqrt((M.worm.loc.X - M.pawn.loc.X) ^ 2 + (M.worm.loc.Y - M.pawn.loc.Y) ^ 2)
check("called worm arrives", d <= 1600, d)
M.press("G") M.step(0.1)
check("remounted", stage() == "tamed_ride", stage())

-- 11. the game deletes the worm mid-ride (what crashed the game at 22:18)
check("EndPlay hook registered", M.endPlayHook ~= nil)
local oldWorm = M.worm
M.destroyActor(M.worm)
M.worm = M.obj("BP_Crea_SandwormArrakis_C", "placeholder", {}) M.worm.__valid = false M.wormHidden = true
M.step(0.2)
M.worm = oldWorm M.wormHidden = false
-- restore a usable worm object for the rest of the scenario
for k, v in pairs(M.wormBackup) do M.worm[k] = v end
M.worm.IsValid = function(self) return self.__valid end
check("lost worm resets", stage() == "idle", stage())
check("freed worm never touched", M.lastLog("touched freed object") == nil and M.lastLog("IsValid on freed") == nil, M.lastLog("freed"))
check("double removed with lost worm", D2 and D2.__valid == false)
M.body.RelativeLocation.Z = 2500 -- the real body went away with the worm
check("lost message", M.hudText:find("returned to the deep") ~= nil, M.hudText)
check("rider freed", M.pawn.collision == true and M.move.mode == 3)

-- 12. new worm, stall -> thrown
M.worm.__valid = true
M.worm.Controller = M.ai M.aiOn = true
M.worm.loc = { X = M.pawn.loc.X + 2000, Y = M.pawn.loc.Y, Z = 1000 }
M.step(3.0)
M.traceBroken = true
M.press("G") M.step(1.7)
check("second tame starts", stage() == "wild_ride", stage())
check("no sand trace: rider still above sand", M.riderUp() > 300, M.riderUp())
M.traceBroken = false
M.step(6.2)
check("stall throws you", stage() == "thrown", stage())
check("AI back on", M.aiOn == true)
check("flung upward", M.launched and M.launched.Z > 0)
M.press("G") M.step(0.1)
check("no leap during cooldown", stage() == "thrown")
M.step(8.5)
check("back to idle", stage() == "idle", stage())

-- 13. respawn safety: rider pawn replaced mid-ride
M.step(3.0) M.press("G") M.step(0.2)
local newPawn = M.obj("BP_Player_C", "BP_Player_C 2", {})
for k, v in pairs(M.pawn) do if type(v) == "function" then newPawn[k] = v end end
newPawn.loc, newPawn.rot, newPawn.CharacterMovement, newPawn.collision = { X = 0, Y = 0, Z = 1100 }, { Yaw = 0 }, M.move, true
M.pc.Pawn = newPawn
M.step(0.2)
check("respawn resets", stage() == "idle", stage())

local errors = 0
for _, l in ipairs(M.log) do if l:find("error") then errors = errors + 1 M.realPrint("LOG " .. l) end end
check("no runtime errors logged", errors == 0, errors)

for _, r in ipairs(results) do M.realPrint(r) end
M.realPrint(string.format("%d checks, %d failed", #results, fails))
return fails
