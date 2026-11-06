# Detection and compatibility

## Activity HP

The activity reader uses the named `.value` fields below, checking domain,
value type, integer range, maximum, hide state, and activity name.

| Field                                                     | Observed ID | Type    |
| --------------------------------------------------------- | ----------- | ------- |
| `var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_PROGRESS`     | `-53293`    | INTEGER |
| `var.VarPlayer.ACTIVITY_PROGRESS_BAR_ACTIVE_MAX_PROGRESS` | `-53295`    | INTEGER |
| `var.VarPlayer.ACTIVITY_PROGRESS_BAR_HIDE_PROGRESS`       | `-53294`    | INTEGER |
| `var.VarClient.ACTIVITY_PROGRESS_BAR_ACTIVE_NAME`         | `7157`      | STRING  |

The HP edge requires `Vorago` after stripping markup, surrounding whitespace,
and case differences, plus the same maximum and primary-container
availability/type. Hidden, inactive, restricted, invalid, wrong-type, or
non-Vorago observations discard history. Optional fill/name visibility is
not an identity check because a fill can change visibility at zero.

Only type, visibility, and restriction metadata are read from these UI
components:

| UI symbol                                   | Observed combined ID |
| ------------------------------------------- | -------------------- |
| `ACTIVITY_PROGRESS_BAR__CONTAINER`          | `76742679`           |
| `ACTIVITY_PROGRESS_BAR__PROGRESS_BAR`       | `76742671`           |
| `ACTIVITY_PROGRESS_BAR__ACTIVITY_NAME_TEXT` | `76742682`           |

Stable lack of optional UI exposure does not create an attack-target
dependency. The plugin does not use UI text traversal, packed `ACTIVE_INFO`,
secondary/shield values, target health, guessed phase IDs, or animation and
movement heuristics. Static animation assets cannot establish a live jump.

## Encounter guards and lifecycle

Scopulus uses the same activity HP edge as other phases: the user observed
that the bar remains present and reflects Scopulus HP. No Scopulus NPC query
or disappearance heuristic is used.

Each fresh observation follows these guards before accepting an HP edge:

1. Query `NPCList.ByName("Vorago")` and check valid identities. If none remains,
   disarm detection.
2. Check typed own-player `var.VarPlayer.LIFEPOINTS.value` (observed ID `13655`).
   Zero disarms detection even if Vorago and the activity bar remain loaded.
   Missing or invalid LP is an explicit error, not assumed alive or zero.
3. A fresh positive-to-zero HP change triggers once if the same Vorago identity
   set remains, the player is alive, and the timer is idle.

"Present" means available as a valid entity, not camera pixels or line of sight.
Death and encounter loss are recognized only when the client updates the
relevant signals.

Checks occur every 50ms on the next draw frame, after server delivery.
Observations over 0.6s apart are not joined into an edge: a stalled/background
client may miss a trigger instead of inventing a late one. Countdown progress
uses `Event.Draw.timeDeltaSecs`, not frame counts.

Every actual timer start centrally clears HP history. Active-run and
one-second full-hold edges are consumed, not restarted or queued. A fresh
positive observation can arm a future run. Encounter identity changes,
death/unreadable LP, failed observations, stale samples, and ordinary
boss/bar loss disarm detection without cancelling an already-running timer.
Loading/logout/reconnect, plugin UI loss, and shutdown still cancel.
Settings remounts and display changes do not reset timing or detection.
Repeated genuine monitoring errors are reported without logging on every poll.

The opt-in `onlyInArena` display preference uses the existing 50ms activity
sample and timer state, without extra queries. A valid, active bar named
Vorago (case-insensitive after normalizing markup/whitespace) with positive HP,
or a non-idle timer, keeps the overlay visible. Late/stale zero-HP readings do
not reset the buffer or reactivate an idle overlay after a fight.
NPC presence is not a visibility condition:
Vorago is also present in the lobby and absent between phases until his next
drop. The countdown and its one-second full-bar hold stay visible without
either Vorago or his bar.

When neither the bar nor timer is active, a five-second grace period begins
on the draw that observes inactivity. Subsequent draw deltas expire it, so a
long frame ending a timer cannot consume the new buffer. Renewed activity
resets the grace period. Invalid/hidden/unrelated bar readings do not keep
refreshing it. Visibility history is maintained even with the setting off;
toggling display settings does not restart the buffer. UI loss, leaving
active game state, and shutdown clear it along with detection/timer state.

