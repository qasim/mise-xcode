-- Runs the tests: `mise run test`, or `lua tests/run.lua [text]` from the
-- repository root to run only the tests whose file or name contains the text.

package.path = "tests/?.lua;" .. package.path

local check = require("support.check")
local mac = require("support.mac")

local filter = arg[1]
local listing = io.popen("ls tests/*_test.lua")
local files = {}
for file in listing:lines() do
  table.insert(files, file)
end
listing:close()

local passed, failures = 0, {}
for _, file in ipairs(files) do
  check.tests = {}
  dofile(file)
  for _, test in ipairs(check.tests) do
    local title = file:match("([^/]+)_test%.lua$") .. ": " .. test.name
    if filter == nil or title:find(filter, 1, true) then
      local ok, message = pcall(test.body)
      mac.restore()
      if ok then
        passed = passed + 1
      else
        table.insert(failures, title .. "\n" .. tostring(message))
      end
    end
  end
end

for _, failure in ipairs(failures) do
  io.stderr:write("FAIL " .. failure .. "\n\n")
end
print(passed .. " passed, " .. #failures .. " failed")
os.exit(#failures == 0 and 0 or 1)
