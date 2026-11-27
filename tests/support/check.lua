-- Registers tests and checks values, with messages that show what differs.

local check = { tests = {} }

function check.test(name, body)
  table.insert(check.tests, { name = name, body = body })
end

-- Writes a value the same way every time, so two values compare by their text.
function check.show(value, indent)
  indent = indent or ""
  if type(value) == "string" then
    return string.format("%q", value)
  end
  if type(value) ~= "table" then
    return tostring(value)
  end
  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)
  if #keys == 0 then
    return "{}"
  end
  local lines = {}
  for _, key in ipairs(keys) do
    local label = type(key) == "number" and "" or (tostring(key) .. " = ")
    table.insert(lines, indent .. "  " .. label .. check.show(value[key], indent .. "  "))
  end
  return "{\n" .. table.concat(lines, ",\n") .. "\n" .. indent .. "}"
end

function check.equal(actual, expected, what)
  local shown_actual, shown_expected = check.show(actual), check.show(expected)
  if shown_actual ~= shown_expected then
    error((what or "Values differ") .. "\n  expected: " .. shown_expected .. "\n  actual:   " .. shown_actual, 2)
  end
end

-- Compares two lists of lines, such as a transcript, and shows both in full
-- with the first difference marked.
function check.lines(actual, expected, what)
  local count = math.max(#actual, #expected)
  local first = nil
  for index = 1, count do
    if actual[index] ~= expected[index] then
      first = index
      break
    end
  end
  if first == nil then
    return
  end
  local function listing(lines)
    local shown = {}
    for index, line in ipairs(lines) do
      table.insert(shown, (index == first and "  > " or "    ") .. line)
    end
    if #lines < first then
      table.insert(shown, "  > (nothing)")
    end
    return table.concat(shown, "\n")
  end
  error(
    (what or "Lines differ")
      .. " at line "
      .. first
      .. "\n  expected:\n"
      .. listing(expected)
      .. "\n  actual:\n"
      .. listing(actual),
    2
  )
end

-- Runs a body that should fail, checks that its message contains the given
-- text, and returns the message.
function check.fails(body, text)
  local ok, message = pcall(body)
  if ok then
    error("Expected an error" .. (text and (" containing " .. string.format("%q", text)) or ""), 2)
  end
  message = tostring(message)
  if text ~= nil and not message:find(text, 1, true) then
    error("Expected an error containing " .. string.format("%q", text) .. "\n  actual: " .. message, 2)
  end
  return message
end

return check
