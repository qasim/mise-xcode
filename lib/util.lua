-- Text helpers shared by the plugin's modules.

local util = {}

function util.trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Quotes a value for a POSIX shell, so paths and names with spaces or quotes
-- reach commands as one argument.
function util.shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function util.split_lines(value)
  local lines = {}
  for line in tostring(value or ""):gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  return lines
end

return util
