# mise-xcode

A mise plugin, written in Lua, that selects Xcode versions and installs missing ones with xcodes. mise runs plugins on Lua 5.1, so the code and its tests stay within Lua 5.1.

- `hooks/`: the entry points mise calls, such as `PreInstall` and `EnvKeys`.
- `lib/`: the plugin's modules. `xcode.lua` finds and selects Xcodes, `install.lua` downloads and sets them up.
- `tests/`: the tests, run with `mise run test`.

Before calling a change done, run `mise run test` and `mise run lint`, and both must pass.

## Tests

Tests prove what the plugin does for the people using it, so they keep passing when the code is reorganized and fail when its behavior breaks.

Before adding a test, answer three questions. If any has no good answer, don't add it.

1. What behavior does it protect? Something a user or another program can observe: what a hook returns, what it prints, the commands it runs on the Mac, an error message.
2. What credible mistake would make it fail?
3. Why do the existing tests miss that mistake?

How tests are written:

- **Through the hooks.** Run a hook the way mise does, with `world:hook("PreInstall", ctx)`, and check what comes out. Don't test private helpers. Rules that are easiest to check with a table of examples, such as the ways a version can be written, can be tested through the module function that holds them.
- **Against the fake Mac.** `tests/support/mac.lua` replaces mise's modules and the Mac behind them with a world the test describes: which Xcodes are installed, what xcodes lists, whether someone can answer prompts. It records what the plugin does to the Mac and what it prints, as a transcript. Only mise's modules are faked. Never add a hook, flag or export to the plugin just so a test can reach it.
- **Expected values come from the requirement**, written out by hand, never computed by the code under test or copied from its output.
- **A new command gets modeled.** The fake Mac fails on commands it doesn't know. When the plugin needs a new one, teach the fake Mac what it does on a real Mac.
- **A bug fix starts with a test that fails** for the reason the bug describes. Then fix the code and watch it pass. If no practical test can show the bug, say so, and describe how the fix was checked instead.
- **Check that a new test can fail.** Break the behavior it protects and watch it fail, then restore the code.
- **Keep tests fast and certain.** No real network, downloads, timers or sleeps.

What isn't tested here: downloading real Xcode archives and Apple sign-in, which need an Apple ID and gigabytes. The fake Mac covers how the plugin drives them.
