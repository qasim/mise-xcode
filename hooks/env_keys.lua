local xcode = require("xcode")

function PLUGIN:EnvKeys(ctx)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"
  local developer_dir = xcode.developer_dir_for_install(ctx.path, search_path)

  return {
    {
      key = "DEVELOPER_DIR",
      value = developer_dir,
    },
  }
end
