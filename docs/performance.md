# Memory measurements

Measured on macOS 26.6.1 / Apple Silicon, 11 September 2026, from app revision
`0867f28`. These are observations on one machine, not portable memory limits.

## Reproduce

```sh
zsh scripts/profile-memory.sh
```

The optimized standalone runner uses the shipping views with 500 synthetic text
entries in temporary storage and private preferences. It opens a separate sample
window, advances selection through history (which scrolls the actual history
view), goes back through the same entries, and repeats open/scroll/close three
times. It measures its own physical footprint with `task_info`, plus loaded row
count and decoded image cache bytes. It never starts the clipboard monitor,
reads personal history, or writes to the general clipboard. Do not interact with
the sample window during the run. The fixture is removed after a normal exit.

This tests keyboard-style scrolling, not wheel-event handling. There are no
images in this fixture, so it isolates UI costs rather than worst-case image
capture/decoding. Allow roughly a minute for compilation and a minute for the run.
The process is separate from installed Stash, which keeps running normally.

## Shipping UI results

Physical footprint, MiB; open samples taken after 1 second, closed samples after
2 seconds. Startup before constructing the UI: 6.1 MiB.

| Cycle | Open | After scrolling | Closed |
| --- | ---: | ---: | ---: |
| 1 | 88.8 | 110.9 | 44.1 |
| 2 | 105.4 | 113.1 | 44.7 |
| 3 | 101.6 | 107.5 | 45.0 |

Scrolling loaded 500 bounded row excerpts. Dismissal returned the row count to
zero. The image cache was zero throughout. The short test reproduced the reported
rise and fall without images and did not show sustained cycle-by-cycle growth.

Separately, `vmmap -summary` on the installed process reported a 58.9 MiB current
footprint and 129.2 MiB peak. Malloc zones held 18.3 MiB of live allocations;
unused allocator space, compressed/swapped pages, and framework/rendering state
also contribute to footprint. Do not equate virtual address space or the summed
resident shared libraries with Activity Monitor's per-process memory.

## Diagnostic experiments

Experiments were confined to temporary source copies; none changed the shipping
UI or the user's system settings.

- Reusing the inspector instead of resetting its entire identity on selection
  produced 106.6–110.9 MiB after scrolling. Closed results varied from 43.1 to
  73.3 MiB. No reliable reduction; discarded.
- The same inspector-reuse variant with Stash's custom glass toolbar/buttons
  replaced by their existing plain-control fallbacks produced 51.7–52.8 MiB
  after scrolling and 42.2–42.5 MiB after closing. Opening still reached
  85.4–101.4 MiB. This isolates a substantial interaction-time cost of the glass
  path, while showing it does not explain the whole opening spike. It changes
  appearance, so it has not been shipped as a performance fix.
- `malloc_zone_pressure_relief(nil, 0)` after dismissal reclaimed zero bytes in
  both glass runs. Do not add forced allocator flushing based on this test.

## Limits and next decisions

Instruments/xctrace is unavailable in the installed Command Line Tools. The live
`leaks` scan was restricted because the installed app is not debuggable; its small
reported leaks cannot establish that the app is leak-free. No allocation-stack
trace was collected, so this is a footprint comparison, not exact attribution of
every allocation to SwiftUI, AppKit, Metal, or Stash.

Retain the existing excerpt limits, thumbnail downsampling, cache budget, and
view teardown. A lower-interaction-memory appearance requires a deliberate choice
between glass and plain controls. Investigating the opening spike further needs
an allocation trace (full Xcode/Instruments or an appropriately debuggable build).
Long-running and mixed-image workloads remain separate profiling cases.
