local install = require("install")
local xcode = require("xcode")

function PLUGIN:PreInstall(ctx)
  local options = ctx.options or {}
  local search_path = options.search_path or "/"
  local install_dir = xcode.install_dir(options)
  local release = xcode.release_for_version(ctx.version)
  local version, build = release.version, release.build
  local automatic = install.option_enabled(options.install, true)
  local note = "Selected Xcode " .. version .. " (" .. build .. ")"

  -- Plan the steps up front so each can be numbered, such as "(2/5)". A new
  -- Xcode is downloaded, unpacked and set up; an existing one is set up only
  -- if it needs it. Each platform and component is one more step.
  local developer_dir = xcode.find_developer_dir(build, search_path, install_dir)
  local downloading = automatic and developer_dir == nil and install.xcodes_path() ~= nil
  local total = 0
  if automatic then
    total = install.extras_count(options)
    if downloading then
      total = total + 3
    elseif developer_dir ~= nil and install.needs_setup(developer_dir) then
      total = total + 1
    end
  end
  local steps = install.new_steps(total)

  if downloading and install.install_xcode(version, build, install_dir, steps) ~= nil then
    note = "Installed Xcode " .. version .. " (" .. build .. ")"
  end

  developer_dir = xcode.require_developer_dir(release, search_path, install_dir, automatic)
  if automatic then
    install.prepare(developer_dir, options, version, steps, downloading)
  end

  return {
    version = version,
    note = note,
  }
end
