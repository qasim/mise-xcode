local xcode = require("xcode")

function PLUGIN:EnvKeys(ctx)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"
  local build = xcode.read_build_file(ctx.path)
  local developer_dir = xcode.require_developer_dir(ctx.version, build, search_path)

  return {
    {
      key = "DEVELOPER_DIR",
      value = developer_dir,
    },
  }
end
