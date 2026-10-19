# Changelog

All notable changes to Name Shift. Versions follow [Semantic Versioning](https://semver.org).

## [0.1.0] - 2026-10-18

First version: the hold-Shift radial wheel for Finder.

### Added
- Menu-bar app: hold Shift for 300 ms (adjustable 200–800 ms; Option + Shift or Fn / Globe
  also available) with files selected in Finder to open the wheel; release or click to run.
- Trigger guard: any other key, click, scroll or drag during the hold cancels it. The wheel never
  opens while you're typing in Finder or holding a mouse button.
- Actions: convert images to PNG, JPG, HEIC or AVIF; merge PDFs and images into one PDF.
- Merge tray to check the order, with drag or ⌥←/→ to reorder and Space to preview each file.
- Outputs saved next to the originals and never overwritten (`name 2.jpg`); Undo moves a job's
  outputs to the Trash, including files written before a cancel.
- Progress toast with Reveal in Finder and Undo; Debug Log of every trigger decision.
- First-run setup for Input Monitoring, Accessibility and Automation → Finder, with live checks.
- Preferences: trigger key, hold duration, haptic tick, tick sound, pause.
- App icon.

### Known limitations
- WebP output isn't available yet (macOS can read WebP but can't write it).
- No signed, notarized download yet. Build from source.
