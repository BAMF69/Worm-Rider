-- Minimal UE4SS + Unreal mock so main.lua can run headless.
local M = { t = 0, keybinds = {}, loops = {}, held = {}, hudText = "", log = {}, addr = 0 }
_G.__MOCK = M

local function obj(class, fullname, props)
  M.addr = M.addr + 1
  local o = props or {}
  o.__class, o.__addr, o.__valid = class, M.addr, true
  o.IsValid = function(self) return self.__valid end
  o.GetFullName = function(self) return fullname end
  o.GetAddress = function(self) return self.__addr end
  return o
end
M.obj = obj

local function actor(class, fullname, loc)
  local a = obj(class, fullname, {})
  a.loc = { X = loc.X, Y = loc.Y, Z = loc.Z }
  a.rot = { Pitch = 0, Yaw = 0, Roll = 0 }
  a.CustomTimeDilation = 1.0
  a.collision = true
  a.K2_GetActorLocation = function(self) return { X = self.loc.X, Y = self.loc.Y, Z = self.loc.Z } end
  a.K2_SetActorLocation = function(self, p, sweep, hit, tp) assert(type(hit) == "table") self.loc = { X = p.X, Y = p.Y, Z = p.Z } return true end
  a.K2_GetActorRotation = function(self) return { Pitch = 0, Yaw = self.rot.Yaw, Roll = 0 } end
  a.K2_SetActorRotation = function(self, r, tp) self.rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } return true end
  a.SetActorEnableCollision = function(self, b) self.collision = b end
  return a
end

function M.ground(x, y) return 1000 + 300 * math.sin(x / 20000) end

-- player
M.move = obj("CharacterMovementComponent", "CMC", { mode = 1 })
M.move.SetMovementMode = function(self, m, c) self.mode = m end
M.pawn = actor("BP_Player_C", "BP_Player_C /Game/Player", { X = 0, Y = 0, Z = 1100 })
M.pawn.CharacterMovement = M.move
M.pawn.LaunchCharacter = function(self, v, xy, z) M.launched = v end
M.pawn.Crouch = function() error("crouch crashes the real game") end
M.pawn.UnCrouch = function() error("uncrouch should not be called") end
M.riderMesh = obj("SkeletalMeshComponent", "PlayerMesh", {})
M.riderMesh.PlayAnimation = function(self, a, loop) M.playing = a M.looping = loop M.animPos = 0 M.playRate = 1 end
M.riderMesh.SetPosition = function(self, p, notify) M.animPos = p end
M.riderMesh.SetPlayRate = function(self, r) M.playRate = r end
M.riderMesh.SetAnimationMode = function(self, m, force) assert(force ~= nil, "SetAnimationMode needs 2 args in this game") M.playing = nil M.animMode = m end
M.riderMesh.AnimClass = obj("Class", "AnimBlueprintGeneratedClass ABP_Player_C", {})
M.riderMesh.SetAnimInstanceClass = function(self, c) M.animClassSet = c end
M.pawn.Mesh = M.riderMesh
M.pc = obj("BP_DunePlayerController_C", "PC", {})
M.pc.Pawn = M.pawn
M.pc.IsLocalPlayerController = function() return true end
M.pc.IsInputKeyDown = function(self, k) return M.held[k.KeyName] == true end

-- worm and its AI
M.ai = obj("AIController", "AI_Worm", {})
M.worm = actor("BP_Crea_SandwormArrakis_C", "BP_Crea_SandwormArrakis_C /Game/Maps/Hagga.Sandworm_1", { X = 3000, Y = 1000, Z = -2000 })
M.worm.Controller = M.ai
-- like the real worm: position point deep underground, body box 800 cm tall around it
M.worm.GetActorBounds = function(self, onlyColl, origin, extent, children)
  origin.X, origin.Y, origin.Z = self.loc.X, self.loc.Y, self.loc.Z
  extent.X, extent.Y, extent.Z = 4000, 600, 800
end
M.ai.UnPossess = function(self) M.worm.Controller = nil M.aiOn = false M.detached = true end
M.brain = obj("BrainComponent", "Brain", {})
M.brain.StopLogic = function(self, why) M.aiOn = false end
M.brain.RestartLogic = function(self) M.aiOn = true end
M.ai.BrainComponent = M.brain
M.ai.StopMovement = function() M.stopMoves = (M.stopMoves or 0) + 1 end
M.ai.Possess = function(self, p) p.Controller = self M.aiOn = true end
M.aiOn = true

