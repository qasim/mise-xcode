local cmd = require("cmd")
local system = require("system")
local http = require("http")
local json = require("json")
local util = require("util")

local trim, shell_quote, split_lines = util.trim, util.shell_quote, util.split_lines

local xcode = {}

xcode.github_repo = "https://github.com/qasim/Xcode"
xcode.github_tags_url = xcode.github_repo .. ".git"
xcode.github_api_repo_url = "https://api.github.com/repos/qasim/Xcode"

local records_cache = nil
local records_by_version_cache = nil

local function command_succeeds(command)
  return pcall(function()
    cmd.exec(command, { timeout = 10 })
  end)
end

local function path_exists(path)
  return command_succeeds("test -e " .. shell_quote(path)) or command_succeeds("test -L " .. shell_quote(path))
end

local function path_is_directory(path)
  return command_succeeds("test -d " .. shell_quote(path))
end

local function path_is_symlink(path)
  return command_succeeds("test -L " .. shell_quote(path))
end

local function symlink_target(path)
  local ok, target = pcall(function()
    return cmd.exec("readlink " .. shell_quote(path), { timeout = 10 })
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
    return cmd.exec(system.xcode_select .. " -p", { timeout = 10 })
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

local function parse_version(version)
  local base, prerelease = version:match("^([%d%.]+)%-?(.*)$")
  local parts = {}
  for part in tostring(base or ""):gmatch("%d+") do
    table.insert(parts, tonumber(part))
  end
  return parts, prerelease ~= "" and prerelease or nil
end

local function compare_versions(left, right)
  local left_parts, left_prerelease = parse_version(left)
  local right_parts, right_prerelease = parse_version(right)

  for i = 1, math.max(#left_parts, #right_parts) do
    local left_part = left_parts[i] or 0
    local right_part = right_parts[i] or 0
    if left_part ~= right_part then
      return left_part - right_part
    end
  end

  if left_prerelease == nil and right_prerelease ~= nil then
    return 1
  end
  if left_prerelease ~= nil and right_prerelease == nil then
    return -1
  end
  if left_prerelease == nil and right_prerelease == nil then
    return 0
  end
  if left_prerelease == right_prerelease then
    return 0
  end
  return left_prerelease > right_prerelease and 1 or -1
end

local function compare_natural(left, right)
  local left_tokens = {}
  local right_tokens = {}

  for token in tostring(left):gmatch("%d+%D*") do
    local number, suffix = token:match("^(%d+)(%D*)$")
    table.insert(left_tokens, { number = tonumber(number), suffix = suffix })
  end
  for token in tostring(right):gmatch("%d+%D*") do
    local number, suffix = token:match("^(%d+)(%D*)$")
    table.insert(right_tokens, { number = tonumber(number), suffix = suffix })
  end

  for i = 1, math.max(#left_tokens, #right_tokens) do
    local left_token = left_tokens[i]
    local right_token = right_tokens[i]
    if left_token == nil then
      return -1
    end
    if right_token == nil then
      return 1
    end
    if left_token.number ~= right_token.number then
      return left_token.number - right_token.number
    end
    if left_token.suffix ~= right_token.suffix then
      return left_token.suffix > right_token.suffix and 1 or -1
    end
  end

  return 0
end

local function load_tag_records()
  if records_cache ~= nil then
    return records_cache, records_by_version_cache
  end

  local output = cmd.exec("git ls-remote --tags --refs " .. shell_quote(xcode.github_tags_url), {
    timeout = 30,
  })
  local by_version = {}

  for _, line in ipairs(split_lines(output)) do
    local tag_sha = line:match("^([^%s]+)%s+")
    local tag = line:match("refs/tags/(.+)$")
    if tag ~= nil then
      local version, build = tag:match("^(.+)%+(.+)$")
      if version ~= nil and build ~= nil then
        by_version[version] = by_version[version] or {}
        table.insert(by_version[version], {
          version = version,
          build = build,
          tag = tag,
          tag_sha = tag_sha,
        })
      end
    end
  end

  local records = {}
  for _, version_records in pairs(by_version) do
    table.sort(version_records, function(left, right)
      return compare_natural(left.build, right.build) > 0
    end)
    table.insert(records, version_records[1])
  end
  table.sort(records, function(left, right)
    return compare_versions(left.version, right.version) > 0
  end)

  records_cache = records
  records_by_version_cache = by_version
  return records_cache, records_by_version_cache
end

local function tag_records()
  local records = load_tag_records()
  return records
end

local function records_for_version(version)
  local _, by_version = load_tag_records()
  return by_version[version] or {}
end

function xcode.available_versions()
  local result = {}
  for _, record in ipairs(tag_records()) do
    table.insert(result, {
      version = record.version,
      note = "build " .. record.build,
    })
  end
  return result
end

function xcode.record_for_version(version, search_path, install_dir)
  local records = records_for_version(version)
  for _, record in ipairs(records) do
    if xcode.find_developer_dir(record.build, search_path, install_dir) ~= nil then
      return record
    end
  end

  return records[1]
end

-- Pre-release labels as people write them, and as the tags name them. GM
-- seeds were tagged "-seed" before they were "-gm-seed".
local labels = { beta = "beta", rc = "rc", ["gm-seed"] = "gm-seed", seed = "gm-seed" }

-- The tag version a spelling names: "27.2-rc.1" is "27.2.0-rc", and
-- "11.5.0-seed" is "11.5.0-gm-seed". Returns nil for anything else.
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

-- The version in an .xcode-version file, which xcodes and fastlane read. It
-- is exact, as xcodes reads it: "26" is 26.0.0. Besides their "14.0b6", it
-- may be written as Apple does, "14.0 Beta 6", or as the plugin's versions
-- are. Returns nil for anything else.
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

-- mise matches prefixes such as "27" and resolves "latest" itself, so a
-- version reaches the plugin either as tagged or spelled another way.
function xcode.resolve_version(written)
  local version = tag_version(written)
  if version ~= nil and #records_for_version(version) > 0 then
    return version
  end
  return nil
end

function xcode.build_for_version(version, search_path, install_dir)
  local resolved_version = xcode.resolve_version(version)
  if resolved_version == nil then
    error("No Xcode release matches version " .. version .. ".", 0)
  end

  local record = xcode.record_for_version(resolved_version, search_path, install_dir)
  if record == nil then
    error("No Xcode release matches version " .. version .. ".", 0)
  end

  return record.build, record.version, record
end

local function xcode_bundle_paths(search_path)
  local query = "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"
  local output = cmd.exec(
    system.mdfind .. " -onlyin " .. shell_quote(search_path or "/") .. " " .. shell_quote(query),
    { timeout = 30 }
  )
  return split_lines(output)
end

local function product_build_version(bundle_path)
  local plist_path = bundle_path .. "/Contents/version.plist"
  local output = cmd.exec(
    "/usr/libexec/PlistBuddy -c " .. shell_quote("print 'ProductBuildVersion'") .. " " .. shell_quote(plist_path),
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
    return cmd.exec("ls -1 " .. shell_quote(directory), { timeout = 10 })
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

function xcode.installation_hint(record)
  if record == nil or record.tag_sha == nil then
    return nil
  end
  if record.installation_url ~= nil then
    return record.installation_url
  end

  local resp, err = http.get({
    url = xcode.github_api_repo_url .. "/git/tags/" .. record.tag_sha,
  })
  if err ~= nil or resp == nil or resp.status_code ~= 200 then
    return nil
  end

  local ok, body = pcall(function()
    return json.decode(resp.body)
  end)
  if not ok or body == nil then
    return nil
  end

  local message = body.message
  local url = tostring(message or ""):match("https://%S+")
  record.installation_url = url
  return record.installation_url
end

-- suggest_xcodes says whether adding xcodes would let the plugin download the
-- missing Xcode, which is not the case when the install option is off.
function xcode.require_developer_dir(version, build, search_path, record, install_dir, suggest_xcodes)
  local developer_dir = xcode.find_developer_dir(build, search_path, install_dir)
  if developer_dir == nil then
    local message = "No Xcode " .. version .. " (" .. build .. ") found in the search path."
    local download_url = xcode.installation_hint(record)
    local has_url = download_url ~= nil and download_url ~= ""
    if has_url and suggest_xcodes then
      message = message
        .. "\nDownload it from "
        .. download_url
        .. ", or add xcodes to [tools] so mise can download it."
    elseif has_url then
      message = message .. "\nDownload it from " .. download_url .. "."
    elseif suggest_xcodes then
      message = message .. "\nAdd xcodes to [tools] so mise can download it."
    end
    error(message, 0)
  end
  return developer_dir
end

function xcode.write_developer_dir_install(path, developer_dir)
  local parent = path:match("^(.*)/[^/]+$")
  if parent ~= nil then
    cmd.exec("mkdir -p " .. shell_quote(parent), { timeout = 10 })
  end

  if path_is_symlink(path) then
    cmd.exec("rm -f " .. shell_quote(path), { timeout = 10 })
  elseif path_is_directory(path) then
    -- Clear what older versions of this plugin kept in the install folder.
    cmd.exec("rm -f " .. shell_quote(path .. "/Developer") .. " " .. shell_quote(path .. "/BUILD"), { timeout = 10 })
    cmd.exec("rmdir " .. shell_quote(path), { timeout = 10 })
  elseif path_exists(path) then
    cmd.exec("rm -f " .. shell_quote(path), { timeout = 10 })
  end

  cmd.exec("ln -s " .. shell_quote(developer_dir) .. " " .. shell_quote(path), { timeout = 10 })
end

function xcode.read_build_file(path)
  local file = require("file")
  return trim(file.read(path .. "/BUILD"))
end

function xcode.developer_dir_for_install(path, search_path)
  if path_is_symlink(path) then
    return symlink_target(path) or path
  end

  -- Migrate installs created before the install path became a symlink. The
  -- broken-link fallback deliberately keeps DEVELOPER_DIR version-specific,
  -- so a removed Xcode cannot silently fall back to another installation.
  local link_path = path .. "/Developer"
  if path_exists(link_path) then
    return symlink_target(link_path) or link_path
  end

  -- Without a BUILD file this is not an older install but one still in
  -- progress, which PostInstall is about to replace with a symlink.
  local build_ok, build = pcall(xcode.read_build_file, path)
  if not build_ok or build == "" then
    return path .. "/Xcode-not-installed"
  end

  local developer_dir = nil
  local find_ok, result = pcall(xcode.find_developer_dir, build, search_path)
  if find_ok then
    developer_dir = result
  end

  local target = developer_dir or (path .. "/Xcode-not-installed")
  command_succeeds("ln -s " .. shell_quote(target) .. " " .. shell_quote(link_path))

  if path_exists(link_path) then
    return symlink_target(link_path) or link_path
  end
  return developer_dir or link_path
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

function xcode.context_field(ctx, key, fallback)
  local ok, value = pcall(function()
    return ctx[key]
  end)
  if ok and value ~= nil then
    return value
  end
  return fallback
end

return xcode
