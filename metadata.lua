PLUGIN = {
  name = "xcode",
  version = "2.0.0",
  description = "Install Xcode versions and select them by setting DEVELOPER_DIR",
  author = "qasim",
  homepage = "https://github.com/qasim/mise-xcode",
  license = "MIT",
  minRuntimeVersion = "0.3.0",
  -- When a project lists xcodes, it is installed first and used to download Xcode.
  depends = { "xcodes" },
  -- Read when idiomatic_version_file_enable_tools includes xcode.
  legacyFilenames = { ".xcode-version" },
}
