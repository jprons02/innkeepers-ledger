-- The TOC, the library load order and Core, run the way the client would load them.
local lfs = require("lfs")
local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local function exists(path)
  return lfs.attributes(path, "mode") == "file"
end

-- Our own .lua files: everything outside Libs/, spec/, scripts/ and local tooling.
local SKIP = { Libs = true, spec = true, scripts = true, [".git"] = true,
  [".luarocks"] = true, lua_modules = true, [".release"] = true }

local function own_lua_files(dir, out)
  for entry in lfs.dir(dir) do
    local path = dir == "." and entry or dir .. "/" .. entry
    if entry ~= "." and entry ~= ".." and not SKIP[entry] then
      local mode = lfs.attributes(path, "mode")
      if mode == "directory" then
        own_lua_files(path, out)
      elseif entry:match("%.lua$") then
        out[#out + 1] = path
      end
    end
  end
  return out
end

describe("InnkeepersLedger.toc", function()
  it("lists only files that exist", function()
    for _, path in ipairs(load.toc_files()) do
      assert.is_true(exists(path), path .. " is listed but missing")
    end
  end)

  it("lists every one of our Lua files", function()
    local listed = {}
    for _, path in ipairs(load.toc_files()) do
      listed[path] = true
    end
    for _, path in ipairs(own_lua_files(".", {})) do
      assert.is_true(listed[path] == true, path .. " is not in the TOC")
    end
  end)

  it("lists each of our files in exactly one of load.PURE, load.DATA and load.GLUE", function()
    local kinds = {}
    for _, list in ipairs({ load.PURE, load.DATA, load.GLUE }) do
      for _, module in ipairs(list) do
        assert.is_nil(kinds[module.path], module.path .. " is in two lists")
        kinds[module.path] = true
      end
    end
    for _, path in ipairs(load.toc_files()) do
      if not path:match("^Libs/") then
        assert.is_true(kinds[path] == true, path .. " is in no list")
        kinds[path] = nil
      end
    end
    assert.same({}, kinds)
  end)

  it("gives WoW globals in .luacheckrc to exactly the load.GLUE files", function()
    local env = { stds = {}, files = {}, ipairs = ipairs }
    local config = assert(loadfile(".luacheckrc"))
    setfenv(config, env)()
    local with_wow = {}
    for path, settings in pairs(env.files) do
      if settings.read_globals then
        with_wow[path] = true
      end
    end
    local glue = {}
    for _, module in ipairs(load.GLUE) do
      glue[module.path] = true
    end
    assert.same(glue, with_wow)
    assert.equal("pure", env.std)
  end)

  it("loads LibStub first and every vendored library before our code", function()
    local files = load.toc_files()
    assert.equal("Libs/LibStub/LibStub.lua", files[1])
    local vendored = {}
    for line in io.lines("Libs/MANIFEST.sha256") do
      local path = line:match("^%x+  (.+%.lua)$")
      if path then
        vendored[path] = true
      end
    end
    local seen_own = false
    for _, path in ipairs(files) do
      if path:match("^Libs/") then
        assert.is_false(seen_own, path .. " loads after our own code")
        vendored[path] = nil
      else
        seen_own = true
      end
    end
    assert.same({}, vendored)
  end)

  it("declares the SavedVariables and keeps the interface placeholder visible", function()
    local toc = io.open(load.TOC, "rb"):read("*a")
    assert.truthy(toc:find("\n## SavedVariables: InnkeepersLedgerDB", 1, true))
    assert.truthy(toc:find("PLACEHOLDER interface number", 1, true))
  end)
end)

describe("the whole AddOn under the WoW stub", function()
  local ns

  before_each(function()
    wow.install()
    ns = load.addon({})
    wow.fire("ADDON_LOADED", load.ADDON_NAME)
    wow.fire("PLAYER_LOGIN")
  end)

  after_each(wow.uninstall)

  it("loads and initializes with no errors", function()
    assert.same({}, wow.errors)
  end)

  it("registers every module on the shared ns", function()
    for _, list in ipairs({ load.PURE, load.GLUE }) do
      for _, module in ipairs(list) do
        assert.is_table(ns[module.name], module.name)
      end
    end
    for _, data in ipairs(load.DATA) do
      assert.is_table(ns.Data[data.name], data.name)
    end
  end)

  it("creates the SavedVariables through AceDB", function()
    assert.is_table(ns.Core.db)
    assert.is_table(_G.InnkeepersLedgerDB)
  end)

  it("answers /ledger with the version", function()
    wow.slash("/ledger")
    assert.equal(1, #wow.chat)
    assert.truthy(wow.chat[1]:find("version dev", 1, true))
  end)

  it("reports the packaged version when the packager has set one", function()
    wow.metadata.Version = "1.2.3"
    wow.slash("/LEDGER")
    assert.truthy(wow.chat[1]:find("version 1.2.3", 1, true))
  end)
end)
