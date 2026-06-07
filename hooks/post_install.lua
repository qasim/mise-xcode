local xcode = require("xcode")

function PLUGIN:PostInstall(ctx)
  local sdk_info = xcode.context_field(ctx, "sdkInfo", {})[PLUGIN.name] or xcode.context_field(ctx, "main", {})
  local version = sdk_info.version or xcode.context_field(ctx, "runtimeVersion", nil)
  local build, resolved_version = xcode.build_for_version(version)
  local options = xcode.context_field(ctx, "options", {})
  local search_path = options.search_path or "/"

  xcode.require_developer_dir(resolved_version, build, search_path)
  xcode.write_build_file(sdk_info.path, build)
end
