# Coffee Control: a "stay awake" button in Control Center

## Goal

A nice-looking cup button in the macOS Control Center. Tap it and the Mac stays awake.
Tap it again and sleep is allowed again. The button should show its state, on or off
(for example, the SF Symbol `cup.and.heat.waves.fill` when on and `cup.and.saucer` when
off). Right now the user keeps a terminal open with `caffeinate -d -i`; this button
should replace it.

## Known facts (2026-11-10)

- macOS 26.5.1 (Tahoe), Apple Silicon MacBook.
- Only the Command Line Tools are installed (`/Library/Developer/CommandLineTools`).
  No full Xcode, `xcodebuild` is unavailable.
- No signing certificates (`security find-identity -v -p codesigning` is empty) and no
  Xcode team (Apple ID personal team).
- `caffeinate -d -i` (the user's terminal) and several `caffeinate -i -t 300` processes
  are running. Do not touch them.

## Options (evaluate and pick one)

1. **Native app with a ControlWidgetToggle (WidgetKit).** A real toggle with state and
   an icon. On macOS 26, third-party controls can be added to Control Center.
   - Needs full Xcode (free in the App Store, installed by the user) and signing: a free
     Apple ID personal team, or ad-hoc if that is enough for a widget extension. Find
     out the minimum required.
   - The widget extension is sandboxed and cannot run `caffeinate`. The main app process
     should keep the Mac awake with `IOPMAssertionCreateWithName` (a windowless
     `LSUIElement` agent), and the toggle's intent should run in the app process. Find
     out which App Intents mechanism fits.
   - The button state comes from shared storage (App Group) or from the app itself.
2. **Shortcuts + "Run Shell Script" in Control Center.** Works without Xcode and can use
   a cup icon, but the button has no state. Fallback if option 1 is not possible.
3. **Existing free apps** (Amphetamine, KeepingYouAwake, Open Caffeine). Check whether
   any of them ships its own Control Center control on macOS 26. If one does and it
   looks good, nothing needs to be written.

## Work order

1. Research first: option 3, then whether option 1 is realistic without a paid
   developer account. Send the findings and a recommendation to the coordinator.
2. If Xcode or an Apple ID sign-in is needed, ask the coordinator to pass that on to
   the user. Do not install anything or sign in yourself.
3. Keep the code in this folder. Run `git init`; create a GitHub repository only if the
   coordinator confirms.

Coordinator rules: `~/.claude/CLAUDE.md`, coordinator session section.
