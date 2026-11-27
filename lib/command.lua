-- Runs commands on the Mac, given as lists of words, such as
-- { "/usr/bin/xcodebuild", "-version" }.
--
-- mise runs each command as a line of shell, so words are quoted here, in one
-- place, and paths with spaces or quotes reach commands as one word.

local cmd = require("cmd")
local util = require("util")

local command = {}

-- Ends the output of commands whose exit code is needed, as
-- "<marker><code>". mise's command runner only reports success or failure.
local exit_marker = "__mise_xcode_exit_"

-- Exit code of lib/progress.pl when a tool stopped to ask for an Apple ID
-- sign-in, and no one could answer.
command.wants_sign_in = 75

-- A line of shell that runs the words, in `cwd` when it's given.
function command.line(words, options)
  local quoted = {}
  for index, word in ipairs(words) do
    quoted[index] = util.shell_quote(word)
  end
  local line = table.concat(quoted, " ")
  if options ~= nil and options.cwd ~= nil then
    line = "cd " .. util.shell_quote(options.cwd) .. " && " .. line
  end
  return line
end

-- A line of shell that runs several commands in turn, stopping at the first
-- that fails.
function command.script(commands)
  local lines = { "set -e" }
  for _, words in ipairs(commands) do
    table.insert(lines, command.line(words))
  end
  return table.concat(lines, "; ")
end

-- Runs a command and returns its output. Raises an error if it fails.
--
--   cwd      the folder to run it in
--   timeout  seconds to wait for it, which is unlimited if not given
--   quiet    hide what it prints as errors
function command.output(words, options)
  options = options or {}
  local line = command.line(words, options) .. (options.quiet and " 2>/dev/null" or "")
  return cmd.exec(line, options.timeout and { timeout = options.timeout } or {})
end

-- Runs a command and returns whether it succeeded.
function command.succeeds(words, options)
  return (pcall(command.output, words, options))
end

-- Runs a command and returns its exit code and everything it printed,
-- including errors, without raising one.
function command.result(words, options)
  local output = cmd.exec(
    "if ("
      .. command.line(words, options)
      .. ") 2>&1; then code=0; else code=$?; fi; printf '\\n"
      .. exit_marker
      .. '%s\' "$code"',
    {}
  )
  local code = tonumber(output:match(exit_marker .. "(%d+)%s*$"))
  return code, util.trim((output:gsub(exit_marker .. "%d+%s*$", "")))
end

-- Runs a line of shell and shows each line of its output through mise, which
-- keeps its progress display below them. Returns the exit code.
local function run_printing(line)
  local handle = io.popen(line .. "; printf '\\n" .. exit_marker .. "%s\\n' $?", "r")
  local code = nil
  for output in handle:lines() do
    local exit_code = output:match("^" .. exit_marker .. "(%d+)$")
    if exit_code ~= nil then
      code = tonumber(exit_code)
    elseif output ~= "" then
      print(output)
    end
  end
  handle:close()
  return code
end

-- Runs a line of shell attached to mise's terminal, so the person can answer
-- its prompts. mise versions without `cmd.stream` fall back to os.execute.
-- Returns the exit code.
local function run_in_terminal(line)
  if type(cmd.stream) == "function" then
    return cmd.stream(line)
  end
  return os.execute(line)
end

-- Whether someone can answer prompts in mise's terminal. It's false for
-- agents, CI and other runs without a terminal.
local terminal = nil

function command.has_terminal()
  if terminal == nil then
    terminal = type(cmd.stream) == "function" and cmd.stream("test -t 0") == 0
  end
  return terminal
end

-- Runs a tool that takes a while, such as a download, and shows its output
-- as tidy progress lines through lib/progress.pl. Returns the exit code.
--
--   label     what progress lines say, such as "Downloading Xcode 27.2.0"
--   step      the step number they start with, such as "(1/3) "
--   pty       run the tool in a pseudo-terminal, so it reports progress as it
--             goes, as it does for a person
--   terminal  attach it to mise's terminal, so the person can answer prompts;
--             otherwise it gets no input
function command.with_progress(words, label, step, options)
  options = options or {}
  local tool = words
  if options.pty then
    tool = { "/usr/bin/script", "-q", "/dev/null" }
    for _, word in ipairs(words) do
      table.insert(tool, word)
    end
  end

  -- Lines that go straight to the terminal start with the prefix mise gives
  -- the plugin's own lines. mise names the plugin's folder after the plugin.
  local filter = { "/usr/bin/perl", RUNTIME.pluginDirPath .. "/lib/progress.pl" }
  if options.terminal and options.pty then
    table.insert(filter, "--interactive")
  end
  local plugin = options.terminal and (RUNTIME.pluginDirPath:match("([^/]+)/*$") or "xcode") or ""
  table.insert(filter, label)
  table.insert(filter, step or "")
  table.insert(filter, plugin)

  local pipeline = command.line(tool)
    .. (options.terminal and "" or " </dev/null")
    .. (options.pty and "" or " 2>&1")
    .. " | "
    .. command.line(filter)
  local line = "/bin/bash -o pipefail -c " .. util.shell_quote(pipeline)
  if options.terminal then
    return run_in_terminal(line)
  end
  return run_printing(line)
end

return command
