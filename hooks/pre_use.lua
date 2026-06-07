local xcode = require("xcode")

function PLUGIN:PreUse(ctx)
  local version = xcode.resolve_version(ctx.version)
  if version == nil then
    return {
      version = ctx.version,
    }
  end

  return {
    version = version,
  }
end