After an actually visible overlay finishes fading out or is unloaded, arena-only
mode starts a ten-second reappearance cooldown. It advances on draw deltas even
while outside active game state. Activity samples during cooldown do not build
visibility grace; a fresh monitoring sample is required at or after expiry.
This avoids replaying the transient full-HP bar after the end-of-fight cutscene.
Detection and countdown time still advance normally; the cooldown gates only
automatic visibility. Native interface editing and always-visible mode bypass
it, and restarting the plugin clears this non-persistent history.

Hiding affects only the overlay root, not monitoring or widget ownership.
Settings remains accessible and monitoring errors continue to be logged.
Overlay error messages are shown only in Debug mode.
This is not a coordinate-based arena boundary check: teleporting out during
a countdown can leave the overlay visible through the timer, hold, buffer, and fade-out.

Layer alpha does not fade child components. The overlay instead applies an
opacity multiplier to each native text/rectangle and PrettyUI frame sprite,
preserving each component's original alpha. Hidden bar styles and debug labels
are included so revealing them mid-fade does not flash opaque content.
On initial display and each hidden-to-visible transition, opacity starts at
zero and rises linearly to one over one second of subsequent draw time.
After the grace period expires, opacity falls to zero at the same rate,
with the root remaining visible until fade-out completes. A change of direction
preserves current opacity and starts moving toward the new target on subsequent
draws. This lets returning activity or Settings changes reverse an in-progress
fade without flashing. Time spent hidden does not advance fade-in. Remaining
visible (including activity returning within the grace period) does not restart
it. A recreated window starts transparent; lifecycle teardown remains immediate.
Animation does not change timer/detection state or the separate Settings view.

## Overlay placement

Placement follows `var.VarPlayer.TOPLEVEL_V2_CUSTOMIZATION_LOCK.value`:
`0` is unlocked and `1` is locked. This is RuneScape's own interface-lock
control, read on draw frames and before starting, continuing, or completing a
drag or resize. The plugin never writes that variable.

Unavailable, invalid, or throwing lock reads keep dragging disabled and log
one message until the error changes or recovers. An unfinished drag is
cancelled without saving when the lock state becomes unreadable; the timer
and encounter monitoring continue. Normal native locking finishes and saves
an active drag.

The panel roots, content containers, scroll content, frame sprites, text, and
bars are click-through. PrettyUI 1.2.0 does not export `Panel:SetClickthrough`;
the checked `dock.scroll` and `overlay.scroll` controllers provide it and update
their scroll root, viewport, content, and scrollbar input states together.
Unlocking shows a full-width, twelve-unit brown drag bar immediately above the
entire HUD frame. It is a sibling layer, not a child clipped by the panel root,
and does not overlap the frame or consume timer content space. A brown rectangle
(`#311F12`, sampled from the native interface reference) fills its interior,
with the same `HUD_WINDOW` top, side, and corner sprites
as the panel at their native four-unit thickness. The panel's top border is
the separator. It uses the `TOPLEVEL_V2_MOVE` cursor, and only this handle
initiates movement. Unlocking also enables
four edge and four corner resize surfaces, with native horizontal, vertical,
and diagonal cursors around the combined header/window bounds. The drag hit area
excludes their five-unit inset, so the upper edge and corners remain resizable.
Locking hides the bar and its input surface without changing the timer's layout.
Unlocking forces the overlay visible and opaque without
changing the countdown, detector, or ordinary five-second visibility history.
Locking restores those visibility rules; it does not start a new grace period.

Each input surface is a separate native layer on the same parent as the window.
On click it records `Mouse.GetPosition()` and calibrates pixels per interface
unit against the clicked point's global UI position, accounting for UI/display
scaling before capture expands to the parent's bounds. Holds use mouse deltas
from that original grab point, not the hook coordinates whose origin can change
after expanding capture. The window and header move together, clamped within
their parent's bounds. Unlocked placement and resizing reserve twelve units
above the window so the header stays reachable, without overwriting saved
geometry just because the native lock changed. Unavailable pointer/scale data
reports an error instead of guessing.
Only the active surface captures input during a gesture; other handles are
disabled. Resizing keeps the opposite edge fixed and uses the same calibrated
mouse coordinates as movement, rather than rebasing native hold-hook positions.
Release or drag completion rechecks the native lock, restores the handle bounds,
and saves once if the position or dimensions changed and the lock is readable.
Input-time lock changes update the cached handle state, so recovery before the
next draw still refreshes the input surfaces correctly.
Locking or resizing also ends an active drag. UI loss, game-state changes, and
shutdown cancel it; stale callbacks are ignored, and the header layer and all
nine input layers are destroyed independently of PrettyUI's owned widget tree.

