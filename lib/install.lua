-- Installs a missing Xcode and prepares Xcodes for command-line use.
--
-- Downloading is delegated to xcodes (https://github.com/XcodesOrg/xcodes) when
-- it is available, so its saved Apple ID session is reused. Everything after
-- the download (unpacking, verification, first-launch setup and extra
-- components) is handled here.

local command = require("command")
local json = require("json")
local system = require("system")
local util = require("util")

local trim, split_lines = util.trim, util.split_lines

local install = {}

-- Xcode is signed by Apple as com.apple.dt.Xcode.
local xcode_requirement = '=anchor apple and identifier "com.apple.dt.Xcode"'

-- Tells the user what is happening during steps that take a while.
local function say(message)
  print(message)
end

-- Numbers the steps of an install, such as "(2/5) ", so people can see how
-- far along it is. Every planned step gets a number, even one that turns out
-- to be done already.
function install.new_steps(total)
  return { current = 0, total = total }
end

local function next_step(steps)
  steps.current = steps.current + 1
  return "(" .. steps.current .. "/" .. steps.total .. ") "
end

local function this_step(steps)
  return "(" .. steps.current .. "/" .. steps.total .. ") "
end

-- Tool options may arrive as booleans, strings, lists or newline-joined strings.
local function option_list(value)
  local result = {}
  if type(value) == "table" then
    for _, item in ipairs(value) do
      for _, part in ipairs(option_list(item)) do
        table.insert(result, part)
      end
    end
  elseif value ~= nil then
    for part in tostring(value):gmatch("[^,%s]+") do
      table.insert(result, part)
    end
  end
  return result
end

function install.option_enabled(value, default)
  if value == nil then
    return default
  end
  if type(value) == "boolean" then
    return value
  end
  local normalized = trim(value):lower()
  return not (normalized == "false" or normalized == "0" or normalized == "no" or normalized == "off")
end

-- A command run with DEVELOPER_DIR set to the given Xcode.
local function with_developer_dir(developer_dir, words)
  local result = { "/usr/bin/env", "DEVELOPER_DIR=" .. developer_dir }
  for _, word in ipairs(words) do
    table.insert(result, word)
  end
  return result
end

-- Downloads are kept in mise's cache folder, so `mise cache clear` removes leftovers.
local function cache_directory(build)
  local base = os.getenv("MISE_CACHE_DIR")
  if base == nil or base == "" then
    local xdg = os.getenv("XDG_CACHE_HOME")
    if xdg == nil or xdg == "" then
      xdg = (os.getenv("HOME") or "") .. "/Library/Caches"
    end
    base = xdg .. "/mise"
  end
  return base .. "/xcode-downloads/" .. build
end

-- Returns the path of a working xcodes executable, or nil.
function install.xcodes_path()
  local ok, output = pcall(command.output, { "command", "-v", "xcodes" }, { timeout = 10 })
  if not ok then
    return nil
  end
  local path = trim(output)
  if path == "" then
    return nil
  end
  -- A mise shim without a selected version exists on PATH but cannot run.
  if not command.succeeds({ path, "version" }, { timeout = 30 }) then
    return nil
  end
  return path
end

-- xcodes names releases after Apple ("27.0 Beta 3"), not semver, so the
-- release is looked up by its build number instead of translating versions.
local function xcodes_name_for_build(xcodes_path, build)
  local output = command.output({ xcodes_path, "list", "--no-color" }, { timeout = 120 })
  for _, line in ipairs(split_lines(output)) do
    local name, line_build = line:match("^(.-)%s+%(([%w]+)%)")
    if name ~= nil and line_build == build then
      return trim(name)
    end
  end
  return nil
end

-- Refreshes the list xcodes keeps from xcodereleases.com, which needs no
-- sign-in. Returns whether it worked.
local function update_xcodes_list(xcodes_path)
  return command.succeeds({ xcodes_path, "update", "--no-color" }, { timeout = 120 })
end

-- Names a version the way Apple's list does, which xcodes matches versions
-- against, such as "27.3.0 Beta 2" for "27.3.0-beta.2".
local apple_labels = { beta = "Beta", rc = "Release Candidate", ["gm-seed"] = "GM Seed" }

function install.apple_name(version)
  local number, label, count = version:match("^([%d%.]+)%-?([%a%-]*)%.?(%d*)$")
  if number == nil or (label ~= "" and apple_labels[label] == nil) then
    return nil
  end
  local name = number
  if label ~= "" then
    name = name .. " " .. apple_labels[label]
    if count ~= "" then
      name = name .. " " .. count
    end
  end
  return name
end

local function find_archive(directory)
  local ok, output = pcall(command.output, { "ls", "-1", directory }, { timeout = 10 })
  if not ok then
    return nil
  end
  local names = {}
  for _, name in ipairs(split_lines(output)) do
    names[name] = true
  end
  for _, name in ipairs(split_lines(output)) do
    local lowered = name:lower()
    -- A .aria2 file next to the archive means xcodes has not finished it.
    local complete = names[name .. ".aria2"] == nil
    if complete and (lowered:match("%.xip$") or lowered:match("%.aea$")) then
      return directory .. "/" .. name
    end
  end
  return nil
end

local function download_with_xcodes(xcodes_path, version, build, directory, steps)
  -- The list xcodes keeps can be older than the release.
  local name = xcodes_name_for_build(xcodes_path, build)
  if name == nil and update_xcodes_list(xcodes_path) then
    name = xcodes_name_for_build(xcodes_path, build)
  end

  -- A release xcodereleases.com does not list yet is downloaded from Apple's
  -- own list, which has every release Apple publishes but no builds, so it is
  -- found by its version. verify_bundle checks its build afterwards.
  local from_apple = false
  if name == nil then
    name = install.apple_name(version)
    if name == nil then
      error("xcodes does not list Xcode " .. version .. " (" .. build .. ").", 0)
    end
    from_apple = true
  end

  say(
    this_step(steps)
      .. "Downloading Xcode "
      .. version
      .. " ("
      .. build
      .. ") with xcodes"
      .. (from_apple and ", from Apple's list, as xcodereleases.com does not list it yet" or "")
  )
  local download = { xcodes_path, "download", name }
  if from_apple then
    table.insert(download, "--data-source")
    table.insert(download, "apple")
  end
  -- A session from `fastlane spaceauth` lets xcodes sign in without a prompt,
  -- such as in CI.
  local fastlane_session = os.getenv("FASTLANE_SESSION")
  if fastlane_session ~= nil and fastlane_session ~= "" then
    table.insert(download, "--use-fastlane-auth")
  end
  for _, word in ipairs({ "--directory", directory, "--no-color" }) do
    table.insert(download, word)
  end

  -- xcodes runs in a pseudo-terminal so it reports progress as it goes, with
  -- no input so the user's terminal is left alone.
  local label = "Downloading Xcode " .. version
  local code = command.with_progress(download, label, this_step(steps), { pty = true })
  local wants_sign_in = code == command.wants_sign_in and not command.has_terminal()
  if code == command.wants_sign_in and command.has_terminal() then
    -- Signing in needs the terminal, so xcodes runs again attached to it.
    -- mise's progress display stays frozen while the terminal is handed over.
    code = command.with_progress(download, label, this_step(steps), { pty = true, terminal = true })
  end
  if from_apple then
    -- xcodes keeps one list, which Apple's replaced, so it is set back to the
    -- one from xcodereleases.com, with builds.
    update_xcodes_list(xcodes_path)
  end
  if wants_sign_in then
    error(
      "Couldn't download Xcode "
        .. version
        .. ". xcodes needs to sign in to your Apple ID, and it can't ask you for it here."
        .. "\nTo sign in, either:"
        .. "\n- run `mise install` in a terminal, or"
        .. "\n- set XCODES_USERNAME and XCODES_PASSWORD, or"
        .. "\n- set FASTLANE_SESSION to a session from `fastlane spaceauth`.",
      0
    )
  end
  if code ~= 0 then
    error("Failed to download Xcode " .. version .. " (" .. build .. ") with xcodes.", 0)
  end

  local archive = find_archive(directory)
  if archive == nil then
    error("xcodes reported success, but no Xcode archive is in " .. directory .. ".", 0)
  end
  return archive
end

local function plist_value(path, key)
  local ok, output = pcall(
    command.output,
    { "/usr/libexec/PlistBuddy", "-c", "Print :" .. key, path },
    { timeout = 10 }
  )
  return ok and trim(output) or nil
end

local function bundle_identifier(bundle_path)
  return plist_value(bundle_path .. "/Contents/Info.plist", "CFBundleIdentifier")
end

local function bundle_build(bundle_path)
  return plist_value(bundle_path .. "/Contents/version.plist", "ProductBuildVersion")
end

local function unpack_archive(archive, directory, version, steps)
  command.output({ "rm", "-rf", directory })
  command.output({ "mkdir", "-p", directory })

  local unpack
  if archive:lower():match("%.aea$") then
    if not command.succeeds({ "test", "-x", system.archiveutil }) then
      error("Failed to unpack " .. archive .. ": this version of macOS does not have archiveutil.", 0)
    end
    unpack = { system.archiveutil, "extractXcodeAEA", archive }
  else
    -- xip does not check the archive's signature; verify_bundle checks the app.
    unpack = { system.xip, "--expand", archive }
  end

  say(next_step(steps) .. "Unpacking Xcode " .. version .. ", which can take a few minutes")
  -- The plugin's own lines cover what xip prints, which is shown only on failure.
  local code, details = command.result(unpack, { cwd = directory })
  if code ~= 0 then
    error("Failed to unpack " .. archive .. ". The archive may be damaged, or the disk may be full.\n" .. details, 0)
  end

  local contents = command.output({ "ls", "-1", directory })
  for _, name in ipairs(split_lines(contents)) do
    local candidate = directory .. "/" .. name
    if name:match("%.app$") and bundle_identifier(candidate) == "com.apple.dt.Xcode" then
      return candidate
    end
  end
  error("Failed to unpack " .. archive .. ": it does not contain an Xcode app.", 0)
end

local function verify_bundle(bundle_path, version, build)
  local refused = "Did not install Xcode " .. version .. " (" .. build .. "): "
  local actual_build = bundle_build(bundle_path)
  if actual_build ~= build then
    error(refused .. "the download is build " .. tostring(actual_build) .. ".", 0)
  end

  -- Checking the signature, not just who signed it, also catches an app that
  -- was changed after it was signed. It takes about 15 seconds.
  if not command.succeeds({ system.codesign, "--verify", "--strict", "-R", xcode_requirement, bundle_path }) then
    error(refused .. "it is not signed by Apple.", 0)
  end

  if not command.succeeds({ system.spctl, "--assess", "--type", "execute", bundle_path }) then
    error(refused .. "Gatekeeper rejected it.", 0)
  end
end

-- Downloads, verifies and installs Xcode as two steps. Returns the installed
-- app's path.
function install.install_xcode(version, build, install_dir, steps)
  local xcodes_path = install.xcodes_path()
  if xcodes_path == nil then
    return nil
  end

  local destination = install_dir .. "/Xcode-" .. version .. ".app"
  if command.succeeds({ "test", "-e", destination }) then
    error(
      "Cannot install Xcode "
        .. version
        .. " ("
        .. build
        .. "): "
        .. destination
        .. " already exists.\nMove it, then try again.",
      0
    )
  end

  -- Checked before downloading, which takes much longer than this.
  if not (command.succeeds({ "mkdir", "-p", install_dir }) and command.succeeds({ "test", "-w", install_dir })) then
    error(
      "Cannot install Xcode "
        .. version
        .. " ("
        .. build
        .. "): you cannot write to "
        .. install_dir
        .. ".\nSet the install_dir option to a folder you can write to.",
      0
    )
  end

  local directory = cache_directory(build)
  command.output({ "mkdir", "-p", directory })

  -- An archive left by an earlier attempt that failed after downloading is reused.
  local archive = find_archive(directory)
  if archive ~= nil then
    say(next_step(steps) .. "Xcode " .. version .. " (" .. build .. ") is already downloaded")
  else
    next_step(steps)
    archive = download_with_xcodes(xcodes_path, version, build, directory, steps)
  end
  local ok, bundle_path = pcall(function()
    local path = unpack_archive(archive, directory .. "/expanded", version, steps)
    verify_bundle(path, version, build)
    return path
  end)
  if not ok then
    -- A damaged or wrong archive would otherwise be reused on the next try.
    command.output({ "rm", "-rf", directory })
    error(bundle_path, 0)
  end

  if not command.succeeds({ "mv", bundle_path, destination }) then
    error(
      "Failed to move Xcode "
        .. version
        .. " into "
        .. install_dir
        .. ".\nSet the install_dir option to a folder you can write to.",
      0
    )
  end

  command.output({ "rm", "-rf", directory })
  say(this_step(steps) .. "Installed Xcode " .. version .. " (" .. build .. ") at " .. destination)
  return destination
end

local function first_launch_complete(developer_dir)
  return command.succeeds(with_developer_dir(developer_dir, { system.xcodebuild, "-checkFirstLaunchStatus" }))
end

function install.needs_setup(developer_dir)
  return not first_launch_complete(developer_dir)
end

-- Does what Xcode asks for the first time it opens, so its tools work from
-- the command line without opening it: accepts the license, installs its
-- first-launch packages, and turns on developer mode, so debugging doesn't
-- ask for a password. Each step needs an administrator, as it does in Xcode.
local function run_first_launch(developer_dir, version, steps)
  local script = command.script({
    with_developer_dir(developer_dir, { system.xcodebuild, "-license", "accept" }),
    with_developer_dir(developer_dir, { system.xcodebuild, "-runFirstLaunch" }),
    { system.devtoolssecurity, "-enable" },
    { system.dseditgroup, "-o", "edit", "-t", "group", "-a", "staff", "_developer" },
  })
  local password_cached = command.succeeds({ system.sudo, "-n", "true" })
  if not password_cached and not command.has_terminal() then
    error(
      "Xcode "
        .. version
        .. " needs an administrator password to finish setting up."
        .. "\nRun `mise install` in a terminal, which asks for it once.",
      0
    )
  end

  say(
    next_step(steps)
      .. "Setting up Xcode "
      .. version
      .. ": accepting the license and installing the packages Xcode asks for on first launch"
      .. (password_cached and "" or ", which needs your administrator password")
  )
  -- The steps run in one sudo, which asks for the password at most once.
  -- -n makes sudo fail instead of asking, should the saved password expire
  -- before this runs without a terminal.
  local code
  if password_cached then
    code =
      command.with_progress({ system.sudo, "-n", "/bin/sh", "-c", script }, "Installing packages", this_step(steps))
  else
    code = command.with_progress(
      { system.sudo, "/bin/sh", "-c", script },
      "Installing packages",
      this_step(steps),
      { terminal = true }
    )
  end
  if code ~= 0 then
    -- sudo and the setup commands print why above.
    error("Failed to set up Xcode " .. version .. ".\nRun `mise install` to try again.", 0)
  end
  say(this_step(steps) .. "Set up Xcode " .. version)
end

-- Marks the Xcode build as checked so Xcode does not offer to install
-- components when it first opens. This mirrors what xcodes does.
local function mark_install_checked(bundle_path)
  local build = bundle_build(bundle_path)
  if build == nil then
    return
  end
  pcall(function()
    local cache = trim(command.output({ system.getconf, "DARWIN_USER_CACHE_DIR" }, { timeout = 10 }))
    local macos_build = trim(command.output({ system.sw_vers, "-buildVersion" }, { timeout = 10 }))
    command.output(
      { "touch", cache .. "com.apple.dt.Xcode.InstallCheckCache_" .. macos_build .. "_" .. build },
      { timeout = 10 }
    )
  end)
end

-- Simulator platforms by their -downloadPlatform name: the SDK name and
-- simulator platform simctl uses for them, and how to describe them.
local platforms = {
  ios = { sdk = "iphoneos", simulator = "com.apple.platform.iphonesimulator", name = "iOS" },
  watchos = { sdk = "watchos", simulator = "com.apple.platform.watchsimulator", name = "watchOS" },
  tvos = { sdk = "appletvos", simulator = "com.apple.platform.appletvsimulator", name = "tvOS" },
  visionos = { sdk = "xros", simulator = "com.apple.platform.xrsimulator", name = "visionOS" },
}

local function simctl_json(developer_dir, words)
  local simctl = { system.xcrun, "simctl", "runtime" }
  for _, word in ipairs(words) do
    table.insert(simctl, word)
  end
  return json.decode(command.output(with_developer_dir(developer_dir, simctl), { timeout = 60 }))
end

local function installed_runtimes(developer_dir)
  return simctl_json(developer_dir, { "list", "-j" })
end

-- Returns the build of the ready runtime with exactly this version, such as
-- "26.0", or nil.
local function runtime_build_for_version(developer_dir, known, version)
  local ok, build = pcall(function()
    for _, runtime in pairs(installed_runtimes(developer_dir)) do
      if runtime.platformIdentifier == known.simulator and runtime.version == version and runtime.state == "Ready" then
        return runtime.build
      end
    end
    return nil
  end)
  return ok and build or nil
end

-- Compares versions such as "26.0" and "27.2" part by part.
local function version_is_newer(left, right)
  local left_parts, right_parts = {}, {}
  for part in tostring(left):gmatch("%d+") do
    table.insert(left_parts, tonumber(part))
  end
  for part in tostring(right):gmatch("%d+") do
    table.insert(right_parts, tonumber(part))
  end
  for index = 1, math.max(#left_parts, #right_parts) do
    local left_part, right_part = left_parts[index] or 0, right_parts[index] or 0
    if left_part ~= right_part then
      return left_part > right_part
    end
  end
  return false
end

local components = {
  metaltoolchain = "Metal Toolchain",
  devicesupport = "Device Support",
}

-- Returns the SDK version this Xcode has for a platform, and the build of the
-- simulator runtime it would use if that is installed. simctl names a runtime
-- for every SDK even when it is missing, so the build is checked against the
-- installed runtimes.
local function platform_status(developer_dir, known)
  local ok, sdk_version, installed_build = pcall(function()
    local matches = simctl_json(developer_dir, { "match", "list", "-j" })
    local runtimes = installed_runtimes(developer_dir)
    for sdk, match in pairs(matches) do
      if sdk:sub(1, #known.sdk) == known.sdk then
        for _, runtime in pairs(runtimes) do
          if runtime.build == match.chosenRuntimeBuild and runtime.state == "Ready" then
            return match.sdkVersion, runtime.build
          end
        end
        return match.sdkVersion, nil
      end
    end
    return nil, nil
  end)
  if not ok then
    return nil, nil
  end
  return sdk_version, installed_build
end

-- Returns whether a component is installed and the build this Xcode uses,
-- which xcodebuild reports even before it is downloaded.
local function component_status(developer_dir, component)
  local ok, details = pcall(function()
    return json.decode(
      command.output(
        with_developer_dir(developer_dir, { system.xcodebuild, "-showComponent", component, "-json" }),
        { timeout = 60, quiet = true }
      )
    )
  end)
  if not ok or type(details) ~= "table" then
    return false, nil
  end
  -- "installedUpdateAvailable" also means installed.
  local installed = tostring(details.status or ""):sub(1, #"installed") == "installed"
  return installed, details.buildVersion
end

function install.extras_count(options)
  return #option_list(options.platforms) + #option_list(options.components)
end

-- xcodebuild keeps these apart: simulator platforms (iOS, watchOS, ...) use
-- -downloadPlatform, while components (metalToolchain, ...) use -downloadComponent.
-- Splits a platform entry such as "iOS" or "iOS@26.0" into the platform's
-- details (nil for a name the plugin does not know, which is passed to
-- xcodebuild as given), its -downloadPlatform name and the exact version
-- asked for, if any.
local function parse_platform(entry)
  local platform, runtime_version = entry:match("^([^@]+)@(.+)$")
  platform = platform or entry
  return platforms[platform:lower()], platform, runtime_version
end

-- Runs an xcodebuild download in a pseudo-terminal so it reports progress.
-- `failed` names the download in the error if it fails.
local function download_with_xcodebuild(developer_dir, words, name, failed, steps)
  local download = with_developer_dir(developer_dir, { system.xcodebuild })
  for _, word in ipairs(words) do
    table.insert(download, word)
  end
  if command.with_progress(download, "Downloading " .. name, this_step(steps), { pty = true }) ~= 0 then
    error("Failed to download " .. failed .. ".", 0)
  end
end

local function download_extras(developer_dir, options, version, steps)
  for _, entry in ipairs(option_list(options.platforms)) do
    -- "iOS" is the runtime that matches this Xcode; "iOS@26.0" is an exact
    -- older version, for testing on it.
    local known, platform, runtime_version = parse_platform(entry)
    local display = known and known.name or platform
    local name, installed_build
    if runtime_version ~= nil then
      name = display .. " " .. runtime_version .. " Simulator"
      if known ~= nil then
        local sdk_version = platform_status(developer_dir, known)
        if sdk_version ~= nil and version_is_newer(runtime_version, sdk_version) then
          error(
            "Cannot use "
              .. name
              .. " with Xcode "
              .. version
              .. ", whose newest is "
              .. display
              .. " "
              .. sdk_version
              .. ".",
            0
          )
        end
        installed_build = runtime_build_for_version(developer_dir, known, runtime_version)
      end
    else
      name = display .. " Simulator"
      if known ~= nil then
        local sdk_version
        sdk_version, installed_build = platform_status(developer_dir, known)
        name = display .. (sdk_version and (" " .. sdk_version) or "") .. " Simulator"
      end
    end
    if installed_build ~= nil then
      say(next_step(steps) .. name .. " is already installed (" .. installed_build .. ")")
    else
      say(next_step(steps) .. "Downloading " .. name)
      local words = { "-downloadPlatform", platform }
      if runtime_version ~= nil then
        table.insert(words, "-buildVersion")
        table.insert(words, runtime_version)
      end
      download_with_xcodebuild(developer_dir, words, name, name, steps)
      say(this_step(steps) .. "Installed " .. name)
    end
  end

  for _, component in ipairs(option_list(options.components)) do
    local name = components[component:lower()] or component
    local installed, component_build = component_status(developer_dir, component)
    local build_note = component_build and (" (" .. component_build .. ")") or ""
    if installed then
      say(next_step(steps) .. name .. " is already installed" .. build_note)
    else
      say(next_step(steps) .. "Downloading " .. name .. build_note)
      download_with_xcodebuild(developer_dir, { "-downloadComponent", component }, name, name .. build_note, steps)
      say(this_step(steps) .. "Installed " .. name .. build_note)
    end
  end
end

-- Makes an installed Xcode ready to use from the command line.
-- setup_counted says whether setup was planned as a step, which it is for a
-- new Xcode before anyone knows whether it needs it.
function install.prepare(developer_dir, options, version, steps, setup_counted)
  local bundle_path = developer_dir:match("^(.*%.app)/Contents/Developer$")

  if not first_launch_complete(developer_dir) then
    run_first_launch(developer_dir, version, steps)
  elseif setup_counted then
    say(next_step(steps) .. "Xcode " .. version .. " is already set up")
  end
  if bundle_path ~= nil then
    mark_install_checked(bundle_path)
  end
  download_extras(developer_dir, options, version, steps)
end

return install
