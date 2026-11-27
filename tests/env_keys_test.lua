-- EnvKeys: pointing DEVELOPER_DIR at the selected Xcode.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

local install_path = "/Users/me/.local/share/mise/installs/xcode/27.2.0"

test("selects the Xcode the plugin linked when installing", function()
  local developer_dir = "/Applications/Xcode-27.2.0.app/Contents/Developer"
  local world = mac.new({
    apps = { ["/Applications/Xcode-27.2.0.app"] = { build = "27B52" } },
    paths = { [install_path] = { target = developer_dir } },
  })

  check.equal(world:hook("EnvKeys", { path = install_path }), { { key = "DEVELOPER_DIR", value = developer_dir } })
end)

-- `mise link xcode@27.2.0 /Applications/Xcode.app` links the app itself, and
-- Apple's tools accept an app as DEVELOPER_DIR.
test("selects an Xcode added with mise link", function()
  local world = mac.new({
    apps = { ["/Applications/Xcode.app"] = { build = "27B52" } },
    paths = { [install_path] = { target = "/Applications/Xcode.app" } },
  })

  check.equal(
    world:hook("EnvKeys", { path = install_path }),
    { { key = "DEVELOPER_DIR", value = "/Applications/Xcode.app" } }
  )
end)
