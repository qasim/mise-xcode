# mise-xcode

Xcode plugin for the [Mise](https://github.com/jdx/mise) version manager.

> [!NOTE]
> This plugin manages your actively selected Xcode version. It can also download missing Xcode versions when [xcodes](https://github.com/XcodesOrg/xcodes) is available; see [Installing missing Xcodes](#installing-missing-xcodes).

## Install

### Option 1: Specify the plugin inside your project's [configuration](https://mise.jdx.dev/configuration.html)

```toml
[plugins]
xcode = 'https://github.com/qasim/mise-xcode'
```

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

### Selecting the latest stable version of a major Xcode

Using version `26` will select the latest stable `26.x.y` release known by the plugin.

```console
foo@bar:~$ mise use xcode@26
mise ~/foo/bar/mise.toml tools: xcode@26.5.0
```

### Selecting Xcodes within a specific search path

By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.
You can specify a custom search path via the `search_path` parameter:

```toml
[tools]
xcode = {version='16.0.0', search_path='/Applications'}
```

### Installing missing Xcodes

When the requested Xcode is not on disk and [xcodes](https://github.com/XcodesOrg/xcodes) is available, the plugin uses it to download Xcode with your saved Apple ID session. The plugin then unpacks it, checks that it is the requested build and signed by Apple, and installs it as `Xcode-<version>.app`. Without xcodes, the plugin only selects Xcodes you have installed yourself.

xcodes finds each Xcode in the list from [xcodereleases.com](https://xcodereleases.com/). A release that isn't there yet, such as a beta Apple published today, is downloaded from Apple's own list instead, which xcodes reads once you're signed in. That download may be the Universal Xcode rather than the Apple silicon one, which is larger but works the same.

```toml
[tools]
xcodes = 'latest'
xcode = '26.2.0'
```

The first download may ask you to sign in to your Apple ID, so run it in a terminal. Without a terminal, such as in CI or from an agent, set `XCODES_USERNAME` and `XCODES_PASSWORD`, or sign in once from a terminal first; xcodes remembers the session.

After installing, and whenever it selects an Xcode that has not been set up yet, the plugin accepts the license and installs the packages Xcode would otherwise ask for on first launch, without opening Xcode. This asks for your administrator password, so it also needs a terminal the first time.

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

Make sure you have it installed and it's available inside the search path. By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.

The plugin links each mise installation to the selected Xcode's `Contents/Developer` directory. If you move or rename the Xcode application after selecting it, run `mise install` to refresh the link.

### ```No Xcode release matches version <version>.```

According to the plugin, this Xcode version doesn't exist at all.

Double check that the Xcode version you're trying to use is accounted for at [xcodereleases.com](https://xcodereleases.com/).
