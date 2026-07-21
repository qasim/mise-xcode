# mise-xcode

Xcode plugin for the [Mise](https://github.com/jdx/mise) version manager.

> [!NOTE]
> This plugin manages your actively selected Xcode version, but does not take the responsibility of downloading or installing Xcode versions themselves.

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

## Troubleshooting

### ```No Xcode <version> installation found within search path.```

The plugin was not able to find a valid Xcode installation for the provided version.

Make sure you have it installed and it's available inside the search path. By default, this plugin looks for Xcode installations with a search path of `/`, i.e. anywhere on your disk.

The plugin links each mise installation to the selected Xcode's `Contents/Developer` directory. If you move or rename the Xcode application after selecting it, refresh the link:

```bash
mise install --force xcode@<version>
```

### ```No Xcode version exists that corresponds to <version>.```

According to the plugin, this Xcode version doesn't exist at all.

Double check that the Xcode version you're trying to use is accounted for at [xcodereleases.com](https://xcodereleases.com/).
