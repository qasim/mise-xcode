-- A fake Mac for running the plugin's hooks in tests.
--
-- The plugin reaches the outside world only through mise's modules (cmd, file,
-- http, json) and a few Lua functions (print, io.popen, os.execute,
-- os.getenv). This replaces them with a world described in a test: the Xcodes
-- on disk, the selected one, the tags in qasim/Xcode, and what xcodes knows.
-- Shell commands are understood as far as the plugin uses them; any other
-- command fails the test, so a new command has to be modeled on purpose.
--
-- `transcript` records what the plugin did to the outside world, as "$ ..."
-- lines, and what it told the user, as "> ..." lines. Questions it asked,
-- such as whether a file exists, are not recorded: they are how the plugin
-- works, not what it does.

local json = require("support.json")

local mac = {}

local plugin_modules = { "cmd", "file", "http", "json", "install", "system", "util", "xcode" }
local originals = { print = print, popen = io.popen, execute = os.execute, getenv = os.getenv }

local exit_marker = "__mise_xcode_exit_"

-- Shell words --------------------------------------------------------------

-- Splits a command at a separator such as " && " or " | ", outside quotes.
local function split_top(command, separator)
  local parts, start, index, quote = {}, 1, 1, nil
  while index <= #command do
    local character = command:sub(index, index)
    if quote ~= nil then
      if character == quote then
        quote = nil
      elseif character == "\\" and quote == '"' then
        index = index + 1
      end
    elseif character == "'" or character == '"' then
      quote = character
    elseif character == "\\" then
      index = index + 1
    elseif command:sub(index, index + #separator - 1) == separator then
      table.insert(parts, command:sub(start, index - 1))
      start = index + #separator
      index = start - 1
    end
    index = index + 1
  end
  table.insert(parts, command:sub(start))
  return parts
end

-- Splits a simple command into its words, removing quotes and redirections.
local function words(command)
  local result, current, has_word, index, quote = {}, {}, false, 1, nil
  local function finish()
    if has_word then
      local word = table.concat(current)
      if not word:match("^%d*[<>]") then
        table.insert(result, word)
      end
    end
    current, has_word = {}, false
  end
  while index <= #command do
    local character = command:sub(index, index)
    if quote == "'" then
      if character == "'" then
        quote = nil
      else
        table.insert(current, character)
      end
    elseif quote == '"' then
      if character == '"' then
        quote = nil
      elseif character == "\\" then
        index = index + 1
        table.insert(current, command:sub(index, index))
      else
        table.insert(current, character)
      end
    elseif character == "'" or character == '"' then
      quote, has_word = character, true
    elseif character == "\\" then
      index = index + 1
      table.insert(current, command:sub(index, index))
      has_word = true
    elseif character:match("%s") then
      finish()
    else
      table.insert(current, character)
      has_word = true
    end
    index = index + 1
  end
  finish()
  return result
end

-- Writes words back as one line for the transcript, quoting those with spaces.
local function line(list)
  local shown = {}
  for _, word in ipairs(list) do
    table.insert(shown, word:find("%s") and string.format("%q", word) or word)
  end
  return table.concat(shown, " ")
end

-- The world ----------------------------------------------------------------

local World = {}
World.__index = World

-- Describes a Mac. Every field is optional:
--   tags      tags of qasim/Xcode, such as "27.2.0+27B52"
--   apps      Xcode apps by path: { build = "27B52", set_up = true,
--             team = "59GAB85EFG", gatekeeper = true, indexed = true }
--   selected  the app xcode-select points at
--   xcodes    nil when xcodes is missing, else:
--             saved     the releases in xcodes' saved list: { name, build }
--             current   what xcodereleases.com lists now, which `xcodes update`
--                       saves (defaults to saved)
--             apple     releases in Apple's list: { name, build }
--             signed_in whether xcodes has a session (default true)
--             broken    whether `xcodes version` fails, as an unset mise shim does
--             Each release may set `file` (its archive's name),
--             `downloads` (the build the archive really holds), `team`
--             (who signed it) and `signature = "broken"` (changed after it
--             was signed).
--   terminal    whether someone can answer prompts (default false)
--   sudo_cached whether sudo would run without asking (default true)
--   stream      whether mise has cmd.stream (default true)
--   env         environment variables
--   files       file contents by path, for file.read
--   http        response bodies by URL, for http.get
function mac.new(description)
  description = description or {}
  local world = setmetatable({
    transcript = {},
    apps = {},
    paths = {},
    archives = {},
    tags = description.tags or {},
    selected = description.selected,
    xcodes = description.xcodes,
    terminal = description.terminal or false,
    sudo_cached = description.sudo_cached ~= false,
    stream = description.stream ~= false,
    files = description.files or {},
    http = description.http or {},
    env = description.env or {},
    home = "/Users/me",
  }, World)
  world.env.HOME = world.env.HOME or world.home
  world.env.MISE_CACHE_DIR = world.env.MISE_CACHE_DIR or "/cache"
  for path, app in pairs(description.apps or {}) do
    world.apps[path] = {
      build = app.build,
      set_up = app.set_up ~= false,
      team = app.team or "59GAB85EFG",
      gatekeeper = app.gatekeeper ~= false,
      indexed = app.indexed ~= false,
      identifier = app.identifier or "com.apple.dt.Xcode",
    }
  end
  for path, kind in pairs(description.paths or {}) do
    world.paths[path] = kind
  end
  if world.xcodes ~= nil then
    world.xcodes.saved = world.xcodes.saved or {}
    world.xcodes.current = world.xcodes.current or world.xcodes.saved
    world.xcodes.apple = world.xcodes.apple or {}
    world.xcodes.signed_in = world.xcodes.signed_in ~= false
    world.xcodes.list_from = "xcodereleases"
  end
  world:install()
  return world
end

function World:record(text)
  table.insert(self.transcript, text)
end

-- Paths ----------------------------------------------------------------------

function World:exists(path)
  if self.paths[path] ~= nil or self.apps[path] ~= nil or self.archives[path] ~= nil then
    return true
  end
  local prefix = path .. "/"
  for _, list in ipairs({ self.paths, self.apps, self.archives }) do
    for key in pairs(list) do
      if key:sub(1, #prefix) == prefix then
        return true
      end
    end
  end
  return false
end

function World:children(directory)
  local names, seen, prefix = {}, {}, directory .. "/"
  for _, list in ipairs({ self.paths, self.apps, self.archives }) do
    for key in pairs(list) do
      if key:sub(1, #prefix) == prefix then
        local name = key:sub(#prefix + 1):match("^[^/]+")
        if not seen[name] then
          seen[name] = true
          table.insert(names, name)
        end
      end
    end
  end
  table.sort(names)
  return names
end

-- Removes a path and everything in it. Returns whether anything was there.
function World:remove(path)
  local removed, prefix = false, path .. "/"
  for _, list in ipairs({ self.paths, self.apps, self.archives }) do
    for key in pairs(list) do
      if key == path or key:sub(1, #prefix) == prefix then
        list[key] = nil
        removed = true
      end
    end
  end
  return removed
end

function World:move(from, to)
  local prefix = from .. "/"
  for _, list in ipairs({ self.paths, self.apps, self.archives }) do
    local moved = {}
    for key, value in pairs(list) do
      if key == from then
        moved[to] = value
        list[key] = nil
      elseif key:sub(1, #prefix) == prefix then
        moved[to .. key:sub(#from + 1)] = value
        list[key] = nil
      end
    end
    for key, value in pairs(moved) do
      list[key] = value
    end
  end
end

-- The app a developer directory or bundle path belongs to.
function World:app_for(path)
  local bundle = tostring(path or ""):match("^(.*%.app)") or path
  return self.apps[bundle], bundle
end

-- Commands -------------------------------------------------------------------

-- Runs a command line. Returns its output and exit code.
function World:run(command, mode)
  mode = mode or {}

  local inner = command:match("^if %((.*)%) 2>&1; then code=0; else code=%$%?; fi; printf ")
  if inner ~= nil then
    local output, code = self:run(inner, mode)
    return output .. "\n" .. exit_marker .. code, 0
  end

  local pipeline = command:match("^/bin/bash %-o pipefail %-c (.*)$")
  if pipeline ~= nil then
    local parts = split_top(words(pipeline)[1], " | ")
    -- The last part is lib/progress.pl, which passes the exit code on.
    return self:run(parts[1], mode)
  end

  local commands = split_top(command, " && ")
  local output, code = "", 0
  local cwd = nil
  for _, simple in ipairs(commands) do
    output, code, cwd = self:simple(words(simple), mode, cwd)
    if code ~= 0 then
      break
    end
  end
  return output, code
end

local function ok(output)
  return output or "", 0
end

local function failed(code)
  return "", code or 1
end

-- Runs one command given as words. Returns its output, exit code and the
-- working directory for the commands after it.
function World:simple(argv, mode, cwd)
  local env = {}
  while argv[1] ~= nil and argv[1]:match("^[%u_]+=") do
    local name, value = argv[1]:match("^([%u_]+)=(.*)$")
    env[name] = value
    table.remove(argv, 1)
  end
  local program = argv[1]

  if program == "cd" then
    return "", 0, argv[2]
  elseif program == "test" then
    local flag, path = argv[2], argv[3]
    local results = {
      ["-e"] = function()
        return self:exists(path)
      end,
      ["-d"] = function()
        return self:exists(path) and type(self.paths[path]) ~= "table" and self.archives[path] == nil
      end,
      ["-L"] = function()
        return type(self.paths[path]) == "table"
      end,
      ["-x"] = function()
        return path == "/usr/bin/archiveutil"
      end,
      ["-w"] = function()
        return not (self.read_only or {})[path]
      end,
      ["-t"] = function()
        return self.terminal
      end,
    }
    return "", results[flag]() and 0 or 1, cwd
  elseif program == "readlink" then
    local link = self.paths[argv[2]]
    if type(link) ~= "table" then
      return "", 1, cwd
    end
    return link.target .. "\n", 0, cwd
  elseif program == "mkdir" then
    if not self:exists(argv[3]) then
      self.paths[argv[3]] = "dir"
    end
    return "", 0, cwd
  elseif program == "rm" then
    for index = 3, #argv do
      if self:remove(argv[index]) and argv[2] == "-rf" then
        self:record("$ rm -rf " .. argv[index])
      end
    end
    return "", 0, cwd
  elseif program == "rmdir" then
    self:remove(argv[2])
    return "", 0, cwd
  elseif program == "ln" then
    self.paths[argv[4]] = { target = argv[3] }
    self:record("$ ln -s " .. argv[3] .. " " .. argv[4])
    return "", 0, cwd
  elseif program == "mv" then
    if not self:exists(argv[2]) then
      return "", 1, cwd
    end
    self:move(argv[2], argv[3])
    self:record("$ mv " .. argv[2] .. " " .. argv[3])
    return "", 0, cwd
  elseif program == "ls" then
    if not self:exists(argv[3]) then
      return "", 1, cwd
    end
    return table.concat(self:children(argv[3]), "\n"), 0, cwd
  elseif program == "printf" then
    return self.home, 0, cwd
  elseif program == "touch" then
    return "", 0, cwd
  elseif program == "/usr/bin/xcode-select" then
    if self.selected == nil then
      return "", 1, cwd
    end
    return self.selected .. "/Contents/Developer\n", 0, cwd
  elseif program == "/usr/libexec/PlistBuddy" then
    local app = self:app_for(argv[4])
    if app == nil then
      return "", 1, cwd
    end
    if argv[3]:find("ProductBuildVersion", 1, true) then
      return app.build .. "\n", 0, cwd
    end
    return app.identifier .. "\n", 0, cwd
  elseif program == "/usr/bin/mdfind" then
    local found = {}
    for path, app in pairs(self.apps) do
      if app.indexed and (argv[3] == "/" or path:sub(1, #argv[3] + 1) == argv[3] .. "/") then
        table.insert(found, path)
      end
    end
    table.sort(found)
    return table.concat(found, "\n"), 0, cwd
  elseif program == "git" then
    local lines = {}
    for _, tag in ipairs(self.tags) do
      table.insert(lines, "sha-" .. tag .. "\trefs/tags/" .. tag)
    end
    return table.concat(lines, "\n"), 0, cwd
  elseif program == "command" then
    if self.xcodes == nil then
      return "", 1, cwd
    end
    return "/opt/xcodes\n", 0, cwd
  elseif program == "/opt/xcodes" then
    return self:xcodes_command(argv, mode, cwd)
  elseif program == "/usr/bin/script" or program == "/bin/sh" then
    local output, code = self:run(argv[#argv], mode)
    return output, code, cwd
  elseif program == "/usr/bin/xip" then
    return self:expand(argv[3], cwd, "xip --expand")
  elseif program == "/usr/bin/archiveutil" then
    return self:expand(argv[3], cwd, "archiveutil extractXcodeAEA")
  elseif program == "/usr/bin/codesign" then
    local app = self:app_for(argv[#argv])
    if argv[2] == "--verify" then
      -- Checks the signature against a requirement such as
      -- '=anchor apple and identifier "com.apple.dt.Xcode"'.
      local requirement = argv[#argv - 1]
      local identifier = requirement:match('identifier "([^"]+)"')
      local apple = app.team == "59GAB85EFG" or not requirement:find("anchor apple", 1, true)
      local valid = app.signature == "valid" and apple and identifier == app.identifier
      return "", valid and 0 or 3, cwd
    end
  elseif program == "/usr/sbin/spctl" then
    local app = self:app_for(argv[#argv])
    return "", app.gatekeeper and 0 or 3, cwd
  elseif program == "/usr/bin/xcodebuild" then
    local app = self:app_for(env.DEVELOPER_DIR)
    if argv[2] == "-checkFirstLaunchStatus" then
      return "", (app and app.set_up) and 0 or 69, cwd
    end
  elseif program == "/usr/bin/sudo" then
    return self:sudo(argv, mode, cwd)
  end

  error("The fake Mac does not know this command: " .. line(argv), 0)
end

-- Unpacks an archive into the working directory, as xip and archiveutil do.
function World:expand(archive, cwd, tool)
  local contents = self.archives[archive]
  if contents == nil then
    return "", 1, cwd
  end
  self:record("$ " .. tool .. " " .. archive)
  self.apps[cwd .. "/Xcode.app"] = {
    build = contents.build,
    set_up = false,
    team = contents.team or "59GAB85EFG",
    gatekeeper = contents.gatekeeper ~= false,
    indexed = false,
    identifier = "com.apple.dt.Xcode",
    signature = contents.signature or "valid",
  }
  return "", 0, cwd
end

-- Runs a command as root. The first-launch setup is recorded command by command.
function World:sudo(argv, mode, cwd)
  if argv[2] == "-n" and argv[3] == "true" then
    return "", self.sudo_cached and 0 or 1, cwd
  end
  local asks = argv[2] ~= "-n"
  if (asks and not (mode.interactive and self.terminal)) or (not asks and not self.sudo_cached) then
    return "", 1, cwd
  end
  local script = argv[#argv]
  local developer_dir = script:match("DEVELOPER_DIR='([^']+)'")
  for _, part in ipairs(split_top(script, "; ")) do
    local command = words(part)
    if command[1] ~= "set" then
      while command[1]:match("^[%u_]+=") do
        table.remove(command, 1)
      end
      command[1] = command[1]:match("[^/]+$")
      self:record("$ sudo " .. line(command))
    end
  end
  local app = self:app_for(developer_dir)
  if app ~= nil then
    app.set_up = true
  end
  return "", 0, cwd
end

-- xcodes: its saved list, `update`, and `download`.
function World:xcodes_command(argv, mode, cwd)
  local xcodes = self.xcodes
  local subcommand = argv[2]
  if subcommand == "version" then
    return "", xcodes.broken and 1 or 0, cwd
  elseif subcommand == "list" then
    local lines = {}
    if xcodes.list_from == "apple" then
      for _, release in ipairs(xcodes.apple) do
        table.insert(lines, release.name)
      end
    else
      for _, release in ipairs(xcodes.saved) do
        table.insert(lines, release.name .. " (" .. release.build .. ")")
      end
    end
    return table.concat(lines, "\n"), 0, cwd
  elseif subcommand == "update" then
    self:record("$ xcodes update")
    xcodes.saved = xcodes.current
    xcodes.list_from = "xcodereleases"
    return "", 0, cwd
  elseif subcommand == "download" then
    local shown = { "xcodes" }
    local name, directory, from_apple = argv[3], nil, false
    for index = 2, #argv do
      if argv[index] ~= "--no-color" then
        table.insert(shown, argv[index])
      end
      if argv[index] == "--directory" then
        directory = argv[index + 1]
      elseif argv[index] == "--data-source" and argv[index + 1] == "apple" then
        from_apple = true
      end
    end
    self:record("$ " .. line(shown))
    if from_apple then
      -- xcodes keeps one list, which Apple's replaces.
      xcodes.list_from = "apple"
    end
    -- With --use-fastlane-auth, xcodes signs in with fastlane's session.
    local fastlane = false
    for _, word in ipairs(argv) do
      fastlane = fastlane or (word == "--use-fastlane-auth" and self.env.FASTLANE_SESSION ~= nil)
    end
    if not xcodes.signed_in and not fastlane then
      if not (mode.interactive and self.terminal) then
        -- lib/progress.pl stops a download that asks for a sign-in with 75.
        return "", 75, cwd
      end
      self:record("(signs in to Apple)")
      xcodes.signed_in = true
    end
    local release = nil
    for _, candidate in ipairs(from_apple and xcodes.apple or xcodes.saved) do
      if candidate.name == name then
        release = candidate
      end
    end
    if release == nil then
      return "", 1, cwd
    end
    local archive = directory .. "/" .. (release.file or ("Xcode-" .. name:gsub(" ", "_") .. ".xip"))
    self.archives[archive] =
      { build = release.downloads or release.build, team = release.team, signature = release.signature }
    return "", 0, cwd
  end
  error("The fake Mac does not know this xcodes command: " .. line(argv), 0)
end

-- Installing the fakes --------------------------------------------------------

function World:install()
  local world = self
  package.path = "lib/?.lua;tests/?.lua;" .. package.path:gsub("lib/%?%.lua;tests/%?%.lua;", "")
  for _, name in ipairs(plugin_modules) do
    package.loaded[name] = nil
    package.preload[name] = nil
  end

  package.preload.cmd = function()
    local cmd = {}
    function cmd.exec(command)
      local output, code = world:run(command, {})
      if code ~= 0 then
        error("command failed with " .. code .. ": " .. command, 0)
      end
      return output
    end
    if world.stream then
      function cmd.stream(command)
        local _, code = world:run(command, { interactive = true })
        return code
      end
    end
    return cmd
  end
  package.preload.file = function()
    return {
      read = function(path)
        local content = world.files[path]
        if content == nil then
          error("no such file: " .. path, 0)
        end
        return content
      end,
    }
  end
  package.preload.http = function()
    return {
      get = function(options)
        local body = world.http[options.url]
        if body == nil then
          return { status_code = 404, body = "" }
        end
        return { status_code = 200, body = body }
      end,
    }
  end
  package.preload.json = function()
    return json
  end

  print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
      table.insert(parts, tostring(select(index, ...)))
    end
    world:record("> " .. table.concat(parts, "\t"))
  end
  io.popen = function(command)
    local body = command:gsub("; printf '\\n" .. exit_marker .. "%%s\\n' %$%?$", "")
    local output, code = world:run(body, {})
    local lines = {}
    for text in (output .. "\n" .. exit_marker .. code):gmatch("[^\n]+") do
      table.insert(lines, text)
    end
    local index = 0
    return {
      lines = function()
        return function()
          index = index + 1
          return lines[index]
        end
      end,
      close = function() end,
    }
  end
  os.execute = function(command)
    local _, code = world:run(command, { interactive = true })
    return code
  end
  os.getenv = function(name)
    return world.env[name]
  end

  RUNTIME = { osType = "darwin", archType = "arm64", pluginDirPath = "/plugins/xcode" }
end

-- Puts back what install() replaced. The runner calls this after each test.
function mac.restore()
  print, io.popen, os.execute, os.getenv = originals.print, originals.popen, originals.execute, originals.getenv
  RUNTIME, PLUGIN = nil, nil
end

local hook_files = {
  Available = "available",
  EnvKeys = "env_keys",
  ParseLegacyFile = "parse_legacy_file",
  PostInstall = "post_install",
  PreInstall = "pre_install",
}

-- Runs a hook the way mise does: load its file, then call it with a context.
function World:hook(name, ctx)
  PLUGIN = { name = "xcode" }
  dofile("hooks/" .. hook_files[name] .. ".lua")
  return PLUGIN[name](PLUGIN, ctx or {})
end

-- Loads one of the plugin's modules against this world.
function World:module(name)
  return require(name)
end

return mac
