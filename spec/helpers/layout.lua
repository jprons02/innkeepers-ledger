-- Layout checks over the stub's frames (#140): every shown region resolves, stays inside
-- its parent, overlaps nothing it shouldn't, and its estimated text fits. Geometry comes
-- from wow.rect (spec/helpers/wow_stub.lua), so it follows the client's anchor rules; text
-- sizes are the stub's conservative estimate. Each check returns a list of problems, one
-- string each with the numbers, so a spec asserts it's empty and a mutation test asserts
-- it isn't.
local wow = require("helpers.wow_stub")

local M = {}

local EPS = 0.001
-- A button's label keeps this far from each side (UIPanelButtonTemplate's art border).
M.BUTTON_INSET = 4

local function rectText(l, b, w, h)
  return string.format("(%.1f, %.1f, %.1f x %.1f)", l, b, w, h)
end

-- Names every region reachable in `ui` (a test handle like Book.ui) by its path, e.g.
-- "list.rows[3].text". Regions themselves aren't searched.
local function nameRegions(ui)
  local names, seen = {}, {}
  local function walk(t, path, depth)
    if seen[t] or depth > 6 then
      return
    end
    seen[t] = true
    local keys = {}
    for k in pairs(t) do
      if type(k) == "string" or type(k) == "number" then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b)
      if type(a) ~= type(b) then
        return type(a) == "number"
      end
      return a < b
    end)
    for _, k in ipairs(keys) do
      local v = t[k]
      local sub = type(k) == "number" and path .. "[" .. k .. "]"
        or (path == "" and k or path .. "." .. k)
      if type(v) == "table" then
        if v.kind and v.points then
          if names[v] == nil then
            names[v] = sub
          end
        else
          walk(v, sub, depth + 1)
        end
      end
    end
  end
  walk(ui, "", 0)
  return names
end