-- the worm's visible body: a skeletal mesh component 30 m above the worm's position point
M.wormMesh = obj("SkeletalMesh", "SkeletalMesh /Game/Dune/Creatures/Sandworm/SK_Sandworm.SK_Sandworm", {})
M.body = obj("SkeletalMeshComponent", "SkeletalMeshComponent /Game/Maps/Survival_1.BP_Crea_SandwormArrakis_C_1.SandwormSkeletalMesh", {})
M.body.RelativeLocation = { X = 0, Y = 0, Z = 2500 }
M.body.RelativeRotation = { Pitch = 0, Yaw = -90, Roll = 0 }
M.body.GetSkeletalMeshAsset = function() return M.wormMesh end
M.body.GetOwner = function() return M.worm end
M.body.K2_GetComponentLocation = function() local l = M.worm.loc local r = M.body.RelativeLocation return { X = l.X + r.X, Y = l.Y + r.Y, Z = l.Z + r.Z } end
M.body.K2_GetComponentScale = function() return { X = 2, Y = 2, Z = 2 } end
M.body.K2_GetComponentRotation = function() return { Pitch = 0, Yaw = M.worm.rot.Yaw - 90, Roll = 0 } end
M.body.K2_SetRelativeLocation = function(self, v, sw, hit, tp) assert(type(hit) == "table") self.RelativeLocation = { X = v.X, Y = v.Y, Z = v.Z } end
-- like the real game: the worm's own part list holds no animated body (it lives elsewhere)
local function tarray(items)
  return setmetatable({}, { __index = { ForEach = function(self, fn) for i, v in ipairs(items) do fn(i, { get = function() return v end }) end end } })
end
M.worm.SandwormSkeletalMesh = M.body
M.wormRoot = obj("SceneComponent", "SceneComponent BP_Crea_SandwormArrakis_C.DefaultSceneRoot", {})
M.worm.K2_GetComponentsByClass = function(self, cls)
  local n = cls:GetFullName()
  if n:find("ActorComponent") then return tarray({ M.wormRoot }) end
  return tarray({})
