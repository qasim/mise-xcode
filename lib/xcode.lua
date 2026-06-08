local cmd = require("cmd")
local http = require("http")
local json = require("json")

local xcode = {}

xcode.github_repo = "https://github.com/qasim/Xcode"
xcode.github_tags_url = xcode.github_repo .. ".git"
xcode.github_api_repo_url = "https://api.github.com/repos/qasim/Xcode"

local records_cache = nil
local records_by_version_cache = nil

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function split_lines(value)
  local lines = {}
  for line in tostring(value or ""):gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  return lines
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
    timeout = 30000,
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

function xcode.record_for_version(version, search_path)
  local records = records_for_version(version)
  for _, record in ipairs(records) do
    if xcode.find_developer_dir(record.build, search_path) ~= nil then
      return record
    end
  end

  return records[1]
end

function xcode.latest_stable_version()
  for _, record in ipairs(tag_records()) do
    if record.version:find("-", 1, true) == nil then
      return record.version
    end
  end
  return nil
end

function xcode.resolve_version(version)
  if version == "latest" then
    return xcode.latest_stable_version()
  end

  for _, record in ipairs(tag_records()) do
    if record.version == version then
      return record.version
    end
    if record.version:match("^" .. version:gsub("%.", "%%.") .. "%.") then
      return record.version
    end
  end

  return nil
end

function xcode.build_for_version(version, search_path)
  local resolved_version = xcode.resolve_version(version)
  if resolved_version == nil then
    error("No Xcode version exists that corresponds to " .. version .. ".")
  end

  local record = xcode.record_for_version(resolved_version, search_path)
  if record == nil then
    error("No Xcode version exists that corresponds to " .. version .. ".")
  end

  return record.build, record.version, record
end

local function xcode_bundle_paths(search_path)
  local query = "kMDItemCFBundleIdentifier='com.apple.dt.Xcode'"
  local output =
    cmd.exec("mdfind -onlyin " .. shell_quote(search_path or "/") .. " " .. shell_quote(query), { timeout = 30000 })
  return split_lines(output)
end

local function product_build_version(bundle_path)
  local plist_path = bundle_path .. "/Contents/version.plist"
  local output = cmd.exec(
    "/usr/libexec/PlistBuddy -c " .. shell_quote("print 'ProductBuildVersion'") .. " " .. shell_quote(plist_path),
    { timeout = 10000 }
  )
  return trim(output)
end

function xcode.find_developer_dir(build, search_path)
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

function xcode.record_for_version_and_build(version, build)
  for _, record in ipairs(records_for_version(version)) do
    if record.build == build then
      return record
    end
  end
  return nil
end

function xcode.require_developer_dir(version, build, search_path, record)
  local developer_dir = xcode.find_developer_dir(build, search_path)
  if developer_dir == nil then
    local message = "No Xcode " .. version .. " installation found within search path."
    local installation_hint = xcode.installation_hint(record)
    if installation_hint ~= nil and installation_hint ~= "" then
      message = message .. "\nInstall it from: " .. installation_hint
    end
    error(message)
  end
  return developer_dir
end

function xcode.write_build_file(path, build)
  cmd.exec("mkdir -p " .. shell_quote(path), { timeout = 10000 })
  cmd.exec("printf %s " .. shell_quote(build) .. " > " .. shell_quote(path .. "/BUILD"), {
    timeout = 10000,
  })
end

function xcode.read_build_file(path)
  local file = require("file")
  return trim(file.read(path .. "/BUILD"))
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
