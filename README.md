# VoragoSync

A native **RuneScape 3** plugin that automatically starts a 24-second Vorago
transition timer from a guarded HP-zero signal. Built for the RuneScape
developer beta; no Alt1 application is needed.

The compact overlay places the countdown **left of the bar on the same row**,
with no heading, audio, or manual Start/Reset buttons. Its four sections are
`pre-ult` (14.4s), `ult` (0.6s), `post-ult` (8.4s), and `tc` (0.6s).
The window fits the visible rows. Debug mode expands below the timer, with
an error row only when needed; normal mode stays a single compact row.

## Developer-beta setup

Follow Jagex's [getting started guide](https://developer.runescape.com/rs/getting-started.html)
and [Accessing the API tutorial](https://developer.runescape.com/rs/tutorial/1helloworld.html)
for beta launch and Import save. Beta progression is separate from live.
Open the beta console with **Alt + the key below Esc**.

Install **PrettyUI, mod.io 6398181**, through the native plugin system first.
VoragoSync declares it as the external `prettyui` dependency and uses the
inspected **1.2.0** API. Developer activation commands do not download missing
dependencies. Do not copy PrettyUI's archive or resources into this plugin.

From this repository's root, after confirming your **beta** cache destination:

```powershell
$destination = 'C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\voragosync'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath .\main.lua, .\plugin.json -Destination $destination -Force
Copy-Item -LiteralPath .\src -Destination $destination -Recurse -Force
```

Only **`main.lua`, `plugin.json`, and the `src` directory** are needed at runtime.
Keep `src` as a subdirectory; do not flatten its files into the plugin root.
Node.js, tests, and a build step are not required to load the plugin. If your cache is
elsewhere, use the client loading-screen cog to locate the beta cache with
`.jcache` files. Nothing in this repository installs game files automatically.

If migrating from the old `voragotag` developer plugin, **disable it before
enabling VoragoSync** to avoid duplicate timers:

```text
poff voragotag
```

Leave the old folder intact. The new identity can start with fresh preference
defaults; no settings migration is required. Refresh the manifest and activate:

```text
prf
plist
pon voragosync
```

After copying an update, use `prf` followed by `prl voragosync`. Disable the
plugin with `poff voragosync`.

## Settings and usage

Monitoring starts automatically. Open **Plugin Hub > Manage > VoragoSync >
Settings** using the plugin's Settings icon.

| Setting                   | Default | Effect                                                                                                   |
| ------------------------- | ------- | -------------------------------------------------------------------------------------------------------- |
| Smooth countdown          | Off     | Use 0.1s steps throughout, rather than 0.6s long sections and 0.1s ult/tc.                               |
| Remove bar sections       | Off     | Show a single gapless gold bar without segment labels; keep the countdown.                               |
| Only show in Vorago arena | Off     | Show with positive Vorago HP or an active countdown; use a 5s hide buffer and 10s reappearance cooldown. |
| Debug mode                | Off     | Dev builds only: show Activity, Current HP, and Armed state below the bar.                               |

All settings persist and apply mid-countdown without resetting elapsed time.
The uniform bar follows raw elapsed time independently of countdown snapping.
Both bar styles hold full for one second at completion, then clear.
Operational errors are always logged, but appear in the overlay only with
Debug mode on. Settings-save failures also show a message in Settings.

**Only show in Vorago arena** shows the overlay while a valid, active Vorago
boss bar has positive HP or a countdown (including its full-bar hold) is active.
Zero-HP bar readings cannot reactivate an idle overlay after the fight.
Once neither is active, it stays visible for **five more seconds** before
fading out. While visible, renewed activity restarts that buffer. After it
disappears, a **ten-second cooldown** blocks automatic reappearance and ignores
transient HP-bar readings without queuing another appearance. A fresh sample
is required after the cooldown. Losing the visible overlay during loading or
a cutscene also starts this cooldown. Vorago's NPC presence is not
required, so phase transitions do not hide an active timer, and the lobby
NPC alone does not show it. Monitoring continues while hidden, and Settings
remains accessible. This is an activity proxy, not an arena boundary check:
teleporting out mid-countdown can leave the overlay visible until the timer,
hold, buffer, and fade-out finish. Reloading clears visibility history.
The overlay fades in over **one second** whenever it first appears or returns from
being hidden, and fades out over **one second** after the buffer. If activity returns
during fade-out, it smoothly reverses from its current opacity. Fading does not
delay the countdown; the window frame, text, and bars fade together.

To move the overlay, **unlock RuneScape's interface** using the game's normal
interface-lock control; there is no separate plugin setting. A full-width brown
drag bar, twelve units tall, appears **above the entire gold frame**, using RuneScape's move cursor.
It adds no padding inside the timer and disappears completely when locked.
Drag that handle
to move the window, or drag any side or corner to resize it. There is no blue
outline. The bars stretch horizontally and vertically to fill the resized
timer area, with labels and the countdown centered vertically. Text stays
the same size.
The overlay stays visible and opaque while unlocked, even outside the arena.
Position and resized dimensions are saved on release and restored on reload,
with screen bounds and minimum readable dimensions enforced.
While unlocked, space is reserved above the window to keep the drag bar
accessible at the top of the screen; this does not overwrite its saved layout.

Lock RuneScape's interface again to hide the handle and disable resizing,
restoring click-through and normal arena visibility/fades. **Reset to defaults**
in the plugin's Settings resets all display preferences, size, and position.
Moving, resizing, and resetting settings never reset a countdown or change
RuneScape's global interface-lock state.
The overlay uses RuneScape's thin HUD-style frame, with four-unit borders
and a matching brown editing header rather than the chunky modal-dialog frame.
The default window is 500 by 48 interface units, with six-unit vertical padding.
The countdown uses a compact 56-unit column, four units from the left edge of
the content and six units from the bars. It can be resized down to 340 units wide; its minimum height fits
the visible rows. Existing saved sizes are preserved, so unlock the interface
to shrink an existing layout further. Editing mode and disabling arena-only
visibility bypass the automatic reappearance cooldown.

`src/build.lua` explicitly sets `isDevBuild = true`; this is **not automatic
beta-client detection**. A non-dev build sets it to `false`, hides Debug mode,
and ignores any saved debug preference. All ordinary settings and the
manifest's `hasSettingsIcon: true` remain enabled in either build.

## Detection and current scope

The HP trigger requires a fresh, valid, named Vorago activity observation
changing from positive HP to exactly zero. Startup zero, sustained zero, and
invalid, hidden, missing, or stale observations do not trigger. Checks run
about every 50ms on available draw frames; elapsed draw time drives the timer.
Edges during a countdown or its completion hold are consumed, never queued.

The same HP trigger covers Scopulus: the activity HP bar is present during
that phase and reflects Scopulus HP, as observed in-game by the user. There is
no separate minion-presence or disappearance trigger. Detection still requires
the same valid Vorago encounter and a living player.

Ordinary boss-bar/NPC disappearance during jumps or dropdown does not cancel
an already-running timer. Leaving active game state, reconnecting, plugin UI
loss, or disabling the plugin cancels it. See [detection and compatibility
details](docs/technical.md) for freshness, lifecycle, and PrettyUI constraints.

The HP trigger, including a P2 HP signal, has **user-reported beta successes**.
Not every rotation or death/teleport edge case has been validated. The new
PrettyUI rendering, settings interaction, and client-side teardown still need
an in-game check: confirm the layout, toggle settings during a countdown,
reload to check persistence, and reopen Settings to check cleanup.

## Development

### Repository layout

```text
main.lua            Native plugin entrypoint (startup and shutdown hook)
plugin.json         Native plugin manifest
src/
  app.lua           Application lifecycle, monitoring, settings, and UI
  build.lua         Explicit dev/release build flag
  detector.lua      Guarded HP transition detection
  encounter.lua     Vorago presence and player life-point reads
  health_probe.lua  Activity HP reads and validation
  timer.lua         Countdown state and display math
tests/              Lua behavioral suites and TypeScript harness
docs/               Detection and API compatibility notes
```

`main.lua` starts `src/app.lua` and exposes its cleanup callback as the native
`PluginShutdown` hook. Each start creates fresh application state, even when
the Lua module is cached. Internal imports use plugin-root-relative paths
without extensions, such as `require("src/timer")`, as required by the
[native loader](https://developer.runescape.com/rs/structure.html#dependencies).

### Local checks

Use **Node.js 22 or newer**:

```powershell
npm ci
npm run check
```

`npm test` runs the Lua 5.4 WebAssembly behavioral suites through Wasmoon.
`npm run typecheck` checks the TypeScript harness, and `npm run format:check`
checks supported text formats with Prettier (`npm run format` applies fixes).
There is no bundled application or generated runtime build.

GitHub Actions runs `npm test` on Node.js 22 for all pull requests and pushes
to `main`. Merging into `main` requires a pull request, a passing `Tests` check,
and a branch up to date with `main`; reviewer approval is not required.
These protections apply to administrators too, and force pushes and branch
deletion are blocked.

Dependabot checks npm dependencies and GitHub Actions weekly. Minor and patch
version updates are grouped into one pull request per ecosystem; major updates
get separate pull requests. See [the configuration](.github/dependabot.yml).
The external PrettyUI plugin is managed manually, not by Dependabot.

Tests cover guarded reads, HP triggers, lifecycle resets, display-setting
combinations, mid-run toggles, bar geometry, persistence and
error reporting, arena visibility, dev/non-dev settings, dependency failures, and wrapper
cleanup. PrettyUI tests use a 1.2.0 contract double, not the game's renderer.
Placement coverage includes native interface-lock changes and unavailable
signals, click-through, drag/resize capture, all eight resize directions, saved
geometry, responsive bars, reset behavior, viewport clamping, and storage failures.
Default timing is compared at thousands of boundaries against a small,
attributed [test-only reference](tests/reference/timer.ts) from VoragoTag.

## License and dependencies

VoragoSync is [MIT licensed](LICENSE), extracted from the native VoragoTag
prototype. [PrettyUI](https://github.com/PrettyRS/prettyui) is a separately
installed external dependency licensed under
[BSD-3-Clause](https://github.com/PrettyRS/prettyui/blob/main/LICENSE);
none of its implementation or resources are vendored here.
Its [website](https://prettyui.j3.gg/) may document newer APIs than 1.2.0.
