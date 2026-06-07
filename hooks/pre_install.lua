local xcode = require("xcode")

function PLUGIN:PreInstall(ctx)
  local build, version = xcode.build_for_version(ctx.version)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"

  xcode.require_developer_dir(version, build, search_path)

  return {
    version = version,
    note = "Using local Xcode build " .. build,
  }
end
