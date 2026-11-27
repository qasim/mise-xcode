local file = require("file")
local xcode = require("xcode")

function PLUGIN:ParseLegacyFile(ctx)
  local content = file.read(ctx.filepath)
  -- mise ignores errors raised here, so a version this can't read is passed on
  -- as written, and installing it fails where people see why. mise splits the
  -- result at spaces, so they are removed.
  local version = xcode.version_file_version(content) or tostring(content or ""):gsub("%s+", "")
  return {
    version = version,
  }
end
