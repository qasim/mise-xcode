# mise-xcode

Xcode plugin for the [Mise](https://github.com/jdx/mise) version manager.

> [!NOTE]
> This plugin selects the Xcode your project uses by setting `DEVELOPER_DIR`, and can install it with [xcodes](https://github.com/XcodesOrg/xcodes); see [Installing Xcode](#installing-xcode).

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

## Installing Xcode

The plugin installs Xcode with [xcodes](https://github.com/XcodesOrg/xcodes). Add it to your tools:

```toml
[tools]
xcodes = 'latest'
xcode = '26.2.0'
```

If that Xcode is already installed, the plugin uses it.

### Signing in

xcodes asks for your Apple ID the first time, then remembers it. Where no one can type, such as in CI, sign in once from a terminal first, or set `XCODES_USERNAME` and `XCODES_PASSWORD`, or `FASTLANE_SESSION`.

### Setting up

After installing, the plugin accepts the license and installs the packages Xcode asks for on first launch. This needs your administrator password.

### Options

```toml
[tools]
xcode = { version = '26.2.0', platforms = ['iOS', 'watchOS'], components = ['metalToolchain'], install_dir = '~/Applications' }
```

- `platforms`: simulators to download, such as `iOS`, or `iOS@26.0` for an older one.
- `components`: components to download, such as `metalToolchain`.
- `install_dir`: where Xcode is installed. Defaults to `/Applications`, or `search_path` if you set one.
- `install = false`: only select Xcodes that are already installed.

Platforms and components added later need `mise install --force xcode`.

## Troubleshooting

### ```No Xcode <version> (<build>) found in the search path.```

The plugin was not able to find a valid Xcode installation for the provided version.

Make sure you have it installed and it's available inside the search path. By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk. To have the plugin install it, see [Installing Xcode](#installing-xcode).

The plugin links each mise installation to the selected Xcode's `Contents/Developer` directory. If you move or rename the Xcode application after selecting it, run `mise install` to refresh the link.

### ```No Xcode release matches version <version>.```

According to the plugin, this Xcode version doesn't exist at all.

Double check that the Xcode version you're trying to use is listed in [qasim/Xcode](https://github.com/qasim/Xcode/blob/main/releases.json).

### ```Couldn't download Xcode <version>. xcodes needs to sign in to your Apple ID, and it can't ask you for it here.```

See [Signing in](#signing-in).
