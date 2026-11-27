-- Which Xcode a version means. mise matches prefixes such as "27" itself and
-- passes the plugin the version it chose; other spellings reach the plugin as
-- written, and mean the one version they unambiguously name.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

local xcodes = {
  ["27.3.0-beta.2+27C5035i"] = "/Applications/Xcode-27.3-beta-2.app",
  ["27.3.0-beta+27C5020n"] = "/Applications/Xcode-27.3-beta.app",
  ["27.2.0+27B52"] = "/Applications/Xcode-27.2.app",
  ["27.2.0-rc+27B48"] = "/Applications/Xcode-27.2-rc.app",
  ["11.5.0-gm-seed+11E608c"] = "/Applications/Xcode-11.5-gm-seed.app",
  ["11.0.0-gm-seed.2+11A420a"] = "/Applications/Xcode-11-gm-seed-2.app",
}

local function world()
  local tags, apps = {}, {}
  for tag, path in pairs(xcodes) do
    table.insert(tags, tag)
    apps[path] = { build = tag:match("%+(.+)$") }
  end
  return mac.new({ tags = tags, apps = apps })
end

local spellings = {
  -- Exactly as tagged.
  { "27.2.0", "27.2.0", "27B52" },
  { "27.2.0-rc", "27.2.0-rc", "27B48" },
  { "27.3.0-beta.2", "27.3.0-beta.2", "27C5035i" },
  -- A first pre-release numbered 1.
  { "27.2.0-rc.1", "27.2.0-rc", "27B48" },
  { "27.3.0-beta.1", "27.3.0-beta", "27C5020n" },
  { "11.5.0-gm-seed.1", "11.5.0-gm-seed", "11E608c" },
  -- The version number without its last zeros, as xcodereleases.com writes it.
  { "27.2-rc", "27.2.0-rc", "27B48" },
  { "27.2-rc.1", "27.2.0-rc", "27B48" },
  { "27.3-beta.2", "27.3.0-beta.2", "27C5035i" },
  { "11-gm-seed.2", "11.0.0-gm-seed.2", "11A420a" },
  -- GM seeds were tagged "-seed" before they were "-gm-seed".
  { "11.5.0-seed", "11.5.0-gm-seed", "11E608c" },
  { "11.0.0-seed.2", "11.0.0-gm-seed.2", "11A420a" },
}

for _, case in ipairs(spellings) do
  local written, version, build = case[1], case[2], case[3]
  test(written .. " selects Xcode " .. version .. " (" .. build .. ")", function()
    local result = world():hook("PreInstall", { version = written })
    check.equal(result, { version = version, note = "Selected Xcode " .. version .. " (" .. build .. ")" })
  end)
end

for _, written in ipairs({ "27.2.0-rc.0", "27.2.0-alpha", "27.2.0.1", "27.2.0-rc-1", "27[", "26.0+" }) do
  test(written .. " matches no Xcode", function()
    check.fails(function()
      world():hook("PreInstall", { version = written })
    end, "No Xcode release matches version " .. written .. ".")
  end)
end

-- xcodes finds a release in Apple's list by the name Apple gives it, which it
-- reads as "27.3.0 Beta 2", so the plugin asks for releases by those names.
local apple_names = {
  { "27.2.0", "27.2.0" },
  { "27.3.0-beta", "27.3.0 Beta" },
  { "27.3.0-beta.2", "27.3.0 Beta 2" },
  { "27.2.0-rc", "27.2.0 Release Candidate" },
  { "26.3.0-rc.2", "26.3.0 Release Candidate 2" },
  { "11.5.0-gm-seed", "11.5.0 GM Seed" },
  { "11.0.0-gm-seed.2", "11.0.0 GM Seed 2" },
}

for _, case in ipairs(apple_names) do
  test(case[1] .. " is " .. case[2] .. " in Apple's list", function()
    mac.new()
    check.equal(require("install").apple_name(case[1]), case[2])
  end)
end
