# Changelog

All notable changes to **M.O.B. (Motors on Boost)** will be documented in this file and tracked in the `changelogs/` directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.4] - 2026-10-09
### Added
- **Centralized Version Metadata (`Version.hx`)**: Single source of truth defining semantic version `0.1.4`, build counter `148`, release channel, and standardized display badges (`v0.1.4 (Build 148)`).
- **Persistent Version Badges Across All 5 Core UI Screens**:
  - *Trademark Disclaimer Screen*: Centered version & build label below attribution logos.
  - *Title Splash Screen*: Version badge below pulsating entrance prompt.
  - *Main Menu*: Version footer centered at screen bottom.
  - *Options Screen*: Version badge placed in upper-right header of options card.
  - *Credits Screen*: Prominent version & build designation above navigation return.
- **Save System v2 Schema & Forward Migration (`SaveSystem.hx`)**:
  - Upgraded active persistence key to `mob_motors_on_boost_save_v2`.
  - Added seamless automated migration for records originating from `mob_motors_on_boost_save_v1` and prototype saves.
  - Stamped save records with `version: 2` and `buildNumber: 148`.
- **Mobile Multi-Touch Virtual Driving Controls (`TouchControlsHUD.hx`)**:
  - Camera-aware coordinate projection mapping canvas buffer pixels into 2D scene space through `s2d.interactiveCamera.eventToCamera()`.
  - Zero-allocation scratch instances (`scratchPoint`, `scratchEvent`) eliminating per-touch garbage collector pressure.
  - Euclidean distance-to-center evaluation for action capsules (GAS, BRAKE, NITRO, DRIFT) eliminating hit-test overlap bias.
  - Independent touch identifier tracking (`activeTouches: Map<Int, String>`) enabling concurrent acceleration, steering, and nitrous boost actuation without input cancellations.
  - Browser `touchcancel` event handler providing fail-safe input register resets on OS gesture interrupts.
- **Decoupled 3D Graphics & UI Resolution Scaling**:
  - Independent 3D rendering resolution scaling separate from UI layout dimensions.
  - Configurable 2D UI resolution presets (`720p`, `1080p`, `1440p`, `2160p`, `Native / Match Window`) using Heaps `AutoZoom`.

### Fixed
- **Invisible Text on High-DPI Displays**: Fixed missing `baseLine` property on TrueType font descriptors in `FontManager.hx`, restoring crisp text across high-DPI displays.
- **Vehicle Mesh Artifacts (`CarMesh.hx`)**: Resolved polygon clipping and geometry misalignment, increasing vertex density across wheel arches, chassis lines, and spoiler.
- **Intro Transition Sequence**: Fixed transition from trademark disclaimer screen to 3D rotating showcase with clean, fully opaque black curtain cross-fading.
- **PWA Service Worker Cache**: Bumped cache name to `mob-motors-on-boost-v1-4` in `sw.js` and added cache-busting tag `?v=0.1.4` in `index.html`.

---

## [0.1.0] - 2026-10-06
### Added
- Core Haxe 4.3+ and Heaps.io (WebGL 2.0 / JavaScript) architecture.
- Progressive Web App (PWA) configuration with service worker caching.
- Custom vehicle raycast suspension, slip angles, and handbrake drift mechanics.
- Infinite procedural highway track generation and multi-lane highway traffic AI.
- Spring-arm chase camera with trauma shake decay and dynamic FOV dilation.
- Web Audio synthesizer with engine pitch shifting, nitro resonance, and channel volume staging.
- Multi-tabbed options menu with bumper tab switching (`LB`/`RB`, `Q`/`E`), sliders, and input isolation.
- Procedural vector iconography (`UIIcons.hx`) drawn via `h2d.Graphics`.
- 3-part sequential bootloader (Studio, Engine, and locked Disclaimer screen).
- Asynchronous asset pre-loading during the locked disclaimer state.
- Offscreen HTML5 Canvas WebP image decoding pipeline for 1080p branding textures.
- Cinematic 1.2-second cross-fade curtain transition into the 3D showcase vehicle.
- Complete in-game attribution screen (Credits) and project `README.md`.

*For detailed subsystem technical notes, see [`changelogs/2026-10-06-v0.1.0-initial.md`](./changelogs/2026-10-06-v0.1.0-initial.md).*

## [0.1.1] - 2026-10-06
### Changed
- Completed project-wide refactoring from working title ("BURNOUT // OVERDRIVE") to finalized title **M.O.B. // MOTORS ON BOOST**.
- Migrated browser `localStorage` persistence key to `mob_motors_on_boost_save_v1` with seamless fallback for existing legacy test saves.
- Corrected PWA service worker asset paths in `sw.js` to target `./icons/icon-192.png` and `./icons/icon-512.png`.
- Standardized in-game credits and documentation references.