local file = require("file")
local xcode = require("xcode")

function PLUGIN:ParseLegacyFile(ctx)
  local content = file.read(ctx.filepath)
  -- mise ignores errors from this hook, so text that isn't a version is
  -- returned as it is, and installing it fails with a clear error. mise splits
  -- the result at spaces, so spaces are removed.
  local version = xcode.version_file_version(content) or tostring(content or ""):gsub("%s+", "")
  return {
    version = version,
  }
end
