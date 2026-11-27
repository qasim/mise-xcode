local command = require("command")
local system = require("system")
local http = require("http")
local json = require("json")
local util = require("util")

local trim, split_lines = util.trim, util.split_lines

local xcode = {}

-- Every Xcode release, newest first, with its build, date and download URL.
xcode.releases_url = "https://raw.githubusercontent.com/qasim/Xcode/main/releases.json"

local releases_cache = nil
local releases_by_version = nil

local function test(flag, path)
  return command.succeeds({ "test", flag, path }, { timeout = 10 })
end

local function path_exists(path)
  return test("-e", path) or test("-L", path)
end

local function path_is_symlink(path)
  return test("-L", path)
end

local function symlink_target(path)
  local ok, target = pcall(function()
    return command.output({ "readlink", path }, { timeout = 10 })
  end)
  if ok then
    return trim(target)
  end
  return nil
end

local function path_is_within(path, parent)
  local normalized_parent = tostring(parent or "/"):gsub("/+$", "")
  if normalized_parent == "" then
    normalized_parent = "/"
  end

  return normalized_parent == "/"
    or path == normalized_parent
    or path:sub(1, #normalized_parent + 1) == normalized_parent .. "/"
end

local function selected_xcode_bundle_path(search_path)
  local ok, output = pcall(function()
    return command.output({ system.xcode_select, "-p" }, { timeout = 10 })
  end)
  if not ok then
    return nil
  end

  local developer_dir = trim(output):gsub("/+$", "")
  local bundle_path = developer_dir:match("^(.*%.app)/Contents/Developer$")
  if bundle_path == nil or not path_is_within(bundle_path, search_path or "/") then
    return nil
  end

  return bundle_path
end

-- Every release, newest first.
local function releases()
  if releases_cache ~= nil then
    return releases_cache
  end

  -- mise's http functions can't run inside pcall in Lua 5.1, so only the
  -- decoding is wrapped.
  local response = http.get({ url = xcode.releases_url })
  local ok, list = false, nil
  if response ~= nil and response.status_code == 200 then
    ok, list = pcall(json.decode, response.body)
  end
  if not ok or type(list) ~= "table" then
    error("Couldn't read the list of Xcode releases.", 0)
  end

  -- Each version belongs to one build.
  releases_by_version = {}
  for _, release in ipairs(list) do
    releases_by_version[release.version] = release
  end
  releases_cache = list
  return releases_cache
end

local function release_for(version)
  releases()
  return releases_by_version[version]
end

function xcode.available_versions()
  local result = {}
  for _, release in ipairs(releases()) do
    table.insert(result, {
      version = release.version,
      note = "build " .. release.build,
      -- For mise's minimum_release_age and --before.
      created_at = release.date and (release.date .. "T00:00:00Z") or nil,
    })
  end
  return result
end

-- Pre-release labels as people write them, and the labels the tags use. GM
-- seeds were tagged "-seed" before "-gm-seed".
local labels = { beta = "beta", rc = "rc", ["gm-seed"] = "gm-seed", seed = "gm-seed" }

-- Returns the tagged version a written version means, such as "27.2.0-rc"
-- for "27.2-rc.1", or "11.5.0-gm-seed" for "11.5.0-seed". Returns nil if it
-- isn't one.
local function tag_version(written)
  local number, label, count = written:match("^(%d+[%.%d]*)%-([%a%-]+)%.?(%d*)$")
  if number == nil then
    number, label, count = written:match("^(%d+[%.%d]*)$"), nil, ""
  end
  if number == nil or number:find("..", 1, true) or number:sub(-1) == "." then
    return nil
  end
  local parts = {}
  for part in number:gmatch("%d+") do
    table.insert(parts, part)
  end
  if #parts > 3 then
    return nil
  end
  while #parts < 3 do
    table.insert(parts, "0")
  end
  local version = table.concat(parts, ".")
  if label == nil then
    return version
  end
  if labels[label] == nil or count == "0" then
    return nil
  end
  version = version .. "-" .. labels[label]
  if count ~= "" and count ~= "1" then
    version = version .. "." .. count
  end
  return version
end

-- Pre-release names as Apple writes them, such as "27.2 Release Candidate 2".
local apple_labels = { beta = "beta", ["release candidate"] = "rc", rc = "rc", ["gm seed"] = "gm-seed" }

-- Reads the version in an .xcode-version file, which xcodes and fastlane use.
-- The version is exact, as in xcodes: "26" means 26.0.0. It can be written as
-- xcodes does ("14.0b6"), as Apple does ("14.0 Beta 6"), or as the tags are.
-- Returns nil if it isn't a version.
function xcode.version_file_version(content)
  local text = util.trim(tostring(content or ""):match("^%s*([^\r\n]*)")):gsub("^[Xx]code%s+", "")

  local number, count = text:match("^(%d+[%.%d]*)[bB](%d*)$")
  if number ~= nil then
    text = number .. "-beta" .. (count ~= "" and ("." .. count) or "")
  end

  local apple_number, name, apple_count = text:match("^(%d+[%.%d]*)%s+(%a[%a ]-)%s*(%d*)$")
  if apple_number ~= nil then
    local label = apple_labels[name:lower()]
    if label == nil then
      return nil
    end
    text = apple_number .. "-" .. label .. (apple_count ~= "" and ("." .. apple_count) or "")
  end

  return tag_version(text)
end

-- mise resolves "latest" and prefixes such as "27" itself, so the plugin only
-- gets full versions, written as tagged or another way.
-- Returns the release a written version means.
function xcode.release_for_version(written)
  local version = tag_version(written)
  local release = version and release_for(version)
  if release == nil then
    error("No Xcode release matches version " .. written .. ".", 0)
  end
  return release
end

local function xcode_bundle_paths(search_path)
  local query = "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"
  local output = command.output({ system.mdfind, "-onlyin", search_path or "/", query }, { timeout = 30 })
  return split_lines(output)
end

local function product_build_version(bundle_path)
  local plist_path = bundle_path .. "/Contents/version.plist"
  local output = command.output(
    { "/usr/libexec/PlistBuddy", "-c", "Print :ProductBuildVersion", plist_path },
    { timeout = 10 }
  )
  return trim(output)
end

-- Lists apps directly inside a folder. Unlike Spotlight, this also sees
-- Xcodes that were installed moments ago and are not indexed yet.
local function direct_bundle_paths(directory, search_path)
  if directory == nil or not path_is_within(directory, search_path or "/") then
    return {}
  end
  local ok, output = pcall(function()
    return command.output({ "ls", "-1", directory }, { timeout = 10 })
  end)
  if not ok then
    return {}
  end
  local paths = {}
  for _, name in ipairs(split_lines(output)) do
    if name:match("^Xcode.*%.app$") then
      table.insert(paths, directory .. "/" .. name)
    end
  end
  return paths
end

function xcode.find_developer_dir(build, search_path, install_dir)
  local selected_bundle_path = selected_xcode_bundle_path(search_path or "/")
  if selected_bundle_path ~= nil then
    local ok, selected_build = pcall(product_build_version, selected_bundle_path)
    if ok and selected_build == build then
      return selected_bundle_path .. "/Contents/Developer"
    end
  end

  for _, bundle_path in ipairs(direct_bundle_paths(install_dir or system.applications, search_path)) do
    local ok, bundle_build = pcall(product_build_version, bundle_path)
    if ok and bundle_build == build then
      return bundle_path .. "/Contents/Developer"
    end
  end

  for _, bundle_path in ipairs(xcode_bundle_paths(search_path or "/")) do
    if product_build_version(bundle_path) == build then
      return bundle_path .. "/Contents/Developer"
    end
  end

  return nil
end

-- suggest_xcodes says whether adding xcodes would let the plugin download the
-- missing Xcode, which is not the case when the install option is off.
function xcode.require_developer_dir(release, search_path, install_dir, suggest_xcodes)
  local version, build = release.version, release.build
  local developer_dir = xcode.find_developer_dir(build, search_path, install_dir)
  if developer_dir == nil then
    local message = "No Xcode " .. version .. " (" .. build .. ") found in the search path."
    local download_url = release.url
    local has_url = download_url ~= nil and download_url ~= ""
    if has_url and suggest_xcodes then
      message = message
        .. "\nDownload it from "
        .. download_url
        .. ", or add xcodes to [tools] so mise can download it before installation."
    elseif has_url then
      message = message .. "\nDownload it from " .. download_url .. "."
    elseif suggest_xcodes then
      message = message .. "\nAdd xcodes to [tools] so mise can download it."
    end
    error(message, 0)
  end
  return developer_dir
end

-- Links mise's install folder for a version to the Xcode it selects.
function xcode.write_developer_dir_install(path, developer_dir)
  local parent = path:match("^(.*)/[^/]+$")
  if parent ~= nil then
    command.output({ "mkdir", "-p", parent }, { timeout = 10 })
  end

  -- mise makes the install folder before PostInstall, so it is replaced.
  if path_is_symlink(path) then
    command.output({ "rm", "-f", path }, { timeout = 10 })
  elseif path_exists(path) then
    command.output({ "rmdir", path }, { timeout = 10 })
  end

  command.output({ "ln", "-s", developer_dir, path }, { timeout = 10 })
end

-- The Xcode a version's install folder links to. Until PostInstall has linked
-- it, DEVELOPER_DIR points at nothing, so Apple's tools fail instead of using
-- another Xcode.
function xcode.developer_dir_for_install(path)
  if path_is_symlink(path) then
    return symlink_target(path) or path
  end
  return path .. "/Xcode-not-installed"
end

-- Where new Xcodes are installed: install_dir, else a narrowed search_path,
-- else /Applications. It is kept inside the search path so the result is found.
function xcode.install_dir(options)
  local directory = options.install_dir
  if directory == nil or directory == "" then
    local search_path = tostring(options.search_path or "/"):gsub("/+$", "")
    directory = search_path ~= "" and search_path or system.applications
  end
  if directory:sub(1, 2) == "~/" then
    directory = (os.getenv("HOME") or "") .. directory:sub(2)
  end
  return directory
end

return xcode
