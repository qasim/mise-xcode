-- Installs a missing Xcode and prepares Xcodes for command-line use.
--
-- Downloading is delegated to xcodes (https://github.com/XcodesOrg/xcodes) when
-- it is available, so its saved Apple ID session is reused. Everything after
-- the download (unpacking, verification, first-launch setup and extra
-- components) is handled here.

local cmd = require("cmd")
local json = require("json")
local system = require("system")
local util = require("util")

local trim, shell_quote, split_lines = util.trim, util.shell_quote, util.split_lines

local install = {}

-- Xcode is signed by Apple as com.apple.dt.Xcode.
local xcode_requirement = '=anchor apple and identifier "com.apple.dt.Xcode"'

-- Ends the output of commands whose exit code the plugin reads from it, as
-- "<marker><code>". mise's own command runner reports only success or failure.
local exit_marker = "__mise_xcode_exit_"

local function exec(command, options)
  return cmd.exec(command, options or {})
end

local function succeeds(command, options)
  return pcall(cmd.exec, command, options or { timeout = 30 })
end

-- Runs a command that may need to prompt the user, such as for an Apple ID
-- sign-in or a sudo password, and returns whether it succeeded. `cmd.stream`
-- hands mise's terminal to the command; mise versions without it fall back to
-- os.execute, which works when no prompt is needed.
local function run_interactive(command)
  if type(cmd.stream) == "function" then
    return cmd.stream(command) == 0
  end
  return os.execute(command) == 0
end

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

-- True when mise runs in a terminal that commands can prompt in. It is false
-- for agents, CI and other runs without a terminal.
local prompt_available = nil

local function can_prompt()
  if prompt_available == nil then
    prompt_available = type(cmd.stream) == "function" and cmd.stream("test -t 0") == 0
  end
  return prompt_available
end

-- Tool options may arrive as booleans, strings, lists or newline-joined strings.
function install.option_list(value)
  local result = {}
  if type(value) == "table" then
    for _, item in ipairs(value) do
      for _, part in ipairs(install.option_list(item)) do
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

local function home_directory()
  local home = os.getenv("HOME")
  if home == nil or home == "" then
    home = trim(exec('printf %s "$HOME"'))
  end
  return home
end

-- Downloads are kept in mise's cache folder, so `mise cache clear` removes leftovers.
local function cache_directory(build)
  local base = os.getenv("MISE_CACHE_DIR")
  if base == nil or base == "" then
    local xdg = os.getenv("XDG_CACHE_HOME")
    if xdg == nil or xdg == "" then
      xdg = home_directory() .. "/Library/Caches"
    end
    base = xdg .. "/mise"
  end
  return base .. "/xcode-downloads/" .. build
end

-- Returns the path of a working xcodes executable, or nil.
function install.xcodes_path()
  local ok, output = pcall(cmd.exec, "command -v xcodes", { timeout = 10 })
  if not ok then
    return nil
  end
  local path = trim(output)
  if path == "" then
    return nil
  end
  -- A mise shim without a selected version exists on PATH but cannot run.
  if not succeeds(shell_quote(path) .. " version") then
    return nil
  end
  return path
end

-- xcodes names releases after Apple ("27.0 Beta 3"), not semver, so the
-- release is looked up by its build number instead of translating versions.
function install.xcodes_name_for_build(xcodes_path, build)
  local output = exec(shell_quote(xcodes_path) .. " list --no-color", { timeout = 120 })
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
  return pcall(exec, shell_quote(xcodes_path) .. " update --no-color", { timeout = 120 })
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
  local ok, output = pcall(cmd.exec, "ls -1 " .. shell_quote(directory), { timeout = 10 })
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

-- Exit code of lib/progress.pl when xcodes stopped to ask for a sign-in.
local wants_sign_in_code = 75

-- The command that tidies a tool's output with lib/progress.pl. With
-- `prefixed`, its lines start with "mise [xcode] " like the plugin's own,
-- for output that goes straight to the terminal; mise names the plugin's
-- folder after the plugin.
local function progress_filter(label, step, prefixed, interactive)
  local plugin = prefixed and (RUNTIME.pluginDirPath:match("([^/]+)/*$") or "xcode") or ""
  return "/usr/bin/perl "
    .. shell_quote(RUNTIME.pluginDirPath .. "/lib/progress.pl")
    .. (interactive and " --interactive" or "")
    .. " "
    .. shell_quote(label)
    .. " "
    .. shell_quote(step or "")
    .. " "
    .. shell_quote(plugin)
end

-- Runs a command and prints each line of its output through mise, which
-- keeps its progress display below them. Returns the command's exit code.
--
-- Output streamed with cmd.stream goes straight to the terminal instead, and
-- mise leaves a frozen copy of its progress display above it, so that is only
-- used when someone has to type an answer.
local function run_printing(command)
  local handle = io.popen(command .. "; printf '\\n" .. exit_marker .. "%s\\n' $?", "r")
  local code = nil
  for line in handle:lines() do
    local exit_code = line:match("^" .. exit_marker .. "(%d+)$")
    if exit_code ~= nil then
      code = tonumber(exit_code)
    elseif line ~= "" then
      say(line)
    end
  end
  handle:close()
  return code
end

-- Runs a download with xcodes or xcodebuild and shows its output in one style
-- through lib/progress.pl. The tool runs in a pseudo-terminal so it reports
-- progress as it goes, with no input so the user's terminal is left alone.
-- Returns whether it succeeded and whether it stopped to ask for a sign-in.
local function run_with_progress(command, label, step)
  local pipeline = "/usr/bin/script -q /dev/null /bin/sh -c "
    .. shell_quote(command)
    .. " </dev/null | "
    .. progress_filter(label, step, false)
  local code = run_printing("/bin/bash -o pipefail -c " .. shell_quote(pipeline))
  return code == 0, code == wants_sign_in_code
end

local function download_with_xcodes(xcodes_path, version, build, directory, steps)
  -- The list xcodes keeps can be older than the release.
  local name = install.xcodes_name_for_build(xcodes_path, build)
  if name == nil and update_xcodes_list(xcodes_path) then
    name = install.xcodes_name_for_build(xcodes_path, build)
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
  -- A session from `fastlane spaceauth` lets xcodes sign in without a prompt,
  -- such as in CI.
  local fastlane_session = os.getenv("FASTLANE_SESSION")
  local command = shell_quote(xcodes_path)
    .. " download "
    .. shell_quote(name)
    .. (from_apple and " --data-source apple" or "")
    .. ((fastlane_session ~= nil and fastlane_session ~= "") and " --use-fastlane-auth" or "")
    .. " --directory "
    .. shell_quote(directory)
    .. " --no-color"
  local label = "Downloading Xcode " .. version
  local ok, wants_sign_in = run_with_progress(command, label, this_step(steps))
  if not ok and wants_sign_in and can_prompt() then
    -- Signing in needs the terminal, so xcodes runs again under `script`
    -- attached to it. The filter shows its prompts and what the person types,
    -- and tidies the rest as before. mise's progress display stays frozen
    -- while the terminal is handed over this way.
    local pipeline = "/usr/bin/script -q /dev/null /bin/sh -c "
      .. shell_quote(command)
      .. " | "
      .. progress_filter(label, this_step(steps), true, true)
    ok = run_interactive("/bin/bash -o pipefail -c " .. shell_quote(pipeline))
  end
  if from_apple then
    -- xcodes keeps one list, which Apple's replaced, so it is set back to the
    -- one from xcodereleases.com, with builds.
    update_xcodes_list(xcodes_path)
  end
  if not ok then
    local message = "Failed to download Xcode " .. version .. " (" .. build .. ") with xcodes."
    if not can_prompt() then
      message = message
        .. "\nIf xcodes needs an Apple ID sign-in, run `mise install` in a terminal,"
        .. " or set XCODES_USERNAME and XCODES_PASSWORD."
    end
    error(message, 0)
  end

  local archive = find_archive(directory)
  if archive == nil then
    error("xcodes reported success, but no Xcode archive is in " .. directory .. ".", 0)
  end
  return archive
end

local function bundle_identifier(bundle_path)
  local ok, output = pcall(
    cmd.exec,
    "/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " .. shell_quote(bundle_path .. "/Contents/Info.plist"),
    { timeout = 10 }
  )
  return ok and trim(output) or nil
end

local function bundle_build(bundle_path)
  local ok, output = pcall(
    cmd.exec,
    "/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' " .. shell_quote(bundle_path .. "/Contents/version.plist"),
    { timeout = 10 }
  )
  return ok and trim(output) or nil
end

local function unpack_archive(archive, directory, version, steps)
  exec("rm -rf " .. shell_quote(directory) .. " && mkdir -p " .. shell_quote(directory))

  local command
  if archive:lower():match("%.aea$") then
    if not succeeds("test -x " .. shell_quote(system.archiveutil)) then
      error("Failed to unpack " .. archive .. ": this version of macOS does not have archiveutil.", 0)
    end
    command = "cd "
      .. shell_quote(directory)
      .. " && "
      .. system.archiveutil
      .. " extractXcodeAEA "
      .. shell_quote(archive)
  else
    -- xip does not check the archive's signature; verify_bundle checks the app.
    command = "cd " .. shell_quote(directory) .. " && " .. system.xip .. " --expand " .. shell_quote(archive)
  end

  say(next_step(steps) .. "Unpacking Xcode " .. version .. ", which can take a few minutes")
  -- The plugin's own lines cover what xip prints, which is shown only on failure.
  -- mise runs commands so that the first failure stops them, except inside an
  -- `if` condition, which keeps xip's exit code for the marker.
  local output =
    exec("if (" .. command .. ") 2>&1; then code=0; else code=$?; fi; printf '\\n" .. exit_marker .. '%s\' "$code"')
  local code = tonumber(output:match(exit_marker .. "(%d+)%s*$"))
  if code ~= 0 then
    local details = trim((output:gsub(exit_marker .. "%d+%s*$", "")))
    error("Failed to unpack " .. archive .. ". The archive may be damaged, or the disk may be full.\n" .. details, 0)
  end

  local contents = exec("ls -1 " .. shell_quote(directory))
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
  local signed = succeeds(
    system.codesign .. " --verify --strict -R " .. shell_quote(xcode_requirement) .. " " .. shell_quote(bundle_path),
    {}
  )
  if not signed then
    error(refused .. "it is not signed by Apple.", 0)
  end

  if not succeeds(system.spctl .. " --assess --type execute " .. shell_quote(bundle_path), {}) then
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
  if succeeds("test -e " .. shell_quote(destination)) then
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
  if not succeeds("mkdir -p " .. shell_quote(install_dir) .. " && test -w " .. shell_quote(install_dir)) then
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
  exec("mkdir -p " .. shell_quote(directory))

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
    exec("rm -rf " .. shell_quote(directory))
    error(bundle_path, 0)
  end

  if not succeeds("mv " .. shell_quote(bundle_path) .. " " .. shell_quote(destination), {}) then
    error(
      "Failed to move Xcode "
        .. version
        .. " into "
        .. install_dir
        .. ".\nSet the install_dir option to a folder you can write to.",
      0
    )
  end

  exec("rm -rf " .. shell_quote(directory))
  say(this_step(steps) .. "Installed Xcode " .. version .. " (" .. build .. ") at " .. destination)
  return destination
end

local function developer_env(developer_dir)
  return "DEVELOPER_DIR=" .. shell_quote(developer_dir) .. " "
end

local function first_launch_complete(developer_dir)
  return succeeds(developer_env(developer_dir) .. system.xcodebuild .. " -checkFirstLaunchStatus")
end

function install.needs_setup(developer_dir)
  return not first_launch_complete(developer_dir)
end

-- Accepts the license and installs the packages Xcode would otherwise ask
-- for on first launch, without opening Xcode.
local function run_first_launch(developer_dir, version, steps)
  local env = developer_env(developer_dir)
  local script = table.concat({
    "set -e",
    env .. system.xcodebuild .. " -license accept",
    env .. system.xcodebuild .. " -runFirstLaunch",
    system.devtoolssecurity .. " -enable",
    system.dseditgroup .. " -o edit -t group -a staff _developer",
  }, "; ")
  local password_cached = succeeds(system.sudo .. " -n true")
  if not password_cached and not can_prompt() then
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
  -- sudo asks for a password on the terminal itself, so only the output of the
  -- setup commands goes through the filter. Without a password to ask for, it
  -- needs no terminal, and its lines go through mise like the rest.
  local ok
  if password_cached then
    -- -n makes sudo fail instead of asking, should the saved password expire
    -- before this runs, because nothing here could show its prompt.
    local command = system.sudo .. " -n /bin/sh -c " .. shell_quote(script)
    local pipeline = command .. " </dev/null 2>&1 | " .. progress_filter("Installing packages", this_step(steps), false)
    ok = run_printing("/bin/bash -o pipefail -c " .. shell_quote(pipeline)) == 0
  else
    local command = system.sudo .. " /bin/sh -c " .. shell_quote(script)
    local pipeline = command .. " 2>&1 | " .. progress_filter("Installing packages", this_step(steps), true)
    ok = run_interactive("/bin/bash -o pipefail -c " .. shell_quote(pipeline))
  end
  if not ok then
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
  pcall(
    cmd.exec,
    'touch "$('
      .. system.getconf
      .. " DARWIN_USER_CACHE_DIR)com.apple.dt.Xcode.InstallCheckCache_$("
      .. system.sw_vers
      .. " -buildVersion)_"
      .. build
      .. '"',
    { timeout = 10 }
  )
end

-- Simulator platforms by their -downloadPlatform name: the SDK name and
-- simulator platform simctl uses for them, and how to describe them.
local platforms = {
  ios = { sdk = "iphoneos", simulator = "com.apple.platform.iphonesimulator", name = "iOS" },
  watchos = { sdk = "watchos", simulator = "com.apple.platform.watchsimulator", name = "watchOS" },
  tvos = { sdk = "appletvos", simulator = "com.apple.platform.appletvsimulator", name = "tvOS" },
  visionos = { sdk = "xros", simulator = "com.apple.platform.xrsimulator", name = "visionOS" },
}

local function installed_runtimes(developer_dir)
  return json.decode(exec(developer_env(developer_dir) .. system.xcrun .. " simctl runtime list -j", { timeout = 60 }))
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
  local env = developer_env(developer_dir)
  local ok, sdk_version, installed_build = pcall(function()
    local matches = json.decode(exec(env .. system.xcrun .. " simctl runtime match list -j", { timeout = 60 }))
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
      exec(
        developer_env(developer_dir)
          .. system.xcodebuild
          .. " -showComponent "
          .. shell_quote(component)
          .. " -json 2>/dev/null",
        { timeout = 60 }
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
  return #install.option_list(options.platforms) + #install.option_list(options.components)
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

local function download_extras(developer_dir, options, version, steps)
  local env = developer_env(developer_dir)

  for _, entry in ipairs(install.option_list(options.platforms)) do
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
      local command = env .. system.xcodebuild .. " -downloadPlatform " .. shell_quote(platform)
      if runtime_version ~= nil then
        command = command .. " -buildVersion " .. shell_quote(runtime_version)
      end
      if not run_with_progress(command, "Downloading " .. name, this_step(steps)) then
        error("Failed to download " .. name .. ".", 0)
      end
      say(this_step(steps) .. "Installed " .. name)
    end
  end

  for _, component in ipairs(install.option_list(options.components)) do
    local name = components[component:lower()] or component
    local installed, component_build = component_status(developer_dir, component)
    local build_note = component_build and (" (" .. component_build .. ")") or ""
    if installed then
      say(next_step(steps) .. name .. " is already installed" .. build_note)
    else
      say(next_step(steps) .. "Downloading " .. name .. build_note)
      local command = env .. system.xcodebuild .. " -downloadComponent " .. shell_quote(component)
      if not run_with_progress(command, "Downloading " .. name, this_step(steps)) then
        error("Failed to download " .. name .. build_note .. ".", 0)
      end
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
