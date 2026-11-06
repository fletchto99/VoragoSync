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

## Scopulus presence and lifecycle

The presence proxy was explicitly selected by the user, with the small-arena
range assumption supplied as encounter context rather than measured proof.
Each fresh observation follows this order:

1. Query `NPCList.ByName("Vorago")` and check valid identities. If none remains,
   disarm before considering Scopulus disappearance.
2. Check typed own-player `var.VarPlayer.LIFEPOINTS.value` (observed ID `13655`).
   Zero disarms before a death camera can make absence look like completion.
   Missing or invalid LP is an explicit error, not assumed alive or zero.
3. Query `*Scopul*` and count unique valid matching NPC identities. Any positive
   count arms the latch; there is no required count or last-hit/target gate.
4. A fresh change to zero triggers once if the same Vorago identity set remains,
   the player is alive, and the timer is idle.

"Present" means available as a valid entity, not camera pixels or line of sight.
An NPC can remain through a death animation. All Scopuli leaving client range
while Vorago remains loaded is indistinguishable from completion; no extra
distance heuristic is imposed. Death and encounter loss are recognized only
when the client updates the relevant signals.

Checks occur every 50ms on the next draw frame, after server delivery.
Observations over 0.6s apart are not joined into an edge: a stalled/background
client may miss a trigger instead of inventing a late one. Countdown progress
uses `Event.Draw.timeDeltaSecs`, not frame counts.

Every actual timer start centrally clears both latches. Active-run and
one-second full-hold edges are consumed, not restarted or queued. A fresh
positive observation can arm a future run. Encounter identity changes,
death/unreadable LP, failed observations, stale samples, and ordinary
boss/bar loss disarm detection without cancelling an already-running timer.
Loading/logout/reconnect, plugin UI loss, and shutdown still cancel.
Settings remounts and display changes do not reset timing or detection.
Repeated genuine monitoring errors are reported without logging on every poll.

The opt-in `onlyInArena` display preference uses the existing 50ms activity
sample and timer state, without extra queries. A valid, active bar named
Vorago (case-insensitive after normalizing markup/whitespace) or a non-idle
timer keeps the overlay visible. NPC presence is not a visibility condition:
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

Hiding affects only the overlay root, not monitoring or widget ownership.
Settings remains accessible and monitoring errors continue to be logged.
This is not a coordinate-based arena boundary check: teleporting out during
a countdown can leave the overlay visible through the timer, hold, buffer, and fade-out.

On initial display and each hidden-to-visible transition, the overlay root's
alpha starts at zero and rises linearly to one over one second of subsequent draw
time. After the grace period expires, alpha falls to zero at the same rate,
with the root remaining visible until fade-out completes. A change of direction
preserves current opacity and starts moving toward the new target on subsequent
draws. This lets returning activity or Settings changes reverse an in-progress
fade without flashing. Time spent hidden does not advance fade-in. Remaining
visible (including activity returning within the grace period) does not restart
it. A recreated window starts transparent; lifecycle teardown remains immediate.
Animation does not change timer/detection state or the separate Settings view.

## PrettyUI 1.2.0

`plugin.json` declares `"requiredDependencies": { "prettyui": 6398181 }`.
The client loads the library first and provides the `prettyui` global.
The integration was inspected against installed **1.2.0**, not inferred
from newer website examples. Missing/incompatible dependencies fail explicitly;
there is no silent raw-UI fallback.

The overlay uses a non-scrolling, untitled `Window` and `AddText`. The native
settings view uses `SimpleView`, flow layout, and `AddCheckboxButton`.
Version 1.2.0 creates a close control even without a title, so VoragoSync hides
and disables its native `closeButton` handle to prevent silently hiding the
automatic timer. There is no title-bar dragging.

Version 1.2.0 has no `NewComponent`, `categoryID = "auto"`, or
`hideCloseButton` option. Custom rectangles are native children of a
**checked category-zero content host**. Unsafe hosts are rejected before
creating rectangles. PrettyUI owns its widget tree; teardown destroys each
wrapper exactly once. Recheck these contracts after library updates.

Debug readouts share the regular monitoring sample, with no additional polls
or timed capture. Missing values remain `--`. If a preference save fails, the
current-session change still applies and a visible error says it was not saved.
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
