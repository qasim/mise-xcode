local xcode = require("xcode")

function PLUGIN:EnvKeys(ctx)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"
  local build = xcode.read_build_file(ctx.path)
  local record = xcode.record_for_version_and_build(ctx.version, build)
  local developer_dir = xcode.require_developer_dir(ctx.version, build, search_path, record)

  return {
    {
      key = "DEVELOPER_DIR",
      value = developer_dir,
    },
  }
end
