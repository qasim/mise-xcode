-- .xcode-version files, which xcodes and fastlane read. A version in one is
-- exact, as xcodes reads it: "26" is 26.0.0, not the newest Xcode 26.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

local function read(content)
  local world = mac.new({ files = { ["/project/.xcode-version"] = content } })
  return world:hook("ParseLegacyFile", { filepath = "/project/.xcode-version" }).version
end

local contents = {
  -- As xcodes and fastlane write it.
  { "26", "26.0.0" },
  { "26.0", "26.0.0" },
  { "16.4", "16.4.0" },
  { "26.0.1", "26.0.1" },
  { "14.0b6", "14.0.0-beta.6" },
  { "14.0b1", "14.0.0-beta" },
  { "9.2b", "9.2.0-beta" },
  -- As Apple writes it.
  { "14.0 Beta 6", "14.0.0-beta.6" },
  { "Xcode 14.0 Beta 6", "14.0.0-beta.6" },
  { "27.2 Release Candidate", "27.2.0-rc" },
  { "26.3 Release Candidate 2", "26.3.0-rc.2" },
  { "11.5 GM Seed", "11.5.0-gm-seed" },
  -- As the plugin's versions are written.
  { "27.2.0-rc", "27.2.0-rc" },
  { "27.2-rc.1", "27.2.0-rc" },
  { "11.5.0-seed", "11.5.0-gm-seed" },
  -- Only the version, without the space or newline around it.
  { "  27.2\n", "27.2.0" },
}

for _, case in ipairs(contents) do
  test(string.format("%q means %s", case[1], case[2]), function()
    check.equal(read(case[1]), case[2])
  end)
end

-- mise ignores errors from ParseLegacyFile, so anything else is passed on as
-- written, and installing it fails where people see why. mise splits what it
-- gets at spaces, so they are removed.
test("passes on a version it can't read, for installing to reject", function()
  check.equal(read("the newest one\n"), "thenewestone")
end)
