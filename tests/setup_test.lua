-- Setting up an installed Xcode, and downloading the simulators and
-- components a project asks for.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

local app = "/Applications/Xcode-27.2.0.app"

local function world(overrides)
  local description = {
    releases = { "27.2.0+27B52" },
    apps = {
      [app] = {
        build = "27B52",
        sdks = { iphoneos = { version = "27.2", runtime = "23C54" } },
        components = { metalToolchain = { build = "17C48" } },
      },
    },
  }
  for key, value in pairs(overrides or {}) do
    description[key] = value
  end
  return mac.new(description)
end

local function setup_lines(step, asks)
  return {
    "> "
      .. step
      .. "Setting up Xcode 27.2.0: accepting the license and installing the packages Xcode asks for on first launch"
      .. (asks and ", which needs your administrator password" or ""),
    "$ sudo xcodebuild -license accept",
    "$ sudo xcodebuild -runFirstLaunch",
    "$ sudo DevToolsSecurity -enable",
    "$ sudo dseditgroup -o edit -t group -a staff _developer",
    "> " .. step .. "Set up Xcode 27.2.0",
  }
end

test("sets up an installed Xcode that isn't set up yet", function()
  local w = world()
  w.apps[app].set_up = false

  w:hook("PreInstall", { version = "27.2.0" })

  check.lines(w.transcript, setup_lines("(1/1) ", false))
end)

test("asks for the administrator password in a terminal when sudo needs it", function()
  local w = world({ sudo_cached = false, terminal = true })
  w.apps[app].set_up = false

  w:hook("PreInstall", { version = "27.2.0" })

  check.lines(w.transcript, setup_lines("(1/1) ", true))
end)

test("explains that setup needs a terminal for the password when there isn't one", function()
  local w = world({ sudo_cached = false })
  w.apps[app].set_up = false

  check.fails(
    function()
      w:hook("PreInstall", { version = "27.2.0" })
    end,
    "Xcode 27.2.0 needs an administrator password to finish setting up.\nRun `mise install` in a terminal, which asks for it once."
  )
  check.equal(w.apps[app].set_up, false, "Xcode should not be set up")
end)

test("downloads the simulator that matches Xcode's SDK", function()
  local w = world()

  w:hook("PreInstall", { version = "27.2.0", options = { platforms = { "iOS" } } })

  check.lines(w.transcript, {
    "> (1/1) Downloading iOS 27.2 Simulator",
    "$ xcodebuild -downloadPlatform iOS",
    "> (1/1) Installed iOS 27.2 Simulator",
  })
end)

test("skips a simulator that's already installed", function()
  local w = world({ runtimes = { { platform = "iOS", version = "27.2", build = "23C54" } } })

  w:hook("PreInstall", { version = "27.2.0", options = { platforms = "iOS" } })

  check.lines(w.transcript, { "> (1/1) iOS 27.2 Simulator is already installed (23C54)" })
end)

test("downloads an older simulator asked for by version", function()
  local w = world()

  w:hook("PreInstall", { version = "27.2.0", options = { platforms = { "iOS@26.0" } } })

  check.lines(w.transcript, {
    "> (1/1) Downloading iOS 26.0 Simulator",
    "$ xcodebuild -downloadPlatform iOS -buildVersion 26.0",
    "> (1/1) Installed iOS 26.0 Simulator",
  })
end)

test("refuses a simulator newer than the Xcode supports", function()
  local w = world()

  check.fails(function()
    w:hook("PreInstall", { version = "27.2.0", options = { platforms = { "iOS@27.3" } } })
  end, "Cannot use iOS 27.3 Simulator with Xcode 27.2.0, whose newest is iOS 27.2.")
end)

test("downloads a component, and skips it once it's installed", function()
  local w = world()

  w:hook("PreInstall", { version = "27.2.0", options = { components = { "metalToolchain" } } })
  w:hook("PreInstall", { version = "27.2.0", options = { components = { "metalToolchain" } } })

  check.lines(w.transcript, {
    "> (1/1) Downloading Metal Toolchain (17C48)",
    "$ xcodebuild -downloadComponent metalToolchain",
    "> (1/1) Installed Metal Toolchain (17C48)",
    "> (1/1) Metal Toolchain is already installed (17C48)",
  })
end)

test("numbers every step when several are asked for", function()
  local w = world()
  w.apps[app].set_up = false

  w:hook("PreInstall", { version = "27.2.0", options = { platforms = "iOS", components = "metalToolchain" } })

  local expected = setup_lines("(1/3) ", false)
  for _, text in ipairs({
    "> (2/3) Downloading iOS 27.2 Simulator",
    "$ xcodebuild -downloadPlatform iOS",
    "> (2/3) Installed iOS 27.2 Simulator",
    "> (3/3) Downloading Metal Toolchain (17C48)",
    "$ xcodebuild -downloadComponent metalToolchain",
    "> (3/3) Installed Metal Toolchain (17C48)",
  }) do
    table.insert(expected, text)
  end
  check.lines(w.transcript, expected)
end)