end
M.spawned = {}
M.gs = obj("GameplayStatics", "Default__GameplayStatics", {})
M.gs.BeginDeferredActorSpawnFromClass = function(self, ctx, cls, xf, coll, owner, scaleMethod)
  if cls:GetFullName():find("StaticMeshActor") then
    local a = actor("StaticMeshActor", "StaticMeshActor_Wire", xf.Translation)
    local c = obj("StaticMeshComponent", "Wire.StaticMeshComponent", {})
    c.SetMobility = function(self, m) self.mobility = m end
    c.SetStaticMesh = function(self, m) self.mesh = m return true end
    c.SetMaterial = function(self, i, m) self.material = m end
    a.StaticMeshComponent = c
    a.SetActorScale3D = function(self, v) self.scale = v end
    a.K2_DestroyActor = function(self) self.__valid = false end
    M.wire = a
    return a
  end
  assert(cls:GetFullName():find("SkeletalMeshActor"))
  local a = actor("SkeletalMeshActor", "SkeletalMeshActor_WormDouble", xf.Translation)
  local c = obj("SkeletalMeshComponent", "Double.SkeletalMeshComponent", {})
  c.SetSkeletalMeshAsset = function(self, m) self.mesh = m end
  c.SetLeaderPoseComponent = function(self, leader, force, followerTick) assert(followerTick ~= nil, "needs 3 args") self.leader = leader end
  c.K2_SetWorldRotation = function(self, r, sw, hit, tp) assert(type(hit) == "table") self.worldRot = r end
  c.SetWorldScale3D = function(self, v) self.scale = v end
  c.K2_SetRelativeRotation = function(self, r) self.relRot = r end
  local bones = { "Root", "Move", "neck_01", "neck_02", "neck_03", "neck_04", "neck_05", "head_01", "mouth_01_t", "tail_base", "tail_01" }
  local fwdOf = { Root = 0, Move = 0, neck_01 = 0, neck_02 = 1100, neck_03 = 2300, neck_04 = 3300, neck_05 = 4300, head_01 = 5200, mouth_01_t = 6700, tail_base = 0, tail_01 = -1200 }
  c.GetNumBones = function() return #bones end
  c.GetBoneName = function(self, i) return bones[i + 1] end
  -- the body sways sideways and undulates; the head lags the worm's turn
  function M.boneWorld(name)
    local l = a.loc
    local f = fwdOf[name] or 0
    local yaw = math.rad((M.worm.rot.Yaw or 0) - 20 * f / 5200)
    local side = (f == 0 and 0 or 300 * math.sin(M.t * 1.5 + f / 1000))
    return { X = l.X + f * math.cos(yaw) - side * math.sin(yaw), Y = l.Y + f * math.sin(yaw) + side * math.cos(yaw),
             Z = l.Z + 1500 + (f == 0 and 0 or 400 * math.sin(M.t * 2 + f / 1000)) }
  end
  c.GetSocketLocation = function(self, name) return M.boneWorld(name) end
  c.SetCollisionResponseToAllChannels = function(self, r) self.resp = r end
  c.SetCollisionEnabled = function(self, e) self.coll = e end
  -- body surface: 600 cm above the nearest neck bone's centre line
  c.K2_LineTraceComponent = function(self, s0, e0, complex, show, persist, hitLoc, hitNormal, boneName, outHit)
    assert(type(boneName) == "table", "Tried storing reference to a Lua table for an 'Out' parameter")
    local b = M.boneWorld("neck_03")
    hitLoc.X, hitLoc.Y, hitLoc.Z = s0.X, s0.Y, b.Z + 3500
    M.bodyTopZ = b.Z + 3500
    return true
  end
  a.SkeletalMeshComponent = c
  a.K2_DestroyActor = function(self) self.__valid = false end
  M.spawned[#M.spawned + 1] = a
  M.double = a
  return a
end
M.gs.FinishSpawningActor = function(self, a, xf, m) a.finished = true return a end

M.kml = obj("KismetMathLibrary", "Default__KismetMathLibrary", {})
M.kml.MakeRotFromZ = function(self, v) return { Pitch = math.deg(math.asin(math.max(-1, math.min(1, v.Z)))) - 90, Yaw = math.deg(math.atan(v.Y, v.X)), Roll = 0 } end
-- libraries
M.ksl = obj("KismetSystemLibrary", "Default__KismetSystemLibrary", {})
M.ksl.GetGameTimeInSeconds = function(self, ctx) return M.t end
M.ksl.LineTraceSingle = function(self, ctx, a, b, ch, cx, ignore, dbg, hit, selfIgnore, c1, c2, dt)
  if M.traceBroken then return false end
  hit.ImpactPoint = { X = a.X, Y = a.Y, Z = M.ground(a.X, a.Y) }
  return true
end
local textBlock = obj("TextBlock", "Text", { Font = { Size = 10 } })
textBlock.SetText = function(self, t) M.hudText = t end
textBlock.SetJustification = function() end
textBlock.SetFont = function() end
textBlock.SetShadowOffset = function() end
textBlock.SetColorAndOpacity = function(self, c) M.hudColor = c end
textBlock.SetVisibility = function(self, v) M.textVis = v end
local slot = { SetAnchors = function() end, SetAlignment = function() end, SetAutoSize = function() end }
M.wbl = obj("WidgetBlueprintLibrary", "Default__WidgetBlueprintLibrary", {})
M.wbl.Create = function(self, ctx, cls, pc)
  local w = obj("UserWidget", "W", {})
  w.AddToViewport = function(self, z) M.inViewport = true end
  w.SetVisibility = function(self, v) M.widgetVis = v end
  return w
end

_G.FName = function(s) return s end
_G.FText = function(s) return s end
_G.Key = setmetatable({}, { __index = function(_, k) return k end })
_G.RegisterKeyBind = function(k, fn) M.keybinds[k] = fn end
_G.RegisterEndPlayPreHook = function(fn) M.endPlayHook = fn end
_G.RegisterLoadMapPreHook = function(fn) M.loadMapHook = fn end
-- simulate the game deleting an actor: EndPlay fires, then its memory is freed
function M.destroyActor(a)
  M.endPlayHook({ get = function() return a end }, 0)
  for k in pairs(a) do if type(a[k]) == "function" and k ~= "GetAddress" then a[k] = function() error("touched freed object: " .. k) end end end
  a.__valid = false
  a.IsValid = function() error("IsValid on freed object (would crash the game)") end
end
_G.LoopAsync = function(ms, fn) M.loops[#M.loops + 1] = { ms = ms, fn = fn } end
_G.ExecuteInGameThread = function(fn) fn() end
M.anims = { obj("AnimSequence", "AnimSequence /Game/Dune/Animations/Gadgets/Grenades/A_Grenade_Position_TEMP.A_Grenade_Position_TEMP", {}),
            obj("AnimSequence", "AnimSequence /Game/Dune/Animations/Humans/Vehicles/A_Human_Sandbike_Turn_L.A_Human_Sandbike_Turn_L", {}),
            obj("AnimSequence", "AnimSequence /Game/Anims/Locomotion/A_Run_Fwd.A_Run_Fwd", {}),
            obj("AnimSequence", "AnimSequence /Game/Dune/Animations/Humans/Vehicles/A_Human_Sandbike_Idle.A_Human_Sandbike_Idle", {}),
            obj("AnimSequence", "AnimSequence /Game/Dune/Vehicles/DropShip/A_SDS_DropShip_Drive_Close.A_SDS_DropShip_Drive_Close", {}),
            obj("AnimSequence", "AnimSequence /Game/Anims/Locomotion/A_Human_Crouch_Idle.A_Human_Crouch_Idle", {}) }
M.otherBody = obj("SkeletalMeshComponent", "SkeletalMeshComponent /Game/Maps/Hagga.BP_Npc_C_1.Mesh", {})
_G.FindAllOf = function(name)
  if name == "SkinnedMeshComponent" then return { M.otherBody, M.body } end
  if name == "AnimationAsset" then return M.anims end
  if name == "PlayerController" then return { M.pc } end
  if name == "BP_Crea_SandwormArrakis_C" then return M.wormHidden and nil or (M.worm.__valid and { M.worm } or nil) end
  if name == "Pawn" then return { M.pawn, M.worm } end
  return nil
end
_G.FindFirstOf = function(name) return obj(name, name, {}) end
M.loadedAssets = {}
_G.LoadAsset = function(path)
  if path:find("^/Engine/BasicShapes/") or path:find("ShigawirePlayer/Materials") then
    local a = obj("Asset", "Asset " .. path, {})
    M.loadedAssets[path] = a
    return a
  end
  if path:find("/Animations/") then
    local a = obj("AnimSequence", "AnimSequence " .. path, {})
    a.GetPlayLength = function() return 2.4 end
    M.loadedAssets[path] = a
    return a
  end
  return nil
end
function M.animNamed(part) for p, a in pairs(M.loadedAssets) do if p:find(part, 1, true) then return a end end end
_G.StaticFindObject = function(path)
  if path:find("/Animations/") or path:find("^/Engine/BasicShapes/") or path:find("ShigawirePlayer") then return M.loadedAssets[path] end
  if path:find("KismetMathLibrary") then return M.kml end
  if path:find("KismetSystemLibrary") then return M.ksl end
  if path:find("WidgetBlueprintLibrary") then return M.wbl end
  if path:find("GameplayStatics") then return M.gs end
  return obj("Class", path, {})
end
_G.StaticConstructObject = function(cls, outer, name)
  local p = cls:GetFullName()
  if p:find("TextBlock") then return textBlock end
  if p:find("CanvasPanel") then local c = obj("CanvasPanel", "Canvas", {}) c.AddChildToCanvas = function() return slot end return c end
  if p:find("WidgetTree") then return obj("WidgetTree", "Tree", {}) end
  return obj("Object", p, {})
end
local realPrint = print
_G.print = function(s) M.log[#M.log + 1] = s end

function M.press(k) assert(M.keybinds[k], "no keybind for " .. k) M.keybinds[k]() end
function M.step(seconds)
  local ms = M.loops[1].ms
  local n = math.floor(seconds * 1000 / ms + 0.5)
  for _ = 1, n do
    M.t = M.t + ms / 1000
    -- the real worm's queued "teleport to attack" reads its controller when it fires
    if M.attackAt and M.t >= M.attackAt then
      M.attackAt = nil
      M.attackFiredWithController = (M.worm.Controller ~= nil)
    end
    M.loops[1].fn()
  end
end
function M.lastLog(pattern)
  for i = #M.log, 1, -1 do if M.log[i]:find(pattern) then return M.log[i] end end
end
M.realPrint = realPrint

function M.wormTop() return M.worm.loc.Z + 800 - M.ground(M.worm.loc.X, M.worm.loc.Y) end
function M.riderUp() return M.pawn.loc.Z - M.ground(M.pawn.loc.X, M.pawn.loc.Y) end
return M