The `overlayPosition` structured preference stores integer `x` and `y`, plus
optional `width` and `height`, together in one write. Existing position-only
records remain valid. Only explicitly resized dimensions are persisted, so
changing width alone does not freeze the automatic content height. Invalid
saved coordinates or dimensions are logged and use the corresponding defaults.
The default width is 500 units; the minimum width is 340. The minimum height
fits the currently visible rows. Bar sections resize proportionally, preserving
their gaps. The countdown uses a fixed 56-unit width, inset four units from the
content's left edge with a six-unit gap before the bars. Vertical resizing
assigns the remaining content height to all segmented and uniform bar backgrounds
and fills, keeping six-unit top and bottom padding. Countdown and section labels
span that same height with native vertical-centre alignment; text size does not
change. Debug/error rows sit below the timer and reserve only their required
height. Changes to those rows invalidate layout even when saved outer dimensions
stay unchanged.

Saved geometry is clamped for the viewport and visible content without replacing
preferred values on every screen resize. Failed saves are logged and reported
in an open Settings view; the new layout still applies for the current session.
The Settings reset button clears the plugin's PersistentDB in one operation,
restores local defaults, cancels an unfinished layout gesture, and refreshes
checkboxes without triggering their change callbacks. A failed clear is reported
while defaults still apply for that session. Neither reset nor layout gestures
reset timer/detector state or write RuneScape's native interface lock.

## PrettyUI 1.2.0

`plugin.json` declares `"requiredDependencies": { "prettyui": 6398181 }`.
The client loads the library first and provides the `prettyui` global.
The integration was inspected against installed **1.2.0**, not inferred
from newer website examples. Missing/incompatible dependencies fail explicitly;
there is no silent raw-UI fallback.

The overlay uses a non-scrolling `Panel` with native `RS3_HUD_WINDOW_*` artwork:
four-unit borders and corners. `Panel.new` receives `flowManaged = true` as its third
argument to disable implicit Alt-drag, with popout and built-in resizing disabled.
There is no close control. The native settings view still uses `SimpleView`,
flow layout, and `AddCheckboxButton`.

Panel owns both dock and popout surfaces even when popout is disabled. Only the
dock surface is shown. `AddText` returns a paired proxy; property changes and
method calls update both labels. Raw timer rectangles belong only to the checked
dock content host. Destroy the Panel wrapper once to release both surfaces,
their scroll controllers, and PrettyUI's event/tooltip registrations.

The default normal overlay has a 40-unit content height (48 including the frame),
with six units of vertical padding around its timer row. Debug mode adds its
three rows and, only while an error is present, another 30 units for that error.
Normal mode never reserves an error row.
An explicitly enlarged height grows the timer bars rather than leaving an empty
area beneath them.
Layout changes call `SetContentHeight` on both surface scroll controllers and
`SetSize` on the Panel so scroll content does not retain an obsolete height
after collapsing rows. There is no `Panel:SetContentHeight` method.
Saved dimensions remain valid and are not rewritten;
resize or reset explicitly to use the smaller default dimensions.

Version 1.2.0 has no `NewComponent`, `categoryID = "auto"`, or
`hideCloseButton` option. Custom rectangles are native children of a
**checked category-zero content host**. Unsafe hosts are rejected before
creating rectangles. PrettyUI owns its widget tree; teardown destroys each
wrapper exactly once. Recheck these contracts after library updates.
The fade also requires the nine named background/border/corner sprite handles
on the installed 1.2.0 panel's dock surface; missing handles fail explicitly.

Debug readouts share the regular monitoring sample, with no additional polls
or timed capture. Missing values remain `--`. If a preference save fails, the
current-session change still applies and Settings shows that it was not saved,
even with Debug mode off.
The explicit build flag is independent of client paths, worlds, or Import save.

## API references

- [Manifest/dependencies](https://developer.runescape.com/rs/structure.html),
  [SettingsLayerReady](https://developer.runescape.com/rs/core/events.html#settingslayerready),
  and [PersistentDB](https://developer.runescape.com/rs/core/persistentdb.html)
- [Variable types](https://developer.runescape.com/rs/game/config/vartype.html),
  [NPC lists](https://developer.runescape.com/rs/game/list/npclist.html),
  and [NPC entities](https://developer.runescape.com/rs/game/entity/npcentity.html)
- [PrettyUI repository](https://github.com/PrettyRS/prettyui) and
  [documentation](https://prettyui.j3.gg/)
