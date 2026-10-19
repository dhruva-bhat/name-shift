# Name Shift (Phase 1)

Select files in Finder, hold Shift ~450 ms, flick toward a slice, release Shift.

```
swift test                 # core logic tests (no UI, no permissions needed)
scripts/run.sh             # build build/NameShift.app, (re)launch it
CONFIG=release scripts/build-app.sh
```

## Layout

- `Sources/NameShiftCore` — testable logic: `Trigger/` (hold state machine, gate, log),
  `Selection/` (FileDescriptor), `Wheel/` (geometry, view model), `Actions/` (registry,
  convert, merge, ordering), `Engine/` (job queue, ImageIO converter, PDFKit merger),
  `Output/` (never-overwrite policy, undo).
- `Sources/NameShift` — AppKit/SwiftUI shell: event tap, Finder AppleScript, panels
  (wheel, merge tray, HUD), menu bar, onboarding, preferences, debug log.

## Phase 1 wheel (clockwise from top)

PNG · JPG · HEIC · Merge → PDF · WebP · AVIF. Slices that don't apply are greyed with the
reason in the center. WebP is always greyed: ImageIO can't encode WebP (libvips, Phase 2).

## Signing and permissions

Ad-hoc builds get a new signature every build, and macOS then quietly drops the Input
Monitoring and Accessibility grants. Use a stable identity (`SIGN_IDENTITY=...` or a free
Apple Development cert). To clear stale entries: `tccutil reset All dev.nameshift.NameShift`.
