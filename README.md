# Coffee Control

A cup button in the macOS 26 Control Center: while it is on, the Mac does not go to sleep.
A replacement for keeping a terminal open with `caffeinate -d -i`.

- On: `cup.and.heat.waves.fill` (cup with steam), sleep is prevented.
- Off: `cup.and.saucer` (empty cup), normal sleep behavior.

## How it works

```
Control Center ──tap──▶ CoffeeControlExtension.appex (sandboxed, WidgetKit)
                          ToggleCoffeeIntent.perform()
                          └─ open coffeecontrol://on|off ──▶ CoffeeControl.app (windowless agent)
                                                              IOPMAssertion ×2
                                                              writes state.json
                          ◀── waits until state.json says on/off
```

- **`CoffeeControl.app`** is an agent (`LSUIElement`, no window, no Dock icon). While the
  button is on, it holds the same two power assertions as `caffeinate -d -i`:
  `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep`. If it is not running, a
  tap launches it, so no login item is needed.
- **`CoffeeControlExtension.appex`** is a sandboxed WidgetKit extension with a
  `ControlWidgetToggle`. It reads the state from
  `~/Library/Application Support/coffee-control/state.json` through a read-only sandbox
  exception. There is no App Group, because App Groups do not work with ad-hoc signing.
  "On" also requires the recorded app process to still be alive.

### Why the intent runs in the extension, not via `openAppWhenRun`

The usual approach is `openAppWhenRun = true`: the system launches the app and runs the
intent in its process. With ad-hoc signing (no team ID) this does not work, because linkd
rejects the app process:

```
linkd: Unable to get teamId from local.coffeecontrol.CoffeeControl
linkd: Rejecting invalid client due to requiresValidatedBundle … com.apple.linkd.mediator
chronod: Failed to execute LNAction … "AppleEvents communication failed."
```

The toggle then flips for a second and snaps back. So the intent runs in the extension
(`openAppWhenRun = false`), which forwards the request to the app through the
`coffeecontrol://` URL scheme. With a team-signed build (an Apple Development
certificate) you could go back to `openAppWhenRun`, but there is no need to.

### Your own `caffeinate` is not affected

The assertions belong to the `CoffeeControl` process only. They are released when the
button is turned off or the app exits, including on `kill`. Other processes, such as a
`caffeinate -d -i` in a terminal, are neither seen nor touched. The Mac stays awake as
long as any assertion is held.

## Build

Needs the macOS 26 SDK. The Command Line Tools for Xcode 26.x are enough; full Xcode is
not required:

```bash
softwareupdate --list    # "Command Line Tools for Xcode 26.x"
./build.sh install       # build, ad-hoc sign, install ~/Applications/CoffeeControl.app
```

Then: Control Center → Edit Controls → search "Coffee" → drag the button in. If the
search finds nothing, open the widget gallery once (right-click the desktop → Edit
Widgets…).

What `build.sh` does:

- `swiftc` builds the app and the extension. The extension is linked with
  `-e _NSExtensionMain`, as Xcode does; without it WidgetKit never loads the extension.
- **App Intents metadata.** Xcode writes `Metadata.appintents` with
  `appintentsmetadataprocessor`, which the Command Line Tools do not ship. When it is
  missing, `Support/gen_appintents_metadata.py` builds the index from the compiler's
  `.swiftconstvalues`. The format is copied from the system's own `DisplayControls.appex`
  (`SetDarkModeEnabledIntent`). The script supports only what this project needs and
  fails on anything else.
- Ad-hoc signing (`CODESIGN_IDENTITY`, default `-`), extension first, then the app.
- `install` copies the app to `~/Applications`, unregisters the `./build` copy, registers
  the extension with `pluginkit` and stops a running extension process. Otherwise chronod
  keeps running the old binary.

Other commands: `./build.sh` (build only), `./build.sh clean`.

## Manual control and debugging

```bash
open coffeecontrol://on            # also: off, toggle, quit
pmset -g assertions | grep -i coffee
cat ~/Library/Application\ Support/coffee-control/state.json
pluginkit -m -v -i local.coffeecontrol.CoffeeControl.Control
/usr/bin/log show --last 5m --info --style compact \
  --predicate 'process == "chronod" OR process == "CoffeeControlExtension" OR subsystem == "local.coffeecontrol.CoffeeControl"'
```

In zsh, `log` is a shell builtin, so use the full path `/usr/bin/log`.

The URL scheme also works from Shortcuts: an "Open URL" action with `coffeecontrol://toggle`.

## Layout

```
Sources/Shared/   CoffeeState (state.json, process check), ToggleCoffeeIntent
Sources/App/      AppDelegate (URL commands, signals), PowerKeeper (IOPMAssertion)
Sources/Widget/   CoffeeControl (ControlWidgetToggle), CoffeeRemote (URL → app)
Support/          Info.plists, entitlements, App Intents metadata generator
build.sh          build and install
```
