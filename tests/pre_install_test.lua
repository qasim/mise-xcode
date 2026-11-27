-- PreInstall: selecting an Xcode that is installed, and downloading,
-- unpacking, checking and setting up one that is not.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

local cache = "/cache/xcode-downloads/27B52"
local installed = "/Applications/Xcode-27.2.0.app"

local function xcode_27_2(overrides)
  local release = { name = "27.2", build = "27B52", file = "Xcode_27.2.xip" }
  for key, value in pairs(overrides or {}) do
    release[key] = value
  end
  return release
end

-- What a download of Xcode 27.2 looks like once xcodes has the archive.
local unpack_and_set_up = {
  "> (2/3) Unpacking Xcode 27.2.0, which can take a few minutes",
  "$ xip --expand " .. cache .. "/Xcode_27.2.xip",
  "$ mv " .. cache .. "/expanded/Xcode.app " .. installed,
  "$ rm -rf " .. cache,
  "> (2/3) Installed Xcode 27.2.0 (27B52) at " .. installed,
  "> (3/3) Setting up Xcode 27.2.0: accepting the license and installing the packages Xcode asks for on first launch",
  "$ sudo xcodebuild -license accept",
  "$ sudo xcodebuild -runFirstLaunch",
  "$ sudo DevToolsSecurity -enable",
  "$ sudo dseditgroup -o edit -t group -a staff _developer",
  "> (3/3) Set up Xcode 27.2.0",
}

local function concat(...)
  local result = {}
  for _, list in ipairs({ ... }) do
    for _, item in ipairs(list) do
      table.insert(result, item)
    end
  end
  return result
end

test("selects an installed Xcode that is set up, and changes nothing", function()
  local world = mac.new({
    releases = { "27.2.0+27B52" },
    apps = { [installed] = { build = "27B52" } },
    xcodes = { saved = { xcode_27_2() } },
  })

  local result = world:hook("PreInstall", { version = "27.2.0" })

  check.equal(result, { version = "27.2.0", note = "Selected Xcode 27.2.0 (27B52)" })
  check.lines(world.transcript, {})
end)

test("downloads a missing Xcode with xcodes, then unpacks, checks and sets it up", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2() } } })

  local result = world:hook("PreInstall", { version = "27.2.0" })

  check.equal(result, { version = "27.2.0", note = "Installed Xcode 27.2.0 (27B52)" })
  check.lines(
    world.transcript,
    concat({
      "> (1/3) Downloading Xcode 27.2.0 (27B52) with xcodes",
      "$ xcodes download 27.2 --directory " .. cache,
    }, unpack_and_set_up)
  )
end)

test("refreshes xcodes' list when it does not have the release yet", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = {}, current = { xcode_27_2() } } })

  world:hook("PreInstall", { version = "27.2.0" })

  check.lines(
    world.transcript,
    concat({
      "$ xcodes update",
      "> (1/3) Downloading Xcode 27.2.0 (27B52) with xcodes",
      "$ xcodes download 27.2 --directory " .. cache,
    }, unpack_and_set_up)
  )
end)

test("downloads from Apple's list a release xcodereleases.com does not list yet, then restores xcodes' list", function()
  local beta_cache = "/cache/xcode-downloads/27C5035i"
  local world = mac.new({
    releases = { "27.3.0-beta.2+27C5035i" },
    xcodes = { saved = {}, apple = { { name = "27.3.0 Beta 2", build = "27C5035i", file = "Xcode_27.3_beta_2.aea" } } },
  })

  world:hook("PreInstall", { version = "27.3.0-beta.2" })

  check.lines(world.transcript, {
    "$ xcodes update",
    "> (1/3) Downloading Xcode 27.3.0-beta.2 (27C5035i) with xcodes, from Apple's list, as xcodereleases.com does not list it yet",
    '$ xcodes download "27.3.0 Beta 2" --data-source apple --directory ' .. beta_cache,
    "$ xcodes update",
    "> (2/3) Unpacking Xcode 27.3.0-beta.2, which can take a few minutes",
    "$ archiveutil extractXcodeAEA " .. beta_cache .. "/Xcode_27.3_beta_2.aea",
    "$ mv " .. beta_cache .. "/expanded/Xcode.app /Applications/Xcode-27.3.0-beta.2.app",
    "$ rm -rf " .. beta_cache,
    "> (2/3) Installed Xcode 27.3.0-beta.2 (27C5035i) at /Applications/Xcode-27.3.0-beta.2.app",
    "> (3/3) Setting up Xcode 27.3.0-beta.2: accepting the license and installing the packages Xcode asks for on first launch",
    "$ sudo xcodebuild -license accept",
    "$ sudo xcodebuild -runFirstLaunch",
    "$ sudo DevToolsSecurity -enable",
    "$ sudo dseditgroup -o edit -t group -a staff _developer",
    "> (3/3) Set up Xcode 27.3.0-beta.2",
  })
end)

test("refuses a download whose build is not the one asked for, and deletes it", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2({ downloads = "27B50" }) } } })

  check.fails(function()
    world:hook("PreInstall", { version = "27.2.0" })
  end, "Did not install Xcode 27.2.0 (27B52): the download is build 27B50.")

  check.equal(world:exists(installed), false, "Nothing should be installed")
  check.equal(world.transcript[#world.transcript], "$ rm -rf " .. cache)
end)

test("refuses a download that is not signed by Apple", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2({ team = "OTHERTEAM1" }) } } })

  check.fails(function()
    world:hook("PreInstall", { version = "27.2.0" })
  end, "Did not install Xcode 27.2.0 (27B52): it is not signed by Apple.")
  check.equal(world:exists(installed), false, "Nothing should be installed")
