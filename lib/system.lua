-- The macOS tools and folders the plugin uses, in one place. Absolute paths
-- keep a changed PATH from substituting them.
return {
  applications = "/Applications",
  archiveutil = "/usr/bin/archiveutil",
  codesign = "/usr/bin/codesign",
  devtoolssecurity = "/usr/sbin/DevToolsSecurity",
  dseditgroup = "/usr/sbin/dseditgroup",
  getconf = "/usr/bin/getconf",
  mdfind = "/usr/bin/mdfind",
  spctl = "/usr/sbin/spctl",
  sudo = "/usr/bin/sudo",
  sw_vers = "/usr/bin/sw_vers",
  xcode_select = "/usr/bin/xcode-select",
  xcodebuild = "/usr/bin/xcodebuild",
  xcrun = "/usr/bin/xcrun",
  xip = "/usr/bin/xip",
}
