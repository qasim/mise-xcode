local xcode = require("xcode")

function PLUGIN:PostInstall(ctx)
  local sdk_info = xcode.context_field(ctx, "sdkInfo", {})[PLUGIN.name] or xcode.context_field(ctx, "main", {})
  local version = sdk_info.version or xcode.context_field(ctx, "runtimeVersion", nil)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"
  local install_dir = xcode.install_dir(options)
  local build, resolved_version, record = xcode.build_for_version(version, search_path, install_dir)

  local developer_dir = xcode.require_developer_dir(resolved_version, build, search_path, record, install_dir)
  xcode.write_developer_dir_install(sdk_info.path, developer_dir)
end
