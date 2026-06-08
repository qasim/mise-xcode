local xcode = require("xcode")

function PLUGIN:PreInstall(ctx)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"
  local build, version, record = xcode.build_for_version(ctx.version, search_path)

  xcode.require_developer_dir(version, build, search_path, record)

  return {
    version = version,
    note = "Using local Xcode build " .. build,
  }
end
