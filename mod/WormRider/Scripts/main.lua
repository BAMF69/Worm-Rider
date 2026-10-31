-- Worm Rider: tame and ride Shai-Hulud in Dune: Awakening (Solo).
-- Taming works like ARK's Concavenator: get on, survive the wild ride by
-- matching arrow prompts, fill the bond bar or get thrown off.
-- All names and numbers come from sheets.lua (generated from sheets/*.json).

local S = require("sheets")
local REF, STAGE, CTRL, CFG, HUD, COLORS, POSEWORD, ANIM, ASSET, BONESKIP, SEAT = S.REF, S.STAGE, S.CTRL, S.CFG, S.HUD, S.COLORS, S.POSEWORD, S.ANIM, S.ASSET, S.BONESKIP, S.SEAT

local TAG = "[WormRider] "
local LOGFILE = "../Mods/WormRider/wormrider.log"
local function log(fmt, ...)
  local line = string.format(fmt, ...)
  print(TAG .. line .. "\n")
  pcall(function()
    local f = io.open(LOGFILE, "a")
    if f then f:write(os.date("%H:%M:%S "), line, "\n") f:flush() f:close() end
  end)
end

math.randomseed(os.time())

---------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------
local function valid(o) return o ~= nil and o.IsValid ~= nil and o:IsValid() end
local function addr(o)
  if o == nil then return nil end
  local ok, a = pcall(function() return o:GetAddress() end)
  return ok and a or nil
end
local function same(a, b)
  if a == b then return true end
  local ok, r = pcall(function() return a:GetAddress() == b:GetAddress() end)
  return ok and r
end
local function call(obj, ref, ...) return obj[ref.name](obj, ...) end
local function v3(x, y, z) return { X = x, Y = y, Z = z } end
local function dist2d(a, b) local dx, dy = a.X - b.X, a.Y - b.Y return math.sqrt(dx * dx + dy * dy) end
local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
local function approach(cur, target, step) if cur < target then return math.min(cur + step, target) end return math.max(cur - step, target) end
local function fwd(yawDeg) local r = math.rad(yawDeg) return math.cos(r), math.sin(r) end
local function getLoc(a) local l = call(a, REF.fn_get_loc) return { X = l.X, Y = l.Y, Z = l.Z } end
local function setLoc(a, p) call(a, REF.fn_set_loc, v3(p.X, p.Y, p.Z), false, {}, true) end
local function setYaw(a, yaw) call(a, REF.fn_set_rot, { Pitch = 0.0, Yaw = yaw, Roll = 0.0 }, true) end

local function kismet(ref)
  local o = StaticFindObject(ref.owner)
  if valid(o) then return o end
  return nil
end

---------------------------------------------------------------------------
-- player and clock
---------------------------------------------------------------------------
local cachedPC = nil
local function playerController()
  if valid(cachedPC) and valid(cachedPC[REF.prop_pawn.name]) then return cachedPC end
  cachedPC = nil
  local all = FindAllOf(REF.player_controller.name)
  if all then
    for _, pc in ipairs(all) do
      if valid(pc) then
        local ok, isLocal = pcall(call, pc, REF.fn_is_local)
        if ok and isLocal then cachedPC = pc break end
      end
    end
  end
  return cachedPC
end

local function playerPawn()
  local pc = playerController()
  if not pc then return nil end
  local p = pc[REF.prop_pawn.name]
  if valid(p) then return p end
  return nil
end

local fallbackClock = 0
local function now()
  local ksl = kismet(REF.fn_game_time)
  local pawn = playerPawn()
  if ksl and pawn then
    local ok, t = pcall(call, ksl, REF.fn_game_time, pawn)
    if ok and type(t) == "number" then return t end
  end
  fallbackClock = fallbackClock + CFG.tick_ms.value / 1000
  return fallbackClock
end

local function held(ctrlRow)
  local pc = playerController()
  if not pc then return false end
  local ok, down = pcall(call, pc, REF.fn_key_down, { KeyName = FName(ctrlRow.ue_key) })
  return ok and down == true
end

---------------------------------------------------------------------------
-- worms
---------------------------------------------------------------------------
local nextFallbackScan = 0
local fallbackWorms = {}

local function isWormName(o)
  local ok, n = pcall(function() return o:GetFullName() end)
  return ok and n and n:find(REF.worm_name_hint.name, 1, true) ~= nil and not n:find("Default__", 1, true)
end

local function findWorms(t)
  local list = {}
  local found = FindAllOf(REF.worm_class.name)
  if found then
    for _, w in ipairs(found) do if valid(w) and isWormName(w) then list[#list + 1] = w end end
  end
  if #list > 0 then return list end
  if t >= nextFallbackScan then
    nextFallbackScan = t + CFG.fallback_scan_seconds.value
    fallbackWorms = {}
    local pawns = FindAllOf(REF.worm_name_hint.owner)
    if pawns then
      for _, p in ipairs(pawns) do if valid(p) and isWormName(p) then fallbackWorms[#fallbackWorms + 1] = p end end
    end
  end
  for _, w in ipairs(fallbackWorms) do if valid(w) then list[#list + 1] = w end end
  return list
end

local function nearestWorm(t, from)
  local best, bestD = nil, math.huge
  for _, w in ipairs(findWorms(t)) do
    local ok, l = pcall(getLoc, w)
    if ok then
      local d = dist2d(l, from)
      if d < bestD then best, bestD = w, d end
    end
  end
  return best, bestD
end

---------------------------------------------------------------------------
-- sand surface
---------------------------------------------------------------------------
local traceColor = { R = 0, G = 0, B = 0, A = 0 }
local function groundZ(x, y, zHint, ignore)
  local ksl = kismet(REF.fn_trace)
  local ctx = playerPawn()
  if not ksl or not ctx then return nil end
  local h = CFG.trace_half_height.value
  local function try(ignoreList)
    local hit = {}
    local was = call(ksl, REF.fn_trace, ctx, v3(x, y, zHint + h), v3(x, y, zHint - h), 0, false,
      ignoreList, 0, hit, true, traceColor, traceColor, 0.0)
    if was then
      local p = hit.ImpactPoint or hit.Location
      if p then return p.Z end
    end
    return nil
  end
  local ok, z = pcall(try, ignore)
  if ok and z then return z end
  ok, z = pcall(try, {})
  if ok then return z end
  return nil
end

-- sand height at x,y; falls back to the surface you stood on when you leapt
local function sandAt(st, x, y, hint, ignore)
  local g = groundZ(x, y, hint or st.surfaceZ or 0, ignore)
  if g and st.surfaceZ and math.abs(g - st.surfaceZ) > 6000 then g = nil end -- hit something odd (worm body, sky)
  if g then st.surfaceZ = g return g, true end
  return st.surfaceZ, false
end

---------------------------------------------------------------------------
-- HUD (a UMG text block on a canvas, created from Lua)
---------------------------------------------------------------------------
local hud = { widget = nil, text = nil, last = nil, color = nil, failed = 0 }

local function umgClass(ref) return StaticFindObject(ref.owner .. "." .. ref.name) end

local function ensureHud()
  if valid(hud.widget) and valid(hud.text) then return true end
  if hud.failed > 5 then return false end
  local pc = playerController()
  if not pc then return false end
  local ok, err = pcall(function()
    local uwClass = umgClass(REF.cls_user_widget)
    local widget = nil
    local lib = kismet(REF.fn_widget_create)
    if lib then
      local okc, w = pcall(call, lib, REF.fn_widget_create, pc, uwClass, pc)
      if okc and valid(w) then widget = w end
    end
    if not widget then
      widget = StaticConstructObject(uwClass, FindFirstOf("GameInstance"), FName("WormRiderHUD"))
    end
    if not valid(widget.WidgetTree) then
      widget.WidgetTree = StaticConstructObject(umgClass(REF.cls_widget_tree), widget, FName("WormRiderTree"))
    end
    local tree = widget.WidgetTree
    local text = StaticConstructObject(umgClass(REF.cls_text_block), tree, FName("WormRiderText"))
    local placed = pcall(function()
      local canvas = StaticConstructObject(umgClass(REF.cls_canvas_panel), tree, FName("WormRiderCanvas"))
      tree.RootWidget = canvas
      local slot = canvas:AddChildToCanvas(text)
      local y = CFG.hud_anchor_y.value
      slot:SetAnchors({ Minimum = { X = 0.5, Y = y }, Maximum = { X = 0.5, Y = y } })
      slot:SetAlignment({ X = 0.5, Y = 0.5 })
      slot:SetAutoSize(true)
    end)
    if not placed then tree.RootWidget = text end
    pcall(function() text:SetJustification(1) end)
    pcall(function()
      local font = text.Font
      font.Size = CFG.hud_font_size.value
      text:SetFont(font)
    end)
    pcall(function() text:SetShadowOffset({ X = 2.0, Y = 2.0 }) end)
    pcall(call, widget, REF.fn_set_visibility, 3) -- HitTestInvisible: never takes clicks or focus
    pcall(call, text, REF.fn_set_visibility, 3)
    widget:AddToViewport(900)
    hud.widget, hud.text, hud.last, hud.color, hud.shown = widget, text, nil, nil, true
  end)
  if not ok then
    hud.failed = hud.failed + 1
    log("HUD unavailable (%s); messages go to UE4SS.log", tostring(err))
    return false
  end
  log("HUD ready")
  return true
end

local function fill(text, fields)
  return (text:gsub("{([%w_]+)}", function(k) local v = fields[k] if v == nil then return "" end return tostring(v) end))
end

local function showHud(hudRow, fields)
  local msg = hudRow and fill(hudRow.text, fields or {}) or ""
  if msg == hud.last then return end
  hud.last = msg
  local rowId = hudRow and hudRow.id or ""
  if msg ~= "" and rowId ~= hud.lastRow then log("HUD: %s", (msg:gsub("\n", " | "))) end
  hud.lastRow = rowId
  if not ensureHud() then return end
  local want = msg ~= ""
  if want ~= hud.shown then
    pcall(call, hud.widget, REF.fn_set_visibility, want and 3 or 1) -- 1 = Collapsed
    hud.shown = want
  end
  pcall(function()
    if hudRow and hud.color ~= hudRow.color then
      local c = COLORS[hudRow.color]
      hud.text:SetColorAndOpacity({ SpecifiedColor = { R = c[1], G = c[2], B = c[3], A = c[4] }, ColorUseRule = 0 })
      hud.color = hudRow.color
    end
    hud.text:SetText(FText(msg))
  end)
end

local function bar(fraction)
  local cells = CFG.hud_bar_cells.value
  local n = clamp(math.floor(fraction * cells + 0.5), 0, cells)
  return "[" .. string.rep("#", n) .. string.rep("-", cells - n) .. "]"
end

---------------------------------------------------------------------------
-- trick sequences (the Concavenator arrow mini-game)
---------------------------------------------------------------------------
local ARROWS = { CTRL.arrow_up, CTRL.arrow_down, CTRL.arrow_left, CTRL.arrow_right }

local function newSequence(st, t)
  st.seq, st.seqPos = {}, 1
  for i = 1, CFG.sequence_length.value do st.seq[i] = ARROWS[math.random(#ARROWS)] end
  st.seqDeadline = t + CFG.sequence_seconds.value
end

local function sequenceText(st)
  local parts = {}
  for i, a in ipairs(st.seq) do
    if i < st.seqPos then parts[i] = "*"
    else
      local label = a.glyph
      if st.stage == STAGE.wild_ride.id and a.alt_key ~= "none" then label = label .. "/" .. a.alt_key end
      parts[i] = (i == st.seqPos) and (">" .. label .. "<") or label
    end
  end
  return table.concat(parts, "   ")
end

-- returns "done", "step", "miss" or nil
local function sequenceInput(st, arrow)
  if not st.seq or not st.seq[st.seqPos] then return nil end
  if st.seq[st.seqPos] == arrow then
    st.seqPos = st.seqPos + 1
    if st.seqPos > #st.seq then return "done" end
    return "step"
  end
  st.seqPos = 1
  return "miss"
end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local st = {
  stage = "idle", t = 0, stageStart = 0, deadline = nil,
  worm = nil, ctrl = nil, aiReleased = false, pawn = nil,
  yaw = 0, speed = 0, sink = 0, surfaceZ = nil, wormDepth = 0, yawOffset = CFG.worm_yaw_offset.value, seatAdjust = 0, showControls = CFG.show_controls.value == 1,
  bond = 0, seq = nil, seqPos = 1, seqDeadline = 0,
  wanderTurn = 0, wanderNext = 0,
  breachStart = nil, breachReady = 0, boostCharge = 0, boostUntil = 0,
  calling = false, flash = nil, nearDist = nil, loadedShown = false,
}

---------------------------------------------------------------------------
-- worm body parts and the sand-height double (experimental, opt-in)
---------------------------------------------------------------------------
local body = { comp = nil, baseRel = nil, offset = 0, double = nil, doubleComp = nil, lift = 0 }

local function engineClass(ref) return StaticFindObject(ref.owner .. "." .. ref.name) end
local function vec(v) if not v then return nil end return { X = v.X, Y = v.Y, Z = v.Z } end

-- UE4SS hands TArrays back as userdata with ForEach; accept plain tables too
local function toList(arr)
  local list = {}
  if arr == nil then return list end
  local okFE = pcall(function()
    if not arr.ForEach then error("no ForEach") end
    arr:ForEach(function(_, e) local c = (type(e) ~= "nil" and e.get) and e:get() or e list[#list + 1] = c end)
  end)
  if okFE then return list end
  if type(arr) == "table" then
    for _, c in ipairs(arr) do list[#list + 1] = c end
    return list
  end
  pcall(function() for i = 1, #arr do list[#list + 1] = arr[i] end end)
  return list
end

local function componentsOf(actor, classRef)
  local ok, arr = pcall(call, actor, REF.fn_get_components, engineClass(classRef))
  if not ok then log("components(%s) failed: %s", classRef.name, tostring(arr)) return {} end
  local list = {}
  for _, c in ipairs(toList(arr)) do if valid(c) then list[#list + 1] = c end end
  return list
end

local function meshOf(comp)
  local ok, m = pcall(call, comp, REF.fn_get_mesh)
  if ok and valid(m) then return m end
  local ok2, m2 = pcall(function() return comp[REF.prop_mesh_old.name] end)
  if ok2 and valid(m2) then return m2 end
  return nil
end

local function className(o)
  local ok, n = pcall(function() return o:GetClass():GetFName():ToString() end)
  if ok and n then return n end
  local ok2, full = pcall(function() return o:GetFullName() end)
  return ok2 and full and full:match("^(%S+)") or "?"
end

local function compZ(c)
  local okw, wl = pcall(call, c, REF.fn_comp_loc)
  return (okw and wl) and wl or nil
end

-- read-only: log what the worm is made of and remember its animated body
local function inspectBodies(worm)
  body.comp, body.baseRel, body.offset = nil, nil, 0
  local parts = componentsOf(worm, REF.cls_actor_comp)
  log("worm has %d parts", #parts)
  for i, c in ipairs(parts) do
    if i > 40 then break end
    log("  part %d: %s (%s)", i, c:GetFullName(), className(c))
  end
  local okp, direct = pcall(function() return worm[REF.prop_worm_mesh.name] end)
  if okp and valid(direct) and meshOf(direct) then body.comp = direct end
  if not body.comp then
    for _, c in ipairs(componentsOf(worm, REF.cls_skel_comp)) do
      if meshOf(c) then body.comp = c break end
    end
  end
  if not body.comp then
    -- the body may be a separate object that follows the worm: search worm-named body parts nearby
    local wl = getLoc(worm)
    local best, bestD, n = nil, math.huge, 0
    for _, c in ipairs(FindAllOf(REF.cls_skinned_comp.name) or {}) do
      local okn, name = pcall(function() return c:GetFullName() end)
      if okn and name and name:lower():find(REF.worm_name_hint.name:lower(), 1, true) and not name:find("Default__", 1, true) then
        local p = compZ(c)
        local d = p and dist2d(p, wl) or math.huge
        n = n + 1
        if n <= CFG.body_scan_max.value then
          log("  world body %d: %s dist=%s model=%s", n, name, d < math.huge and string.format("%.0f m", d / 100) or "?", tostring(meshOf(c) and meshOf(c):GetFullName()))
        end
        if meshOf(c) and d < bestD and d <= CFG.body_search_radius.value then best, bestD = c, d end
      end
    end
    body.comp = best
  end
  if body.comp then
    local oko, owner = pcall(call, body.comp, REF.fn_get_owner)
    st.bodyOwnerAddr = (oko and owner) and addr(owner) or nil
    body.baseRel = vec(body.comp[REF.prop_rel_loc.name])
    local p = compZ(body.comp)
    log("worm body: %s worldZ=%s", body.comp:GetFullName(), p and string.format("%.0f", p.Z) or "?")
  else
    log("worm body: none found")
  end
  return body.comp
end

local function moveRealBody(delta)
  if not valid(body.comp) or not body.baseRel then return false end
  body.offset = body.offset + delta
  local b = body.baseRel
  call(body.comp, REF.fn_set_rel_loc, v3(b.X, b.Y, b.Z + body.offset), false, {}, true)
  return true
end

local function restoreRealBody()
  if valid(body.comp) and body.baseRel and body.offset ~= 0 then
    local b = body.baseRel
    pcall(call, body.comp, REF.fn_set_rel_loc, v3(b.X, b.Y, b.Z), false, {}, true)
    log("real worm body restored")
  end
  body.offset = 0
end

local function destroyDouble()
  if valid(body.double) then pcall(call, body.double, REF.fn_destroy) log("worm double removed") end
  body.double, body.doubleComp = nil, nil
  body.rideBone, body.rideOffset, body.seatBone, body.faceBone, body.loggedTop = nil, nil, nil, nil, nil
  st.riderPos, st.riderZ = nil, nil
end

local function tryCalls(obj, ref, argSets)
  local last
  for _, args in ipairs(argSets) do
    local ok, r = pcall(function() return obj[ref.name](obj, table.unpack(args, 1, args.n)) end)
    if ok then return true, r end
    last = r
  end
  return false, last
end
local function pack(...) return { n = select("#", ...), ... } end

local function spawnDouble(worm)
  if not valid(body.comp) then inspectBodies(worm) end
  if not valid(body.comp) then return nil, "no visible body found" end
  local mesh = meshOf(body.comp)
  if not mesh then return nil, "no worm model" end
  local gs = kismet(REF.fn_spawn)
  local ctx = playerPawn()
  if not gs or not ctx then return nil, "no spawner" end
  local cls = engineClass(REF.cls_skel_actor)
  local okl, wl = pcall(call, body.comp, REF.fn_comp_loc)
  local sandZ = st.surfaceZ or ((okl and wl) and wl.Z or getLoc(worm).Z)
  local at = (okl and wl) and v3(wl.X, wl.Y, sandZ + CFG.double_sand_offset.value) or getLoc(worm)
  local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = at, Scale3D = v3(1, 1, 1) }
  local ok, a = tryCalls(gs, REF.fn_spawn, { pack(ctx, cls, xf, 1, nil, 0), pack(ctx, cls, xf, 1, nil), pack(ctx, cls, xf, 1, ctx, 0), pack(ctx, cls, xf, 1, ctx) })
  if not ok or not valid(a) then return nil, "spawn failed: " .. tostring(a) end
  tryCalls(gs, REF.fn_finish_spawn, { pack(a, xf, 0), pack(a, xf) })
  local dc = a[REF.prop_skel_actor_comp.name]
  if not valid(dc) then pcall(call, a, REF.fn_destroy) return nil, "double has no body" end
  local okm = tryCalls(dc, REF.fn_set_mesh, { pack(mesh) })
  if not okm then okm = tryCalls(dc, REF.fn_set_mesh_old, { pack(mesh, true), pack(mesh) }) end
  if not okm then pcall(call, a, REF.fn_destroy) return nil, "could not set the worm model" end
  -- traceable by the mod (to find the top of the body) but ignored by everything else
  local okq = pcall(call, dc, REF.fn_set_resp_all, 0) and pcall(call, dc, REF.fn_set_coll_enabled, 1)
  if not okq then pcall(call, a, REF.fn_collision, false) end
  local oks, sc = pcall(call, body.comp, REF.fn_comp_scale)
  if oks and sc then pcall(call, dc, REF.fn_set_scale, v3(sc.X, sc.Y, sc.Z)) end
  local rr = body.comp[REF.prop_rel_rot.name]
  if rr then pcall(call, dc, REF.fn_set_rel_rot, { Pitch = rr.Pitch, Yaw = rr.Yaw, Roll = rr.Roll }, false, {}, true) end
  local okp, perr = tryCalls(dc, REF.fn_leader, { pack(body.comp, false, false), pack(body.comp, false), pack(body.comp) })
  if not okp then okp, perr = tryCalls(dc, REF.fn_leader_old, { pack(body.comp, false, false), pack(body.comp, false), pack(body.comp) }) end
  if not okp then log("copy animation failed: %s", tostring(perr)) end
  body.double, body.doubleComp, body.lift = a, dc, CFG.double_sand_offset.value
  body.spawnedAt, body.rideBone, body.rideOffset, body.rideBoneFailed = st.t, nil, nil, false
  body.seatBone, body.faceBone, body.loggedTop, st.riderPos, st.riderZ = nil, nil, nil, nil, nil
  local okr, wr = pcall(call, body.comp, REF.fn_comp_rot)
  log("real body rotation: rel=%s world=%s worm yaw=%.0f",
    rr and string.format("%.0f/%.0f/%.0f", rr.Pitch, rr.Yaw, rr.Roll) or "?",
    (okr and wr) and string.format("%.0f/%.0f/%.0f", wr.Pitch, wr.Yaw, wr.Roll) or "?", st.yaw)
  log("worm double spawned (model=%s, copies animation=%s)", mesh:GetFullName(), tostring(okp))
  return a
end

-- keep the double over the real body, body.lift higher
local function updateDouble()
  if not valid(body.double) then return end
  if not valid(st.worm) or not valid(body.comp) then destroyDouble() return end
  local okl, wl = pcall(call, body.comp, REF.fn_comp_loc)
  if not okl or not wl then return end
  setLoc(body.double, v3(wl.X, wl.Y, (st.surfaceZ or wl.Z) + body.lift))
  local okr, wr = pcall(call, body.comp, REF.fn_comp_rot)
  if okr and wr and valid(body.doubleComp) then
    pcall(call, body.doubleComp, REF.fn_set_world_rot, { Pitch = wr.Pitch, Yaw = wr.Yaw, Roll = wr.Roll }, false, {}, true)
  else
    setYaw(body.double, st.yaw + st.yawOffset)
  end
end

---------------------------------------------------------------------------
-- riding pose (crouch + optional loaded animation, F7 cycles)
---------------------------------------------------------------------------
local pose = { list = nil, idx = 0, playing = false }

local function riderMesh(pawn)
  local ok, m = pcall(function() return pawn[REF.prop_char_mesh.name] end)
  if ok and valid(m) then return m end
  return nil
end

-- animations from the player's own install, loaded on first use
-- Looked up fresh every time: the game may unload an asset nobody else uses,
-- and a kept reference would then point at freed memory.
local missingLogged = {}
local function loadObject(row)
  local a = StaticFindObject(row.path)
  if not valid(a) and LoadAsset then
    local ok, r = pcall(LoadAsset, row.path)
    if ok and valid(r) then a = r else a = StaticFindObject(row.path) end
  end
  if valid(a) then return a end
  if not missingLogged[row.path] then missingLogged[row.path] = true log("not found in your game: %s", row.path) end
  return nil
end
local animAsset = loadObject

local function playAnim(pawn, row)
  if CFG.ride_anims.value ~= 1 or not valid(pawn) then return false end
  local m, a = riderMesh(pawn), animAsset(row)
  if not m or not a then return false end
  if not pose.playing and not pose.savedClass then
    local okc, cls = pcall(function() return m[REF.prop_anim_class.name] end)
    if okc and valid(cls) then pose.savedClass = cls end
  end
  local ok, err = pcall(call, m, REF.fn_play_anim, a, row.loop)
  if ok then pose.playing, pose.current = true, row.id else log("play %s failed: %s", row.id, tostring(err)) end
  if ok and row.hold_end then
    -- jump to the final frame and hold it (if any step fails, the one-shot still ends on that frame)
    local okl, len = pcall(call, a, REF.fn_play_length)
    if okl and type(len) == "number" and len > 0 then
      pcall(call, m, REF.fn_set_position, math.max(0, len - 0.03), false)
    end
    pcall(call, m, REF.fn_set_play_rate, 0)
  end
  return ok
end

local function poseRank(fullName)
  local base = (fullName:match("([%w_]+)$") or fullName):lower()
  local best = nil
  for token in base:gmatch("[^_]+") do
    for _, w in pairs(POSEWORD) do
      if token == w.word and (not best or w.priority < best) then best = w.priority end
    end
  end
  if best and base:find("idle", 1, true) then best = best - 0.5 end -- idle loops make the steadiest pose
  return best
end

local function scanPoses()
  local found = {}
  local all = FindAllOf(REF.cls_anim_seq.name) or {}
  for _, a in ipairs(all) do
    local okn, n = pcall(function() return a:GetFullName() end)
    if okn and n and not n:find("Default__", 1, true) and n:find("/Humans/", 1, true) then
      local r = poseRank(n)
      if r then found[#found + 1] = { asset = a, rank = r, name = n } end
    end
  end
  table.sort(found, function(x, y) if x.rank ~= y.rank then return x.rank < y.rank end return x.name < y.name end)
  pose.list, pose.best = {}, found[1] and found[1].rank or nil
  for i, f in ipairs(found) do
    if i > CFG.pose_scan_max.value then break end
    pose.list[i] = f.asset
    log("pose candidate %d (rank %.1f): %s", i, f.rank, f.name)
  end
  log("pose scan: %d candidates among %d loaded animations", #found, #all)
end

-- (crouching the rider crashes the game while mounted, so poses are animation-only)
local function applyPose(pawn)
  if pose.idx > 0 and pose.list and pose.list[pose.idx] and valid(pose.list[pose.idx]) then
    local m = riderMesh(pawn)
    if m then
      local ok, err = pcall(call, m, REF.fn_play_anim, pose.list[pose.idx], true)
      if ok then pose.playing = true else log("pose play failed: %s", tostring(err)) end
    end
  end
end

-- give the rider their own animations back (mode 0 = animation blueprint)
local function restoreAnims(m)
  pcall(call, m, REF.fn_set_play_rate, 1)
  local ok, err = tryCalls(m, REF.fn_anim_mode, { pack(0, true), pack(0) })
  if not ok then log("restore animations: SetAnimationMode failed (%s)", tostring(err)) end
  if (not ok) and pose.savedClass then
    local ok2, err2 = pcall(call, m, REF.fn_set_anim_class, pose.savedClass)
    if not ok2 then log("restore animations: SetAnimInstanceClass failed (%s)", tostring(err2)) end
  end
end

local function clearPose(pawn)
  if not valid(pawn) then return end
  local m = riderMesh(pawn)
  if m and pose.playing then restoreAnims(m) end
  pose.playing, pose.current, pose.savedClass = false, nil, nil
end

---------------------------------------------------------------------------
-- the Shigawire wire (a thin cylinder from your hand to the worm)
---------------------------------------------------------------------------
local wire = { actor = nil, comp = nil, failed = false }

local function destroyWire()
  if valid(wire.actor) then pcall(call, wire.actor, REF.fn_destroy) end
  wire.actor, wire.comp = nil, nil
end

local function spawnWire()
  if valid(wire.actor) then return true end
  if wire.failed then return false end
  local gs, ctx = kismet(REF.fn_spawn), playerPawn()
  if not gs or not ctx then return false end
  local p = getLoc(ctx)
  local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = v3(p.X, p.Y, p.Z), Scale3D = v3(1, 1, 1) }
  local cls = engineClass(REF.cls_static_mesh_actor)
  local ok, a = tryCalls(gs, REF.fn_spawn, { pack(ctx, cls, xf, 1, nil, 0), pack(ctx, cls, xf, 1, nil), pack(ctx, cls, xf, 1, ctx, 0), pack(ctx, cls, xf, 1, ctx) })
  if not ok or not valid(a) then log("wire spawn failed: %s", tostring(a)) wire.failed = true return false end
  tryCalls(gs, REF.fn_finish_spawn, { pack(a, xf, 0), pack(a, xf) })
  local c = a[REF.prop_smc.name]
  local mesh = loadObject(ASSET.wire_mesh)
  if not valid(c) or not mesh then pcall(call, a, REF.fn_destroy) wire.failed = true return false end
  pcall(call, c, REF.fn_set_mobility, 2) -- movable
  if not tryCalls(c, REF.fn_set_static_mesh, { pack(mesh) }) then pcall(call, a, REF.fn_destroy) wire.failed = true log("wire: could not set mesh") return false end
  local mat = loadObject(ASSET.wire_material)
  if mat then pcall(call, c, REF.fn_set_material, 0, mat) end
  pcall(call, a, REF.fn_collision, false)
  wire.actor, wire.comp = a, c
  log("wire spawned")
  return true
end

local function placeWire(from, to)
  if not valid(wire.actor) then return end
  local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  if len < 5 then len = 5 end
  setLoc(wire.actor, v3((from.X + to.X) / 2, (from.Y + to.Y) / 2, (from.Z + to.Z) / 2))
  local kml = kismet(REF.fn_rot_from_z)
  local okr, rot = false, nil
  if kml then okr, rot = pcall(call, kml, REF.fn_rot_from_z, v3(dx / len, dy / len, dz / len)) end
  if okr and rot then pcall(call, wire.actor, REF.fn_set_rot, { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }, true) end
  local t = CFG.wire_thickness.value
  pcall(call, wire.actor, REF.fn_actor_scale, v3(t, t, len / 100))
end

---------------------------------------------------------------------------
-- riding on the double's body: follow the bone under the rider
---------------------------------------------------------------------------
local function skipBone(name)
  local n = name:lower()
  for _, sk in pairs(BONESKIP) do
    if sk.part == "root" then
      if n == "root" then return true end
    elseif n:find(sk.part, 1, true) then return true end
  end
  return false
end

local function boneLabel(bn)
  local ok, t = pcall(function() return bn:ToString() end)
  return (ok and t) and t or tostring(bn)
end

local function bonePos(c, name)
  local ok, l = pcall(call, c, REF.fn_socket_loc, FName(name))
  if ok and l then return { X = l.X, Y = l.Y, Z = l.Z } end
  return nil
end

-- read-only: list the bones once, then choose the seat and look-at bones from the seat sheet
local function pickRideBone(rx, ry, rz)
  local c = body.doubleComp
  if not valid(c) then return end
  local okn, n = pcall(call, c, REF.fn_num_bones)
  if not okn or type(n) ~= "number" or n <= 0 then log("ride bone: no bones (%s)", tostring(n)) body.rideBoneFailed = true return end
  local fx, fy = fwd(st.yaw)
  local present, nearest, nearestD = {}, nil, math.huge
  for i = 0, n - 1 do
    local okb, bn = pcall(call, c, REF.fn_bone_name, i)
    if okb and bn then
      local label = boneLabel(bn)
      present[label] = true
      local l = bonePos(c, label)
      if l then
        local dx, dy = l.X - rx, l.Y - ry
        log("  bone %d %s: fwd %.0f side %.0f up %.0f m", i, label, (dx * fx + dy * fy) / 100, (-dx * fy + dy * fx) / 100, (l.Z - rz) / 100)
        local d = math.sqrt(dx * dx + dy * dy)
        if not skipBone(label) and d < nearestD then nearest, nearestD = label, d end
      end
    end
  end
  local function choose(role)
    local best, bp = nil, math.huge
    for _, r in pairs(SEAT) do
      if r.role == role and present[r.bone] and r.priority < bp then best, bp = r.bone, r.priority end
    end
    return best
  end
  body.seatBone = choose("seat") or nearest
  body.faceBone = choose("face")
  if body.seatBone then
    body.rideBone = body.seatBone
    log("ride bone: %s, facing %s (%d bones)", body.seatBone, tostring(body.faceBone), n)
  else
    log("ride bone: none suitable")
    body.rideBoneFailed = true
  end
end

-- top of the double's body at x,y (traced against the double only), or nil
local function bodyTop(x, y, nearZ)
  local c = body.doubleComp
  local hitLoc, hitNormal, boneName, outHit = {}, {}, {}, {}
  local ok, hit = pcall(call, c, REF.fn_trace_comp, v3(x, y, nearZ + 30000), v3(x, y, nearZ - 30000), true, false, false, hitLoc, hitNormal, boneName, outHit)
  if ok and hit then
    local p = (hitLoc.Z and hitLoc) or outHit.ImpactPoint or outHit.Location
    if p and p.Z then return p.Z end
  end
  if not ok and not body.traceWarned then body.traceWarned = true log("body trace failed: %s", tostring(hit)) end
  return nil
end

-- the rider's seat on the double's body: x, y, z and facing yaw, or nil
local function rideOnDouble(rx, ry, rz, dt)
  if CFG.ride_bone_track.value ~= 1 or not valid(body.doubleComp) or body.rideBoneFailed then return nil end
  if not body.rideBone then
    if st.t - (body.spawnedAt or st.t) < CFG.bone_pick_delay.value then return nil end
    pickRideBone(rx, ry, rz)
    if not body.rideBone then return nil end
  end
  local seat = bonePos(body.doubleComp, body.seatBone)
  if not seat then return nil end
  -- left/right/forward: sit over the seat bone (smooth only its sway relative to the worm)
  local ox, oy = 0, 0
  if CFG.ride_follow_sideways.value == 1 then ox, oy = seat.X - rx, seat.Y - ry end
  local k = math.min(1, CFG.ride_track_rate.value * (dt or 0.016))
  local o = st.riderPos
  if not o then o = { X = ox, Y = oy } else o = { X = o.X + (ox - o.X) * k, Y = o.Y + (oy - o.Y) * k } end
  st.riderPos = o
  local x, y = rx + o.X, ry + o.Y
  -- up/down: stand on top of the body right under us
  local top = bodyTop(x, y, seat.Z)
  local tz = seat.Z + CFG.seat_fallback_height.value -- in game: 25 m above the neck
  if top then
    if not body.loggedTop then body.loggedTop = true log("body surface traced %.0f m above seat bone", (top - seat.Z) / 100) end
    tz = math.max(tz, top + CFG.seat_height.value)
  end
  local kz = math.min(1, CFG.ride_height_rate.value * (dt or 0.016))
  st.riderZ = st.riderZ and (st.riderZ + (tz - st.riderZ) * kz) or tz
  if st.riderZ < tz - 150 then st.riderZ = tz - 150 end -- never sink into the body
  -- facing: from the seat toward the head
  local yaw = nil
  if CFG.face_along_body.value == 1 and body.faceBone then
    local h = bonePos(body.doubleComp, body.faceBone)
    if h and (math.abs(h.X - seat.X) + math.abs(h.Y - seat.Y)) > 50 then yaw = math.deg(math.atan(h.Y - seat.Y, h.X - seat.X)) end
  end
  return x, y, st.riderZ, yaw
end


---------------------------------------------------------------------------
-- objects the game removes: drop our hold before the memory is freed
---------------------------------------------------------------------------
local gone = {}  -- address -> true for objects that ended play
local function isGone(o) local a = addr(o) return a ~= nil and gone[a] == true end

local function onEndPlay(ctx)
  local okc, a = pcall(function() if ctx.get then return ctx:get() end return ctx end)
  if not okc or a == nil then return end
  local ad = addr(a)
  if not ad then return end
  if ad == addr(st.worm) or ad == st.bodyOwnerAddr then st.wormGone = true end
  if ad == addr(body.double) then body.double, body.doubleComp = nil, nil end
  if ad == addr(wire.actor) then wire.actor, wire.comp = nil, nil end
  if ad == addr(st.pawn) then st.pawnGone = true end
  if ad == addr(cachedPC) then cachedPC = nil end
  gone[ad] = true
end

local okHook, hookErr = pcall(function()
  RegisterEndPlayPreHook(function(ctx, reason) onEndPlay(ctx) end)
end)
print("[WormRider] " .. REF.hook_end_play.name .. " hook: " .. (okHook and "on" or ("unavailable: " .. tostring(hookErr))) .. "\n")
local okMap = pcall(function()
  RegisterLoadMapPreHook(function()
    st.wormGone, st.pawnGone = st.worm ~= nil, st.pawn ~= nil
    body.double, body.doubleComp, body.comp = nil, nil, nil
    wire.actor, wire.comp = nil, nil
    cachedPC, hud.widget, hud.text = nil, nil, nil
  end)
end)
print("[WormRider] " .. REF.hook_load_map.name .. " hook: " .. (okMap and "on" or "unavailable") .. "\n")

local function flash(hudRow, fields)
  st.flash = { row = hudRow, fields = fields or {}, untilT = st.t + CFG.flash_seconds.value }
end

-- Keep the worm's AI controller attached: the game crashes (null controller)
-- if the worm had an attack queued when its controller was detached.
local function releaseAI()
  if st.aiReleased then return end
  local c = st.worm[REF.prop_controller.name]
  st.ctrl = valid(c) and c or nil
  if CFG.release_ai.value == 1 then
    log("releasing worm AI (detach)")
    if st.ctrl then
      local ok, err = pcall(call, st.ctrl, REF.fn_unpossess)
      if not ok then log("UnPossess failed: %s", tostring(err)) end
    end
    st.aiDetached = true
  else
    log("pausing worm AI (controller stays attached)")
    if st.ctrl then
      pcall(call, st.ctrl, REF.fn_stop_movement)
      local okb, brain = pcall(function() return st.ctrl[REF.prop_brain.name] end)
      if okb and valid(brain) then
        local ok, err = pcall(call, brain, REF.fn_stop_logic, "WormRider")
        log("worm brain paused: %s", ok and "yes" or tostring(err))
        st.brain = ok and brain or nil
      else
        log("worm has no brain component to pause")
      end
    end
    st.aiDetached = false
  end
  st.aiReleased = true
end

-- called every ridden tick so the paused AI never steers against us
local function holdAI()
  if st.aiReleased and not st.aiDetached and valid(st.ctrl) then pcall(call, st.ctrl, REF.fn_stop_movement) end
end

local function restoreAI()
  if not st.aiReleased then return end
  if st.aiDetached then
    if valid(st.ctrl) and valid(st.worm) then
      local ok, err = pcall(call, st.ctrl, REF.fn_possess, st.worm)
      if not ok then log("Possess failed: %s", tostring(err)) end
    end
  elseif valid(st.brain) then
    local ok, err = pcall(call, st.brain, REF.fn_restart_logic)
    if not ok then log("RestartLogic failed: %s", tostring(err)) end
  end
  st.aiReleased, st.aiDetached, st.brain = false, false, nil
end

local function setDilation(worm, value)
  pcall(function() worm[REF.prop_dilation.name] = value end)
end

local function movement(pawn, mode)
  pcall(function()
    local cm = pawn[REF.prop_char_move.name]
    if valid(cm) then call(cm, REF.fn_movement_mode, mode, 0) end
  end)
end

local MOVE_NONE, MOVE_WALKING, MOVE_FALLING = 0, 1, 3

local function mountRider()
  local pawn = playerPawn()
  if not pawn then return end
  st.pawn = pawn
  local p = getLoc(pawn)
  st.surfaceZ = p.Z - CFG.capsule_half_height.value
  local traced = groundZ(p.X, p.Y, p.Z, { pawn, st.worm })
  if traced and math.abs(traced - st.surfaceZ) < 3000 then st.surfaceZ = traced end
  if valid(st.worm) then
    local w = getLoc(st.worm)
    -- keep the worm at its own natural depth below the sand (moving it up is opt-in)
    st.wormDepth = st.surfaceZ - w.Z
    log("mount: pawnZ=%.0f surfaceZ=%.0f traced=%s wormZ=%.0f wormDepth=%.0f",
      p.Z, st.surfaceZ, tostring(traced), w.Z, st.wormDepth)
    local okp, direct = pcall(function() return st.worm[REF.prop_worm_mesh.name] end)
    log("mount: worm body %s", (okp and valid(direct)) and direct:GetFullName() or "not found directly")
    if CFG.auto_double.value == 1 and not valid(body.double) then
      local okd, a, why = pcall(spawnDouble, st.worm)
      if not okd or not a then log("auto double failed: %s", tostring(okd and why or a)) end
    end
  end
  pcall(call, pawn, REF.fn_collision, false)
  movement(pawn, MOVE_NONE)
  st.arcFrom = getLoc(pawn)
  st.landUntil = nil
  playAnim(pawn, ANIM.shig_in)
end

local function unmountRider(how)
  local pawn = st.pawn
  st.pawn = nil
  if not valid(pawn) then return end
  clearPose(pawn)
  pcall(function()
    local base = valid(st.worm) and getLoc(st.worm) or getLoc(pawn)
    local fx, fy = fwd(st.yaw)
    local rx, ry = -fy, fx -- right of the worm
    local side = (how == "thrown") and CFG.thrown_distance.value or CFG.dismount_offset.value
    if how == "thrown" and math.random() < 0.5 then side = -side end
    local x, y = base.X + rx * side, base.Y + ry * side
    local z = sandAt(st, x, y, nil, { pawn, st.worm }) or base.Z
    setLoc(pawn, v3(x, y, z + 150))
  end)
  pcall(call, pawn, REF.fn_collision, true)
  movement(pawn, how == "thrown" and MOVE_FALLING or MOVE_WALKING)
  if how == "thrown" then
    pcall(call, pawn, REF.fn_launch, v3(0, 0, CFG.thrown_launch_up.value), false, true)
  end
end

local function enterStage(id)
  local row = STAGE[id]
  log("enter %s", id)
  local prev = STAGE[st.stage]
  log("stage %s -> %s", st.stage, id)
  st.stage, st.stageStart = id, st.t
  st.deadline = (row.timeout_cfg ~= "none") and (st.t + CFG[row.timeout_cfg].value) or nil
  if valid(st.worm) then
    setDilation(st.worm, row.worm_dilation)
    if row.worm_ai == "released" then releaseAI() else restoreRealBody() destroyDouble() restoreAI() end
  end
  if row.rider_mounted and not prev.rider_mounted then mountRider() end
  if not row.rider_mounted and prev.rider_mounted then unmountRider(id == STAGE.thrown.id and "thrown" or "dismount") end
  st.calling = false
end

local function forgetWorm()
  destroyWire()
  restoreRealBody()
  destroyDouble()
  body.comp, body.baseRel = nil, nil
  st.worm, st.ctrl, st.aiReleased, st.aiDetached, st.brain, st.sink, st.breachStart, st.wormDepth = nil, nil, false, false, nil, 0, nil, 0
end

local function resetToIdle(lost)
  if lost then flash(HUD.hud_lost) end
  if st.pawn then
    local pawn = st.pawn
    st.pawn = nil
    if valid(pawn) then
      clearPose(pawn)
      pcall(call, pawn, REF.fn_collision, true)
      movement(pawn, MOVE_FALLING)
    end
  end
  if st.stage ~= STAGE.idle.id then
    log("stage %s -> idle (reset)", st.stage)
  end
  st.stage, st.stageStart, st.deadline = STAGE.idle.id, st.t, nil
  restoreAI()
  forgetWorm()
end

---------------------------------------------------------------------------
-- moving the worm and rider
---------------------------------------------------------------------------
local function driveWorm(dt)
  local w = st.worm
  local here = getLoc(w)
  local fx, fy = fwd(st.yaw)
  local x, y = here.X + fx * st.speed * dt, here.Y + fy * st.speed * dt
  local g = sandAt(st, x, y, nil, { w, st.pawn }) or here.Z
  local breachOffset = 0
  if st.breachStart then
    local k = (st.t - st.breachStart) / CFG.breach_seconds.value
    if k >= 1 then st.breachStart = nil else breachOffset = math.sin(k * math.pi) * CFG.breach_height.value end
  end
  -- The worm only ever follows the sand at its own natural depth. Moving it
  -- up or down (even 8 m) while ridden crashes the game, so breach and dive
  -- move only the rider.
  local z = g - (st.wormDepth or 0)
  setLoc(w, v3(x, y, z))
  setYaw(w, st.yaw + st.yawOffset)
  return x, y, g, breachOffset
end

local function riderTarget(x, y, g, breachOffset)
  if not g then return nil end
  local fx, fy = fwd(st.yaw)
  local rx, ry = x - fx * CFG.rider_back.value, y - fy * CFG.rider_back.value
  local k = st.sink / CFG.dive_depth.value -- 0 surfacing .. 1 fully dived
  local rz = g + CFG.rider_height.value + (CFG.rider_dive_height.value - CFG.rider_height.value) * k + (breachOffset or 0)
  return rx, ry, rz
end

local function carryRider(x, y, g, breachOffset)
  local pawn = st.pawn
  if not valid(pawn) then return end
  local rx, ry, rz = riderTarget(x, y, g, breachOffset)
  if not rx then return end
  local bx, by, bz, byaw = rideOnDouble(rx, ry, rz - (breachOffset or 0), st.dt)
  if bx then
    local k = st.sink / CFG.dive_depth.value -- diving drops you from the body toward the sand
    rx, ry, rz = bx, by, bz * (1 - k) + (rz - (breachOffset or 0)) * k + (breachOffset or 0)
  end
  setLoc(pawn, v3(rx, ry, rz + st.seatAdjust))
  if CFG.rider_face_forward.value == 1 then pcall(setYaw, pawn, byaw or st.yaw) end
end

---------------------------------------------------------------------------
-- per-stage updates
---------------------------------------------------------------------------
local function rideMode()
  if st.breachStart then return "BREACH!" end
  if st.t < st.boostUntil then return "BOOST!" end
  if st.sink > 1 then return "DIVING" end
  return "SURFACING"
end

local function updateIdle()
  local pawn = playerPawn()
  if not pawn then st.nearDist = nil return end
  local w, d = nearestWorm(st.t, getLoc(pawn))
  st.radarDist = (w and d <= CFG.radar_range.value) and d or nil
  if w and d <= CFG.leap_range.value then
    st.nearDist = d
    st.nearWorm = w
  else
    st.nearDist, st.nearWorm = nil, nil
  end
end

local function updateWild(dt)
  if st.t >= st.wanderNext then
    st.wanderTurn = (math.random() * 2 - 1) * CFG.wild_turn_rate.value
    st.wanderNext = st.t + CFG.wild_wander_seconds.value
  end
  st.yaw = st.yaw + st.wanderTurn * dt
  st.speed = approach(st.speed, CFG.wild_speed.value, CFG.accel.value * dt)
  carryRider(driveWorm(dt))
end

local function updateTamed(dt)
  local diving = held(CTRL.dive)
  local target = CFG.cruise_speed.value
  if held(CTRL.throttle) then target = CFG.ride_speed.value end
  if held(CTRL.brake) then target = 0 end
  if st.t < st.boostUntil then target = CFG.boost_speed.value end
  st.speed = approach(st.speed, target, CFG.accel.value * dt)
  local turn = 0
  if held(CTRL.turn_left) then turn = turn - 1 end
  if held(CTRL.turn_right) then turn = turn + 1 end
  st.yaw = st.yaw + turn * CFG.turn_rate.value * dt
  local sinkTarget = (diving and not st.breachStart) and CFG.dive_depth.value or 0
  st.sink = approach(st.sink, sinkTarget, CFG.dive_depth.value * 2 * dt)
  if diving then
    if not st.seq or st.t > st.seqDeadline then newSequence(st, st.t) end
  else
    st.seq = nil
  end
  carryRider(driveWorm(dt))
end

local function updateCall(dt)
  local pawn = playerPawn()
  if not pawn then return end
  local p, w = getLoc(pawn), getLoc(st.worm)
  local d = dist2d(p, w)
  st.nearDist = d
  if not st.calling then
    st.speed = 0
    driveWorm(0) -- hold it where you left it
  else
    if d <= CFG.call_stop_distance.value then
      st.calling, st.speed = false, 0
    else
      st.yaw = math.deg(math.atan(p.Y - w.Y, p.X - w.X))
      st.speed = approach(st.speed, CFG.call_speed.value, CFG.accel.value * dt)
      driveWorm(dt)
    end
  end
end

local function hudFields()
  local f = {
    leap_key = CTRL.leap.glyph, call_key = CTRL.call.glyph,
    dist = st.nearDist and math.floor(st.nearDist / 100 + 0.5) or "?",
  }
  if st.stage == STAGE.wild_ride.id then
    f.arrows = sequenceText(st)
    f.bar = bar(st.bond / CFG.sequences_to_tame.value)
    f.pct = math.floor(100 * st.bond / CFG.sequences_to_tame.value)
    f.secs = string.format("%.1f", math.max(0, (st.deadline or st.t) - st.t))
  elseif st.stage == STAGE.tamed_ride.id then
    f.controls = st.showControls and fill(HUD.hud_controls.text, { leap_key = CTRL.leap.glyph }) or HUD.hud_controls_hidden.text
    f.speed = math.floor(st.speed * 0.036 + 0.5)
    f.mode = rideMode()
    if st.t < st.boostUntil then
      f.boost_line = string.format("BOOST %.1fs", st.boostUntil - st.t)
    elseif st.seq then
      f.boost_line = sequenceText(st) .. "     BOOST " .. bar(st.boostCharge / CFG.boost_sequences.value)
    else
      f.boost_line = "Hold [" .. CTRL.dive.glyph .. "] to dive, land arrow tricks to charge a boost"
    end
  elseif st.stage == STAGE.thrown.id then
    f.secs = math.max(0, math.ceil((st.deadline or st.t) - st.t))
  end
  return f
end

local function render()
  if st.flash and st.t < st.flash.untilT then
    showHud(st.flash.row, st.flash.fields)
    return
  end
  st.flash = nil
  local row = HUD[STAGE[st.stage].hud]
  local f = hudFields()
  if st.stage == STAGE.idle.id then
    if st.hookReady then
      row = st.radarDist and HUD.hud_ready or HUD.hud_ready_none
      f.dist = st.radarDist and math.floor(st.radarDist / 100 + 0.5) or "?"
    elseif st.nearDist then
      row = HUD.hud_in_range
    elseif st.radarDist then
      row = HUD.hud_radar
      f.dist = math.floor(st.radarDist / 100 + 0.5)
    end
  end
  if st.stage == STAGE.thrown.id and st.t - st.stageStart > CFG.flash_seconds.value then row = HUD.hud_cooldown end
  showHud(row, f)
end

local onLeap
local lastT = nil
local nextIdleScan = 0

local function tick()
  local t = now()
  local dt = lastT and clamp(t - lastT, 0, 0.1) or 0
  lastT = t
  st.t, st.dt = t, dt

  local pawn = playerPawn()
  if not pawn then return end
  if not st.loadedShown then st.loadedShown = true flash(HUD.hud_loaded, { leap_key = CTRL.leap.glyph }) end

  -- the game removed the worm (or its body) or our rider: forget them without touching them
  if st.wormGone then
    st.wormGone = false
    st.worm, st.ctrl, st.brain, body.comp, body.baseRel, body.offset = nil, nil, nil, nil, nil, 0
    st.aiReleased = false
    destroyDouble() -- the double is ours and still alive; remove it
    log("the game removed the worm; letting go")
    resetToIdle(true)
  end
  if st.pawnGone then st.pawnGone = false st.pawn = nil resetToIdle(false) end
  -- the rider died, respawned or changed body: let go of everything
  if st.pawn and not same(st.pawn, pawn) then resetToIdle(false) end
  if st.lastPawn and not same(st.lastPawn, pawn) then st.hookReady = false end
  st.lastPawn = pawn
  -- the worm despawned
  if st.worm and not valid(st.worm) then resetToIdle(true) end

  local row = STAGE[st.stage]
  if st.deadline and t >= st.deadline then
    enterStage(row.on_timeout == "ok" and row.next_ok or row.next_fail)
    if st.stage ~= STAGE.stunned.id then destroyWire() end
    if st.stage == STAGE.wild_ride.id then
      newSequence(st, t) st.deadline = st.seqDeadline
      if playAnim(st.pawn, ANIM.shig_land) then st.landUntil = t + CFG.land_seconds.value end
    end
    if st.stage == STAGE.idle.id then forgetWorm() end
    row = STAGE[st.stage]
  end

  if row.worm_ai == "released" then holdAI() end
  if row.rider_mounted and row.worm_driver ~= "hold" and valid(st.pawn) and pose.idx == 0
     and (not st.landUntil or t >= st.landUntil) then
    local want = ANIM.ride_sit
    if pose.current ~= want.id and (pose.failed or {})[want.id] == nil then
      if not playAnim(st.pawn, want) then pose.failed = pose.failed or {} pose.failed[want.id] = true end
    end
  end
  local ok, err = pcall(function()
    if row.worm_driver == "none" then
      if t >= nextIdleScan then nextIdleScan = t + (st.hookReady and CFG.tick_ms.value or CFG.scan_ms.value) / 1000 updateIdle() end
      if st.hookReady and st.nearWorm and valid(st.nearWorm) then onLeap() end
    elseif row.worm_driver == "hold" then
      local x, y, g, b = driveWorm(0)
      local tx, ty, tz = riderTarget(x, y, g, b)
      local k = clamp((t - st.stageStart) / CFG.stun_seconds.value, 0, 1)
      if st.arcFrom and tx and valid(st.pawn) then
        local f = st.arcFrom
        local e = k * k * (3 - 2 * k) -- ease in/out
        setLoc(st.pawn, v3(f.X + (tx - f.X) * e, f.Y + (ty - f.Y) * e, f.Z + (tz - f.Z) * e + math.sin(k * math.pi) * CFG.arc_height.value))
        pcall(setYaw, st.pawn, math.deg(math.atan(ty - f.Y, tx - f.X)))
        if k >= CFG.claw_throw_fraction.value and pose.current == ANIM.shig_in.id then playAnim(st.pawn, ANIM.shig_loop) end
        if spawnWire() then
          local hand = getLoc(st.pawn)
          hand.Z = hand.Z + CFG.hand_height.value
          local anchor = v3(tx, ty, tz - CFG.rider_height.value * 0.5)
          local reach = math.min(1, k / CFG.claw_throw_fraction.value) -- the claw flies out, then reels in
          placeWire(hand, v3(hand.X + (anchor.X - hand.X) * reach, hand.Y + (anchor.Y - hand.Y) * reach, hand.Z + (anchor.Z - hand.Z) * reach))
        end
      elseif tx then
        carryRider(x, y, g, b)
      end
    elseif row.worm_driver == "wild" then
      updateWild(dt)
    elseif row.worm_driver == "rider" then
      updateTamed(dt)
    elseif row.worm_driver == "call" then
      updateCall(dt)
    end
  end)
  if ok and body.double then
    local okd, errd = pcall(updateDouble)
    if not okd then log("double error: %s", tostring(errd)) destroyDouble() end
  end
  if not ok then
    log("update error in %s: %s", st.stage, tostring(err))
    if st.worm and not valid(st.worm) then resetToIdle(true) end
  end
  render()
end

---------------------------------------------------------------------------
-- presses
---------------------------------------------------------------------------
onLeap = function()
  if st.stage == STAGE.idle.id then
    if not st.nearWorm or not valid(st.nearWorm) then
      st.hookReady = not st.hookReady
      log("hook %s", st.hookReady and "ready" or "cancelled")
      return
    end
    st.hookReady = false
    st.worm = st.nearWorm
    st.nearWorm, st.nearDist = nil, nil
    local okr, r = pcall(call, st.worm, REF.fn_get_rot)
    st.yaw = okr and r.Yaw - st.yawOffset or 0
    st.speed, st.sink, st.bond = 0, 0, 0
    enterStage(STAGE.idle.next_ok)
  elseif st.stage == STAGE.tamed_ride.id then
    st.speed, st.sink, st.seq = 0, 0, nil
    enterStage(STAGE.tamed_ride.next_ok)
  elseif st.stage == STAGE.tamed_wait.id then
    if st.nearDist and st.nearDist <= CFG.remount_range.value then
      st.speed = 0
      enterStage(STAGE.tamed_wait.next_ok)
    end
  end
end

local function onCall()
  if st.stage ~= STAGE.tamed_wait.id then return end
  if st.nearDist and st.nearDist <= CFG.call_range.value then
    st.calling = true
  else
    flash(HUD.hud_too_far, { dist = st.nearDist and math.floor(st.nearDist / 100) or "?" })
  end
end

local function onBreach()
  if st.stage ~= STAGE.tamed_ride.id or st.breachStart or st.t < st.breachReady then return end
  st.breachStart = st.t
  st.breachReady = st.t + CFG.breach_cooldown.value
  st.sink = 0
end

local function onArrow(arrow, alt)
  if alt and st.stage ~= STAGE.wild_ride.id then return end -- WASD steers once tamed
  if st.stage == STAGE.wild_ride.id then
    local r = sequenceInput(st, arrow)
    if r == "done" then
      st.bond = st.bond + 1
      if st.bond >= CFG.sequences_to_tame.value then
        enterStage(STAGE.wild_ride.next_ok)
        flash(HUD.hud_tamed)
        log("worm tamed")
      else
        newSequence(st, st.t)
        st.deadline = st.seqDeadline
      end
    end
  elseif st.stage == STAGE.tamed_ride.id and st.seq then
    if sequenceInput(st, arrow) == "done" then
      st.boostCharge = st.boostCharge + 1
      if st.boostCharge >= CFG.boost_sequences.value then
        st.boostCharge = 0
        st.boostUntil = st.t + CFG.boost_seconds.value
      end
      newSequence(st, st.t)
    end
  end
end

local function inStages(ctrlRow)
  for _, sid in ipairs(ctrlRow.stages) do if sid == st.stage then return true end end
  return false
end

local function onDouble()
  if not inStages(CTRL.double) or not valid(st.worm) then return end
  if valid(body.double) then
    destroyDouble()
    flash(HUD.hud_double_off)
    return
  end
  local a, why = spawnDouble(st.worm)
  if a then flash(HUD.hud_double_on) else log("double failed: %s", tostring(why)) flash(HUD.hud_double_fail, { why = why }) end
end

local function onBody(dir)
  if not inStages(CTRL.body_up) or not valid(st.worm) then return end
  local step = dir * CFG.body_step.value
  if valid(body.double) then
    body.lift = body.lift + step
    log("double lift now %d cm", body.lift)
    flash(HUD.hud_body, { what = "Double", h = string.format("%+.0f", body.lift / 100) })
  else
    if not valid(body.comp) then inspectBodies(st.worm) end
    log("moving real worm body by %d cm (experimental)", step)
    if moveRealBody(step) then
      flash(HUD.hud_body, { what = "Worm body", h = string.format("%+.0f", body.offset / 100) })
    else
      flash(HUD.hud_double_fail, { why = "no visible body found" })
    end
  end
end

local function onPose()
  if not inStages(CTRL.pose) or not valid(st.pawn) then return end
  scanPoses() -- fresh every press: the game may have unloaded earlier results
  if #pose.list == 0 then flash(HUD.hud_pose_none) return end
  pose.idx = pose.idx + 1
  if pose.idx > #pose.list then
    pose.idx = 0
    pose.current = nil -- the riding pose picks back up next tick
    log("pose: cross-legged riding pose")
    flash(HUD.hud_pose_off)
    return
  end
  applyPose(st.pawn)
  local name = pose.list[pose.idx]:GetFullName():match("([%w_]+)$") or "?"
  log("pose %d: %s", pose.idx, pose.list[pose.idx]:GetFullName())
  flash(HUD.hud_pose, { i = pose.idx, n = #pose.list, name = name })
end

local function onControls()
  if not inStages(CTRL.controls) then return end
  st.showControls = not st.showControls
end

local function onSeat(dir)
  if not inStages(CTRL.seat_up) then return end
  st.seatAdjust = st.seatAdjust + dir * CFG.seat_step.value
  log("seat adjust now %+d cm (seat_fallback_height %d would keep it)", st.seatAdjust, CFG.seat_fallback_height.value + st.seatAdjust)
  flash(HUD.hud_seat, { h = string.format("%+.0f", st.seatAdjust / 100) })
end

local function onGame(fn, ...)
  local args = { ... }
  ExecuteInGameThread(function()
    local ok, err = pcall(fn, table.unpack(args))
    if not ok then log("input error: %s", tostring(err)) end
  end)
end

RegisterKeyBind(Key[CTRL.leap.ue4ss_key], function() onGame(onLeap) end)
RegisterKeyBind(Key[CTRL.call.ue4ss_key], function() onGame(onCall) end)
RegisterKeyBind(Key[CTRL.breach.ue4ss_key], function() onGame(onBreach) end)
RegisterKeyBind(Key[CTRL.double.ue4ss_key], function() onGame(onDouble) end)
RegisterKeyBind(Key[CTRL.pose.ue4ss_key], function() onGame(onPose) end)
RegisterKeyBind(Key[CTRL.seat_up.ue4ss_key], function() onGame(onSeat, 1) end)
RegisterKeyBind(Key[CTRL.controls.ue4ss_key], function() onGame(onControls) end)
RegisterKeyBind(Key[CTRL.seat_down.ue4ss_key], function() onGame(onSeat, -1) end)
RegisterKeyBind(Key[CTRL.body_up.ue4ss_key], function() onGame(onBody, 1) end)
RegisterKeyBind(Key[CTRL.body_down.ue4ss_key], function() onGame(onBody, -1) end)
for _, a in ipairs(ARROWS) do
  RegisterKeyBind(Key[a.ue4ss_key], function() onGame(onArrow, a, false) end)
  if a.alt_key ~= "none" then
    RegisterKeyBind(Key[a.alt_key], function() onGame(onArrow, a, true) end)
  end
end

---------------------------------------------------------------------------
-- main loop
---------------------------------------------------------------------------
local busy = false
LoopAsync(CFG.tick_ms.value, function()
  if not busy then
    busy = true
    ExecuteInGameThread(function()
      local ok, err = pcall(tick)
      if not ok then log("tick error: %s", tostring(err)) end
      busy = false
    end)
  end
  return false
end)

local n = 0 for _ in pairs(STAGE) do n = n + 1 end
log("loaded (stages=%d, worm class=%s)", n, REF.worm_class.name)
