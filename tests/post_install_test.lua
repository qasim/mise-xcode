-- PostInstall and EnvKeys: linking mise's install folder to the selected
-- Xcode, and pointing DEVELOPER_DIR at it.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

local folder = "/Users/me/.local/share/mise/installs/xcode/27.2.0"
local developer_dir = "/Applications/Xcode-27.2.0.app/Contents/Developer"

local function world()
  return mac.new({
    releases = { "27.2.0+27B52" },
    apps = { ["/Applications/Xcode-27.2.0.app"] = { build = "27B52" } },
    -- mise makes the install folder before PostInstall runs.
    paths = { [folder] = "dir" },
  })
end

test("links mise's install folder to the selected Xcode", function()
  local w = world()

  w:hook("PostInstall", { sdkInfo = { xcode = { version = "27.2.0", path = folder } } })

  check.lines(w.transcript, { "$ ln -s " .. developer_dir .. " " .. folder })
  check.equal(w:hook("EnvKeys", { path = folder }), { { key = "DEVELOPER_DIR", value = developer_dir } })
end)

test("links a version written another way to the Xcode it means", function()
  local w = world()

  w:hook("PostInstall", { sdkInfo = { xcode = { version = "27.2", path = folder } } })

  check.lines(w.transcript, { "$ ln -s " .. developer_dir .. " " .. folder })
end)

test("points DEVELOPER_DIR at nothing until the folder is linked, so no other Xcode is used", function()
  local w = world()

  check.equal(
    w:hook("EnvKeys", { path = folder }),
    { { key = "DEVELOPER_DIR", value = folder .. "/Xcode-not-installed" } }
  )
end)
