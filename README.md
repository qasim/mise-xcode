# mise-xcode

Xcode plugin for the [Mise](https://github.com/jdx/mise) version manager.

> [!NOTE]
> This plugin selects the Xcode your project uses by setting `DEVELOPER_DIR`. When that Xcode is missing and [xcodes](https://github.com/XcodesOrg/xcodes) is available, it downloads and sets it up too; see [Installing missing Xcodes](#installing-missing-xcodes).

## Install

### Option 1: Specify the plugin inside your project's [configuration](https://mise.jdx.dev/configuration.html)

```toml
[plugins]
xcode = 'https://github.com/qasim/mise-xcode'
```

To pin a release of the plugin, add its tag, such as `https://github.com/qasim/mise-xcode#v2.0.0`.

### Option 2: Install the plugin globally

```bash
mise plugins install xcode https://github.com/qasim/mise-xcode
```

## Use

### Selecting the latest stable version of Xcode

```bash
mise use xcode@latest
```

or

```toml
[tools]
xcode = 'latest'
```

This resolves to the latest stable Xcode version known by the plugin.

### Selecting a specific version of Xcode

```toml
[tools]
xcode = '16.0.0'
```

### Selecting a pre-release of Xcode

```toml
[tools]
xcode = '27.3.0-beta.2'
```

Run `mise ls-remote --prerelease xcode` to see every pre-release.

### Selecting the latest stable version of a major Xcode

Using version `26` will select the latest stable `26.x.y` release known by the plugin.

```console
foo@bar:~$ mise use xcode@26
mise ~/foo/bar/mise.toml tools: xcode@26.5.0
```

### Using an .xcode-version file

The plugin reads the `.xcode-version` file that xcodes and fastlane use, once you turn it on in mise:

```toml
[settings]
idiomatic_version_file_enable_tools = ['xcode']
```

The file holds one version, written as xcodes reads it, such as `26.0` or `14.0b6`, or as Apple writes it, such as `14.0 Beta 6`. As with xcodes, the version is exact: `26` means Xcode 26.0.0, not the newest Xcode 26. A version in `mise.toml` takes precedence over the file.

### Selecting Xcodes within a specific search path

By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.
You can specify a custom search path via the `search_path` parameter:

```toml
[tools]
xcode = {version='16.0.0', search_path='/Applications'}
```

### Selecting an Xcode outside the search path

To use an Xcode the plugin doesn't find, link it with mise:

```bash
mise link xcode@26.2.0 /Volumes/Tools/Xcode-26.2.app
```

## Installing missing Xcodes

When the Xcode you ask for isn't installed, the plugin downloads it with [xcodes](https://github.com/XcodesOrg/xcodes), so add xcodes to your tools:

```toml
[tools]
xcodes = 'latest'
xcode = '26.2.0'
```

xcodes looks each release up in the list from [xcodereleases.com](https://xcodereleases.com/). A release that isn't there yet, such as a beta Apple published today, comes from Apple's own list instead, and may be the Universal Xcode rather than the Apple silicon one, which is larger but works the same.

The plugin then unpacks the download, checks that it's the build you asked for and that Apple signed it, and installs it as `Xcode-<version>.app`. Without xcodes, the plugin only selects Xcodes you have installed yourself.

### Signing in to your Apple ID

Downloading Xcode needs your Apple ID. Run `mise install` in a terminal, and xcodes asks you to sign in the first time, then remembers it. Where no one can type, such as in CI or from an agent, either:

- sign in once from a terminal first, or
- set `XCODES_USERNAME` and `XCODES_PASSWORD`, or
- set `FASTLANE_SESSION` to a session from `fastlane spaceauth`.

### Setting up Xcode

An Xcode can't be used from the command line until it's set up: its license accepted and its first-launch packages installed, which Xcode does when you first open it. So after installing, and whenever it selects an Xcode that isn't set up yet, the plugin does the same without opening Xcode. It accepts the license, installs those packages, and turns on developer mode so debugging doesn't ask for your password. Like Xcode, it needs your administrator password for this, so the first time, run it in a terminal.

### Options

These options change what the plugin installs:

```toml
[tools]
xcode = { version = '26.2.0', platforms = ['iOS', 'watchOS'], components = ['metalToolchain'], install_dir = '~/Applications' }
```

- `platforms`: simulator platforms to download with `xcodebuild -downloadPlatform`, such as `iOS` or `watchOS`. A plain name gets the simulator that matches the Xcode. Add an exact version, such as `iOS@26.0`, for an older simulator to test on.
- `components`: extra components to download with `xcodebuild -downloadComponent`, such as `metalToolchain`.
- `install_dir`: where new Xcodes are installed. Defaults to `search_path` if you set one, otherwise `/Applications`.
- `install = false`: never download, set up or add to Xcode; only select it.

mise treats an installed version as done, so platforms or components added later are downloaded only after `mise install --force xcode`. Ones already installed are skipped.

## Troubleshooting

### ```No Xcode <version> (<build>) found in the search path.```

The plugin was not able to find a valid Xcode installation for the provided version.

Make sure you have it installed and it's available inside the search path. By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk. To have the plugin download it, add xcodes to your tools; see [Installing missing Xcodes](#installing-missing-xcodes).

The plugin links each mise installation to the selected Xcode's `Contents/Developer` directory. If you move or rename the Xcode application after selecting it, run `mise install` to refresh the link.

### ```No Xcode release matches version <version>.```

According to the plugin, this Xcode version doesn't exist at all.

Double check that the Xcode version you're trying to use is listed in [qasim/Xcode](https://github.com/qasim/Xcode/blob/main/releases.json).

### ```Couldn't download Xcode <version>. xcodes needs to sign in to your Apple ID, and it can't ask you for it here.```

xcodes needs your Apple ID, and nothing could be typed into this run. See [Signing in to your Apple ID](#signing-in-to-your-apple-id).
