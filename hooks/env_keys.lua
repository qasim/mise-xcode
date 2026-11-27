local xcode = require("xcode")

function PLUGIN:EnvKeys(ctx)
  return {
    {
      key = "DEVELOPER_DIR",
      value = xcode.developer_dir_for_install(ctx.path),
    },
  }
end