-- Every region under `root` (root first, then textures, font strings and child frames,
-- depth first): { region, name, parent }. `ui` names them; the rest get a path from their
-- parent's name.
function M.collect(root, ui, rootName)
  local names = nameRegions(ui or {})
  local items = {}
  local function add(region, name, parent)
    name = names[region] or name
    items[#items + 1] = { region = region, name = name, parent = parent }
    for i, tex in ipairs(region.textures or {}) do
      add(tex, name .. ".textures[" .. i .. "]", region)
    end
    for i, fs in ipairs(region.fontStrings or {}) do
      add(fs, name .. ".fontStrings[" .. i .. "]", region)
    end
    if region.events then -- a frame
      for i, child in ipairs(wow.children(region)) do
        add(child, name .. ".children[" .. i .. "]", region)
      end
    end
  end
  add(root, rootName or "root", nil)
  return items
end

-- Shown, with every parent up to `root` shown.
function M.visible(region, root)
  local r = region
  while r ~= nil do
    if not r.shown then
      return false
    end
    if rawequal(r, root) then
      return true
    end
    r = r.parent
  end
  return true
end

local function shownItems(items)
  local root = items[1].region
  local out = {}
  for _, it in ipairs(items) do
    if M.visible(it.region, root) then
      out[#out + 1] = it
    end
  end
  return out
end

local function inside(a, b)
  return a[1] >= b[1] - EPS and a[2] >= b[2] - EPS and a[1] + a[3] <= b[1] + b[3] + EPS
    and a[2] + a[4] <= b[2] + b[4] + EPS
end

local function rectOf(region)
  local l, b, w, h = wow.rect(region)
  if l == nil then
    return nil
  end
  return { l, b, w, h }
end

-- 1. Every shown region resolves to a rectangle.
function M.unresolved(items)
  local out = {}
  for _, it in ipairs(shownItems(items)) do
    if rectOf(it.region) == nil then
      out[#out + 1] = it.name .. " doesn't resolve"
    end
  end
  return out
end

-- 2. Every shown region lies inside its parent. `instead` maps a region to the region it
-- must lie inside instead (an intentional exception), or to false to skip it.
function M.outside(items, instead)
  instead = instead or {}
  local out = {}
  for _, it in ipairs(shownItems(items)) do
    local box = it.parent
    if instead[it.region] ~= nil then
      box = instead[it.region]
    end
    if box then
      local r, b = rectOf(it.region), rectOf(box)
      if r and b and not inside(r, b) then
        out[#out + 1] = string.format("%s %s leaves %s", it.name, rectText(r[1], r[2], r[3],
          r[4]), rectText(b[1], b[2], b[3], b[4]))
      end
    end
  end
  return out
end

-- Where a font string's text is drawn: its box narrowed to the estimated text, by its
-- justification (the client's defaults: centered both ways). nil for no text.
function M.ink(fs)
  local r = rectOf(fs)
  if r == nil then
    return nil
  end
  local lines, widest = wow.textLines(fs, r[3])
  if lines == 0 then
    return nil
  end
  local w = math.min(widest, r[3])
  local h = math.min(lines * wow.fontSize(fs), r[4])
  local l, b = r[1], r[2]
  local jh, jv = fs.justifyH or "CENTER", fs.justifyV or "MIDDLE"
  if jh == "RIGHT" then
    l = l + r[3] - w
  elseif jh ~= "LEFT" then
    l = l + (r[3] - w) / 2
  end
  if jv == "TOP" then
    b = b + r[4] - h
  elseif jv ~= "BOTTOM" then
    b = b + (r[4] - h) / 2
  end
  return { l, b, w, h }
end

local function ancestor(a, b)
  local r = b.parent
  while r ~= nil do
    if rawequal(r, a) then
      return true
    end
    r = r.parent
  end
  return false
end

-- 3. No two shown regions overlap, except a region and its own parents, and a backdrop: a
-- region that covers its whole parent (panels, page and row backgrounds, highlights).
-- Text counts where it's drawn (M.ink). `allowed(a, b)` returns true for an intentional
-- overlap (either order).
function M.overlaps(items, allowed)
  local boxes = {}
  for _, it in ipairs(shownItems(items)) do
    local r
    if it.region.kind == "FontString" then
      r = M.ink(it.region)
    else
      r = rectOf(it.region)
      local p = it.parent and rectOf(it.parent)
      if r and p and inside(p, r) then
        r = nil -- a backdrop
      end
    end
    if it.parent and r and r[3] > EPS and r[4] > EPS then
      boxes[#boxes + 1] = { it = it, r = r }
    end
  end
  local out = {}
  for i = 1, #boxes do
    for j = i + 1, #boxes do
      local a, b = boxes[i], boxes[j]
      local ra, rb = a.r, b.r
      local dx = math.min(ra[1] + ra[3], rb[1] + rb[3]) - math.max(ra[1], rb[1])
      local dy = math.min(ra[2] + ra[4], rb[2] + rb[4]) - math.max(ra[2], rb[2])
      if dx > EPS and dy > EPS and not ancestor(a.it.region, b.it.region)
        and not ancestor(b.it.region, a.it.region)
        and not (allowed and (allowed(a.it.region, b.it.region)
          or allowed(b.it.region, a.it.region))) then
        out[#out + 1] = string.format("%s %s overlaps %s %s by %.1f x %.1f", a.it.name,
          rectText(ra[1], ra[2], ra[3], ra[4]), b.it.name, rectText(rb[1], rb[2], rb[3], rb[4]),
          dx, dy)
      end
    end
  end
  return out
end

-- 4. Every shown text fits its box, by the estimate: a line that doesn't wrap fits its
-- width, a wrapped text has no word wider than its box and, in a box of set height, no
-- more lines than fit. A button's label fits inside its border (BUTTON_INSET a side).
function M.overflows(items)
  local out = {}
  for _, it in ipairs(shownItems(items)) do
    local region = it.region
    local r = rectOf(region)
    local text = region.text
    if r and type(text) == "string" and text ~= "" then
      if region.kind == "FontString" then
        local lines, widest, word = wow.textLines(region, r[3])
        local size = wow.fontSize(region)
        if region.wordWrap == false and widest > r[3] + EPS then
          out[#out + 1] = string.format("%s: %q is %.1f wide in %.1f", it.name, text, widest,
            r[3])
        elseif word > r[3] + EPS then
          out[#out + 1] = string.format("%s: a word of %q is %.1f wide in %.1f", it.name, text,
            word, r[3])
        end
        if lines * size > r[4] + EPS then
          out[#out + 1] = string.format("%s: %q is %d lines (%.1f high) in %.1f", it.name, text,
            lines, lines * size, r[4])
        end
      elseif region.kind == "Button" then
        local w = wow.textWidth(region, text)
        if w > r[3] - 2 * M.BUTTON_INSET + EPS then
          out[#out + 1] = string.format("%s: label %q is %.1f wide in %.1f (inset %d)", it.name,
            text, w, r[3], M.BUTTON_INSET)
        end
      end
    end
  end
  return out
end

-- 5. A region lies inside the screen (UIParent, 1024 x 768).
function M.offScreen(region, name)
  local r = rectOf(region)
  if r == nil then
    return { name .. " doesn't resolve" }
  end
  if not inside(r, { 0, 0, wow.SCREEN_W, wow.SCREEN_H }) then
    return { string.format("%s %s leaves the screen", name, rectText(r[1], r[2], r[3], r[4])) }
  end
  return {}
end

return M
