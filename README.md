# VoragoSync

A native **RuneScape 3** plugin that automatically starts a 24-second Vorago
transition timer from a guarded HP-zero signal. Built for the developer beta;
no Alt1 application is needed.

The compact HUD shows a countdown beside four sections: `pre-ult` (14.4s),
`ult` (0.6s), `post-ult` (8.4s), and `tc` (0.6s). It supports smooth countdowns,
a single-bar display, and optional encounter-only visibility with fades.
Unlock RuneScape's interface to move or resize it; settings and layout persist.

## Getting started

1. Set up the [RuneScape developer beta](https://developer.runescape.com/rs/getting-started.html)
   and install **PrettyUI, mod.io 6398181**, through the native plugin system.
2. Download a ZIP from [Releases](https://github.com/fletchto99/VoragoSync/releases)
   and extract it into your beta cache's `dev_plugins\voragosync` folder.
   See the [installation guide](docs/guide.md#developer-beta-setup) for exact
   Windows commands and source installs.
3. Open the beta console with **Alt + the key below Esc**, then enable it:

   ```text
   prf
   pon voragosync
   ```

Only `main.lua`, `plugin.json`, and `src` are needed at runtime. PrettyUI is
installed separately; Node.js is only needed for development.
Reload an updated copy with `prl voragosync`, or disable it with `poff voragosync`.

## Usage

Monitoring starts automatically. Open **Plugin Hub > Manage > VoragoSync >
Settings** to configure the display, see monitoring status, reset only the
layout, or reset all settings.

**Auto-hide when inactive** is off by default. When enabled, positive Vorago
HP or an active countdown keeps the overlay visible, followed by a five-second
buffer and one-second fade-out. A ten-second cooldown prevents immediate
reappearance. This uses boss activity, not arena coordinates.
**Single-bar display** replaces the segmented bar with one gapless bar.
Existing saved preferences keep their values under the clearer labels.

Unlock RuneScape's interface to reveal the brown drag handle and resize from any
edge or corner. Lock it again to restore click-through and normal visibility.
See the [settings and usage guide](docs/guide.md#settings-and-usage) for details,
including [current in-game verification limits](docs/guide.md#detection-and-current-scope).

## Development

With **Node.js 22 or newer**:

```powershell
npm ci
npm run check
```

- [Developer and release guide](docs/guide.md#development)
- [Detection, lifecycle, and PrettyUI compatibility](docs/technical.md)

## License

VoragoSync is [MIT licensed](LICENSE).
[PrettyUI](https://github.com/PrettyRS/prettyui) is a separately
installed [BSD-3-Clause](https://github.com/PrettyRS/prettyui/blob/main/LICENSE)
dependency; none of its implementation or resources are vendored here.
