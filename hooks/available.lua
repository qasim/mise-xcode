local xcode = require("xcode")

function PLUGIN:Available(ctx)
  return xcode.available_versions()
end
