-- THROWAWAY: proves CI fails on lint and test errors (#9). Reverted in the next commit.
local unused = 1
describe("ci", function()
  it("fails on purpose", function()
    assert.are.equal(1, 2)
  end)
end)
