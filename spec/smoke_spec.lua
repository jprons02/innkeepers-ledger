local load = require("helpers.load")
local wow = require("helpers.wow_stub")

local PURE, DATA = load.PURE, load.DATA

describe("pure modules", function()
  it("run with no WoW API defined", function()
    assert.is_nil(rawget(_G, "CreateFrame"))
    assert.is_nil(rawget(_G, "LibStub"))
  end)

  for _, module in ipairs(PURE) do
    it(module.path .. " loads in plain Lua and registers ns." .. module.name, function()
      local ns = load.file(module.path, {}, load.pure_env())
      assert.is_table(ns[module.name])
    end)
  end

  for _, data in ipairs(DATA) do
    it(data.path .. " loads in plain Lua and registers ns.Data." .. data.name, function()
      local ns = load.file(data.path, {}, load.pure_env())
      assert.is_table(ns.Data[data.name])
    end)
  end

  it("each load gets its own ns", function()
    local a = load.file("Ledger.lua", {}, load.pure_env())
    local b = load.file("Ledger.lua", {}, load.pure_env())
    assert.are_not.equal(a.Ledger, b.Ledger)
  end)

  it("the pure environment rejects WoW globals", function()
    local env = load.pure_env()
    assert.has_error(function() return env.GetServerTime end)
    assert.has_error(function() env.Leaked = true end)
  end)
end)

describe("wow stub", function()
  after_each(wow.uninstall)

  it("installs, takes overrides and uninstalls cleanly", function()
    wow.install({ IsResting = function() return true end })
    assert.is_true(_G.IsResting())
    assert.equal(1800000000, _G.GetServerTime())
    _G.SomeLibraryGlobal = {}

    wow.uninstall()
    assert.is_nil(rawget(_G, "IsResting"))
    assert.is_nil(rawget(_G, "SomeLibraryGlobal"))
    assert.is_function(rawget(_G, "print"))
  end)

  it("delivers events to registered frames only", function()
    wow.install()
    local seen = {}
    local on = _G.CreateFrame("Frame")
    on:RegisterEvent("PLAYER_LOGIN")
    on:SetScript("OnEvent", function(_, event) seen[#seen + 1] = event end)
    local off = _G.CreateFrame("Frame")
    off:SetScript("OnEvent", function() error("not registered") end)

    wow.fire("PLAYER_LOGIN")
    assert.same({ "PLAYER_LOGIN" }, seen)
  end)
end)
