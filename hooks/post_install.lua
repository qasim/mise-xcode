local xcode = require("xcode")

function PLUGIN:PostInstall(ctx)
  local sdk = ctx.sdkInfo[PLUGIN.name]
  local options = ctx.options or {}
  local search_path = options.search_path or "/"
  local release = xcode.release_for_version(sdk.version)
  local developer_dir = xcode.require_developer_dir(release, search_path, xcode.install_dir(options))
  xcode.write_developer_dir_install(sdk.path, developer_dir)
end
