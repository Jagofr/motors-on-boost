# Changelog

All notable changes to **M.O.B. (Motors on Boost)** will be documented in this file and tracked in the `changelogs/` directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-09
### Added
- **First-Principles Arcade Raycast Vehicle Dynamics (`CarPhysics.hx`)**:
  - Four-wheel independent spring-damper suspension integration along road contact normals: `F = (k * (restLength - currentLength) - c * suspVelocity) * contactNormal`.
  - Opposing anti-roll bar torque across front and rear wheel pairs preventing unnatural body roll while preserving suspension travel.
  - Separated longitudinal propulsion from lateral cornering grip with slip angle calculation `alpha = atan2(vLateral, |vForward|)` clamped through a normalized Pacejka-like grip saturation curve.
  - Complete Arcade Drift State Machine with handbrake and tap-brake initiation, scaled lateral tire stiffness (35% baseline), counter-steer torque injection, and forward velocity vector biasing for momentum-preserving slides without snap-back spinouts.
  - Powertrain simulation: Dynamic flywheel engine RPM calculation, progressive 6-speed gear ratios, automatic transmission up/down-shift logic, and simulated limited-slip differential (LSD).
- **Runtime Vehicle Configuration Schema (`CarConfig.hx`)**:
  - Strongly typed, serializable vehicle configuration schema defining curb weight, moment of inertia tensor, suspension spring/damper constants, gear ratios, tire friction parameters, and drift assist multipliers.
  - Full JSON parsing and dumping support (`CarConfig.fromJson`, `CarConfig.toJson`) enabling runtime vehicle tuning without recompilation.
- **Chase Camera Refinement & Toned-Down Shake (`ChaseCamera.hx`)**:
  - Spring-damped target lag with dynamic acceleration pull-back during forward surge and nitrous injection.
  - Dynamic speed-dependent Field of View (FOV) smoothly expanding from 65° base to 85° at terminal velocity.
  - Substantially softened collision impulses: clamped peak trauma ceiling to 0.55, dampened translational/rotational offsets, and applied rapid exponential decay (`3.8 * dt`) for punchy, non-disorienting hits.
- **High-Speed Radial Motion Blur Screen Shader (`RadialBlurShader.hx` & `PostProcessRenderer.hx`)**:
  - Screen-space radial directional blur pass implemented in HxSL (`h3d.shader.ScreenShader`) centered on the vehicle horizon/vanishing point.
  - Runtime dynamic parameters for `blurOrigin` and `blurIntensity` scaled automatically with vehicle speed.
  - Clean registration into `s3d.renderer` through custom `PostProcessRenderer` utilizing offscreen render target passes with zero overhead during low-speed cruising.
- **Procedural Atmospheric Gradient Blue Skybox (`Skybox.hx`)**:
  - High-density celestial dome sphere with custom HxSL shader blending deep azure zenith blue (`#1052B8`), bright atmospheric horizon cyan (`#7AC2F2`), and dusk nadir tones.
  - Synchronized dynamically with camera translation for an infinite celestial horizon.
- **Apex Summit Solar Lighting**:
  - Re-positioned scene directional sunlight to the highest south-east point of the map (`X: +350, Y: -250, Z: 140`) casting solar illumination across the circuit.
- **Save System v3 Schema & Forward Migration (`SaveSystem.hx`)**:
  - Bumped schema to `SAVE_VERSION = 3` with active storage key `mob_motors_on_boost_save_v3`.
  - Seamless forward migration preserving player settings from v2, v1, and legacy prototype keys.
- **PWA Service Worker Cache**:
  - Bumped cache to `mob-motors-on-boost-v2-0` in `sw.js` and updated script cache buster to `game.js?v=0.2.0`.

### Fixed
- **Track Obstruction Cleanup (`Track.hx`)**:
  - Removed overlapping scenery skyscraper object at `(X: 295, Y: 130)` that clipped across 9 circuit waypoints without collision.

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