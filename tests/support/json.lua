-- Decodes JSON, standing in for mise's json module in tests.

local json = {}

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

function json.decode(text)
  local position = 1

  local function fail(problem)
    error("Invalid JSON at " .. position .. ": " .. problem, 0)
  end

  local function skip()
    position = text:find("[^ \t\r\n]", position) or (#text + 1)
  end

  local value

  local function string_value()
    local parts = {}
    position = position + 1
    while true do
      local character = text:sub(position, position)
      if character == "" then
        fail("unterminated string")
      elseif character == '"' then
        position = position + 1
        return table.concat(parts)
      elseif character == "\\" then
        local escape = text:sub(position + 1, position + 1)
        if escape == "u" then
          local code = tonumber(text:sub(position + 2, position + 5), 16)
          table.insert(parts, code < 128 and string.char(code) or "?")
          position = position + 6
        else
          table.insert(parts, escapes[escape] or fail("bad escape"))
          position = position + 2
        end
      else
        table.insert(parts, character)
        position = position + 1
      end
    end
  end

  function value()
    skip()
    local character = text:sub(position, position)
    if character == "{" then
      local result = {}
      position = position + 1
      skip()
      if text:sub(position, position) == "}" then
        position = position + 1
        return result
      end
      while true do
        skip()
        local key = string_value()
        skip()
        if text:sub(position, position) ~= ":" then
          fail("expected ':'")
        end
        position = position + 1
        result[key] = value()
        skip()
        local separator = text:sub(position, position)
        position = position + 1
        if separator == "}" then
          return result
        elseif separator ~= "," then
          fail("expected ',' or '}'")
        end
      end
    elseif character == "[" then
      local result = {}
      position = position + 1
      skip()
      if text:sub(position, position) == "]" then
        position = position + 1
        return result
      end
      while true do
        table.insert(result, value())
        skip()
        local separator = text:sub(position, position)
        position = position + 1
        if separator == "]" then
          return result
        elseif separator ~= "," then
          fail("expected ',' or ']'")
        end
      end
    elseif character == '"' then
      return string_value()
    elseif text:sub(position, position + 3) == "true" then
      position = position + 4
      return true
    elseif text:sub(position, position + 4) == "false" then
      position = position + 5
      return false
    elseif text:sub(position, position + 3) == "null" then
      position = position + 4
      return nil
    else
      local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
      if number == nil or number == "" then
        fail("unexpected character")
      end
      position = position + #number
      return tonumber(number)
    end
  end

  local result = value()
  skip()
  if position <= #text then
    fail("trailing characters")
  end
  return result
end

return json
