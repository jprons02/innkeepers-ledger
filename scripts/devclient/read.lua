-- Dev harness (#139): reads ILDev's SavedVariables after a tour and reports it.
-- Usage: lua read.lua <ILDev.lua saved variables> <Screenshots folder> <out folder>
-- Prints the run (client facts, steps, errors, layout warnings), writes each dump as an
-- indented tree to <out>/<label>.txt and the screenshots to crop to <out>/crops.txt
-- (source|destination|x|y|w|h|screenW|screenH), which crop.ps1 reads.
-- The output names the character (the book's title): it stays out of the repo.
local svPath, shotDir, out = arg[1], arg[2], arg[3]
assert(svPath and shotDir and out, "usage: lua read.lua <saved variables> <Screenshots> <out>")

local chunk = assert(loadfile(svPath))
local env = {}
setfenv(chunk, env)
chunk()
local db = env.ILDevDB or {}
local run = db.run
if type(run) ~= "table" then
  print("no run in " .. svPath)
  os.exit(1)
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function fmtRect(r)
  if type(r) ~= "table" then
    return "-"
  end
  return ("%g,%g %gx%g"):format(r[1], r[2], r[3], r[4])
end

print(("run %s  started %s  finished %s"):format(tostring(run.id),
  run.started and os.date("%Y-%m-%d %H:%M:%S", run.started) or "?",
  run.finished and os.date("%H:%M:%S", run.finished) or "NO (cut short)"))
local c = run.client or {}
print(("client build %s, interface %s, screen %s, UI %s, scale %s"):format(tostring(c.build),
  tostring(c.interface), c.screen and table.concat(c.screen, "x") or "?",
  c.ui and table.concat(c.ui, "x") or "?", tostring(c.uiScale)))
print(("automatic reload worked: %s;  watch until: %s"):format(tostring(db.reloadWorked),
  db.watchUntil and os.date("%H:%M", db.watchUntil) or "off"))
for _, b in ipairs(db.blocked or {}) do
  print("BLOCKED: " .. b)
end

print("\nsteps:")
for _, s in ipairs(run.steps or {}) do
  print(("  %6.1fs %s %s%s"):format(s.t or 0, s.ok and "ok  " or "FAIL", s.op,
    s.note and ("  (" .. s.note .. ")") or ""))
end
print("\nlua errors: " .. #(run.errors or {}))
for _, e in ipairs(run.errors or {}) do
  print("  " .. e:gsub("\n", "\n  "))
end

-- Screenshots: WoWScrnShot_MMDDYY_HHMMSS.<ext>, named in local time to the second.
local function shotFile(stamp)
  local mo, d, y, h, mi, s = stamp:match("^(%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)$")
  if not mo then
    return nil
  end
  local t = os.time({ year = 2000 + y, month = mo, day = d, hour = h, min = mi, sec = s })
  for _, delta in ipairs({ 0, -1, 1, -2, 2 }) do
    local name = "WoWScrnShot_" .. os.date("%m%d%y_%H%M%S", t + delta)
    for _, ext in ipairs({ ".jpg", ".png", ".tga" }) do
      local path = shotDir .. "/" .. name .. ext
      if exists(path) then
        return path
      end
    end
  end
  return nil
end

print("\nscreenshots:")
local crops = assert(io.open(out .. "/crops.txt", "wb"))
for i, shot in ipairs(run.shots or {}) do
  local file = shot.ok and shot.stamp and shotFile(shot.stamp)
  local dest = ("%s/%02d-%s.png"):format(out, i, shot.label)
  if file and shot.crop then
    local k = shot.crop
    crops:write(table.concat({ file, dest, k.x, k.y, k.w, k.h, k.screenW, k.screenH }, "|"),
      "\n")
  elseif file then
    crops:write(table.concat({ file, dest, 0, 0, 0, 0, 0, 0 }, "|"), "\n")
  end
  print(("  %02d %-24s %s"):format(i, shot.label, file and dest or "MISSING (" ..
    tostring(shot.stamp) .. ")"))
end
crops:close()

-- Layout: trees and warnings.
local function inside(r, box)
  return r[1] >= box[1] - 1 and r[2] >= box[2] - 1 and r[1] + r[3] <= box[1] + box[3] + 1
    and r[2] + r[4] <= box[2] + box[4] + 1
end

local labels = {}
for label in pairs(run.dumps or {}) do
  labels[#labels + 1] = label
end
table.sort(labels)
print("\nlayout warnings:")
for _, label in ipairs(labels) do
  local rootNode = run.dumps[label]
  local f = assert(io.open(out .. "/" .. label .. ".txt", "wb"))
  local warnings = {}
  local function warn(path, text)
    warnings[#warnings + 1] = ("  [%s] %s: %s"):format(label, path, text)
  end
  local function walk(n, depth, path)
    local name = n.name or n.k
    path = path .. "/" .. name
    f:write(("%s%s%s %s%s%s%s%s%s\n"):format(("  "):rep(depth), n.k,
      n.name and (" " .. n.name) or "", n.vis and "V" or (n.shown and "s" or "-"),
      " " .. fmtRect(n.r),
      n.strata and (" " .. n.strata .. ":" .. tostring(n.level)) or "",
      n.layer and (" " .. n.layer .. ":" .. tostring(n.sub)) or "",
      n.text and (" %q"):format(n.text) or "",
      (n.tex and (" tex=" .. n.tex) or "") .. (n.sw and (" sw=" .. n.sw) or "")
      .. (n.trunc and " TRUNCATED" or "") .. (n.a and n.a < 1 and (" a=" .. n.a) or "")))
    if n.vis then
      if n.k == "FontString" and n.text then
        if n.trunc then
          warn(path, ("text truncated %q (box %s, text %s wide)"):format(n.text,
            fmtRect(n.r), tostring(n.sw)))
        end
        if not n.r or n.r[3] <= 0 or n.r[4] <= 0 then
          warn(path, ("text %q has no size (%s)"):format(n.text, fmtRect(n.r)))
        end
        if n.color and n.color[4] == 0 then
          warn(path, ("text %q is fully transparent"):format(n.text))
        end
      end
      if n.r and rootNode.r and depth > 0 and not inside(n.r, rootNode.r) then
        warn(path, ("outside %s: %s vs %s"):format(rootNode.name or rootNode.k,
          fmtRect(n.r), fmtRect(rootNode.r)))
      end
      if n.r and c.ui and (n.r[1] + n.r[3] < 0 or n.r[2] + n.r[4] < 0 or n.r[1] > c.ui[1]
        or n.r[2] > c.ui[2]) then
        warn(path, "off screen " .. fmtRect(n.r))
      end
    end
    for _, kid in ipairs(n.kids or {}) do
      walk(kid, depth + 1, path)
    end
  end
  walk(rootNode, 0, "")
  f:close()
  for _, w in ipairs(warnings) do
    print(w)
  end
end
print(("\ntrees: %s/<dump>.txt (%d dumps)"):format(out, #labels))
