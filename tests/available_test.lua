-- Available: the versions mise lists, with their builds and release dates.

local check = require("support.check")
local mac = require("support.mac")
local test = check.test

test("lists every release qasim/Xcode lists, newest first, with its build and date", function()
  local world = mac.new({
    releases = {
      { version = "27.3.0-beta.2", build = "27C5035i", date = "2026-11-16" },
      { version = "27.2.0", build = "27B52", date = "2026-10-29" },
      { version = "11.5.0-gm-seed", build = "11E608c", date = "2020-05-15" },
    },
  })

  check.equal(world:hook("Available"), {
    { version = "27.3.0-beta.2", note = "build 27C5035i", created_at = "2026-11-16T00:00:00Z" },
    { version = "27.2.0", note = "build 27B52", created_at = "2026-10-29T00:00:00Z" },
    { version = "11.5.0-gm-seed", note = "build 11E608c", created_at = "2020-05-15T00:00:00Z" },
  })
end)

test("says where the list of releases could not be read from", function()
  local world = mac.new()
  world.http[mac.releases_url] = nil

  check.fails(function()
    world:hook("Available")
  end, "Could not read the list of Xcode releases from " .. mac.releases_url .. ".")
end)