end)

test("refuses a download changed after Apple signed it", function()
  local world =
    mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2({ signature = "broken" }) } } })

  check.fails(function()
    world:hook("PreInstall", { version = "27.2.0" })
  end, "Did not install Xcode 27.2.0 (27B52): it is not signed by Apple.")
  check.equal(world:exists(installed), false, "Nothing should be installed")
end)

test("reuses an archive an earlier attempt downloaded", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2() } } })
  world.paths[cache] = "dir"
  world.archives[cache .. "/Xcode_27.2.xip"] = { build = "27B52" }

  world:hook("PreInstall", { version = "27.2.0" })

  check.lines(world.transcript, concat({ "> (1/3) Xcode 27.2.0 (27B52) is already downloaded" }, unpack_and_set_up))
end)

test("stops before downloading when it can't write to the install folder", function()
  local world = mac.new({
    releases = { "27.2.0+27B52" },
    xcodes = { saved = { xcode_27_2() } },
    read_only = { "/Applications" },
  })

  check.fails(
    function()
      world:hook("PreInstall", { version = "27.2.0" })
    end,
    "Cannot install Xcode 27.2.0 (27B52): you cannot write to /Applications.\nSet the install_dir option to a folder you can write to."
  )
  check.lines(world.transcript, {})
end)

test("stops before downloading when something is already where Xcode would go", function()
  local world = mac.new({
    releases = { "27.2.0+27B52" },
    xcodes = { saved = { xcode_27_2() } },
    paths = { [installed] = "dir" },
  })

  check.fails(function()
    world:hook("PreInstall", { version = "27.2.0" })
  end, "Cannot install Xcode 27.2.0 (27B52): " .. installed .. " already exists.\nMove it, then try again.")
  check.lines(world.transcript, {})
end)

test("explains how to sign in when xcodes needs it and no one can answer", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2() }, signed_in = false } })

  check.fails(
    function()
      world:hook("PreInstall", { version = "27.2.0" })
    end,
    "Couldn't download Xcode 27.2.0. xcodes needs to sign in to your Apple ID, and it can't ask you for it here.\nTo sign in, either:\n- run `mise install` in a terminal, or\n- set XCODES_USERNAME and XCODES_PASSWORD, or\n- set FASTLANE_SESSION to a session from `fastlane spaceauth`."
  )
end)

test("says only that the download failed when it wasn't for a sign-in", function()
  local world = mac.new({ releases = { "27.2.0+27B52" }, xcodes = { saved = { xcode_27_2({ fails = true }) } } })

  local message = check.fails(function()
    world:hook("PreInstall", { version = "27.2.0" })
  end, "Failed to download Xcode 27.2.0 (27B52) with xcodes.")
  check.equal(message, "Failed to download Xcode 27.2.0 (27B52) with xcodes.")
end)

test("lets the user sign in when xcodes needs it in a terminal", function()
  local world = mac.new({
    releases = { "27.2.0+27B52" },
    xcodes = { saved = { xcode_27_2() }, signed_in = false },
    terminal = true,
  })

  world:hook("PreInstall", { version = "27.2.0" })

  check.lines(
    world.transcript,
    concat({
      "> (1/3) Downloading Xcode 27.2.0 (27B52) with xcodes",
      "$ xcodes download 27.2 --directory " .. cache,
      "$ xcodes download 27.2 --directory " .. cache,
      "(signs in to Apple)",
    }, unpack_and_set_up)
  )
end)

test("without xcodes, says where to download a missing Xcode", function()
  local world = mac.new({
    releases = {
      {
        version = "27.2.0",
        build = "27B52",
        url = "https://download.developer.apple.com/Developer_Tools/Xcode_27.2/Xcode_27.2.xip",
      },
    },
  })

  check.fails(
    function()
      world:hook("PreInstall", { version = "27.2.0" })
    end,
    "No Xcode 27.2.0 (27B52) found in the search path.\nDownload it from https://download.developer.apple.com/Developer_Tools/Xcode_27.2/Xcode_27.2.xip, or add xcodes to [tools] so mise can download it before installation."
  )
  check.lines(world.transcript, {})
end)

test("with install = false, neither downloads nor sets up", function()
  local world = mac.new({
    releases = { "27.2.0+27B52" },
    apps = { [installed] = { build = "27B52", set_up = false } },
    xcodes = { saved = { xcode_27_2() } },
  })

  local result = world:hook("PreInstall", { version = "27.2.0", options = { install = false } })

  check.equal(result.note, "Selected Xcode 27.2.0 (27B52)")
  check.lines(world.transcript, {})
end)

test("signs xcodes in with fastlane's session when FASTLANE_SESSION is set", function()
  local world = mac.new({
    releases = { "27.2.0+27B52" },
    xcodes = { saved = { xcode_27_2() }, signed_in = false },
    env = { FASTLANE_SESSION = "---\n- !ruby/object:HTTP::Cookie" },
  })

  world:hook("PreInstall", { version = "27.2.0" })

  check.lines(
    world.transcript,
    concat({
      "> (1/3) Downloading Xcode 27.2.0 (27B52) with xcodes",
      "$ xcodes download 27.2 --use-fastlane-auth --directory " .. cache,
    }, unpack_and_set_up)
  )
end)
