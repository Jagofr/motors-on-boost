# Changelog

All notable changes to **M.O.B. (Motors on Boost)** will be documented in this file and tracked in the `changelogs/` directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.2] - 2026-10-10
### Added
- **In-Game HUD Overhaul (`InGameHUDView.hx`)**:
  - High-density top-left angled telemetry badge with digital speedometer (`KM/H`), gear indicator (`[G1]` - `[G6]`), and animated `[DRIFTING]` status.
  - Lap counter (`LAP 1/3`) and high-precision race timer (`MM:SS.MS`).
  - Real-time circuit minimap with procedural track boundaries and glowing player position indicator with directional heading tick.
  - Top-center curved tachometer arc gauge with radial tick markers, cyan-to-redline gradient fill, and digital RPM readout.
  - Bottom-center curved nitro arc gauge with procedural dual-layer flame icon, remaining fuel percentage (`100% NITRO`), and warning states.
  - Discreet top-right real-time FPS counter.
- **Limited & Regenerating Nitrous Boost (`CarPhysics.hx`)**:
  - Nitrous fuel capacity model (`boostFuel`) with active burn drain rate (`0.25/s`, 4.0s full duration) and passive idle recharge rate (`0.10/s`, 10.0s empty-to-full).
  - Automatic nitrous cutoff upon depletion preventing infinite acceleration.
- **Steering Sensitivity Controls Setting (`ControlsOptionsPanel.hx`, `SaveSystem.hx`, `InputController.hx`)**:
  - Fine-grained steering sensitivity setting scalable from 0% to 100% in 2% steps.
  - Persistent save schema v4 (`mob_motors_on_boost_save_v4`) with seamless forward migration from v1, v2, and v3 saves.
- **Decoupled 3D Render Scale from 2D UI Resolution (`PostProcessRenderer.hx`, `GraphicsManager.hx`)**:
  - 3D scene renders to dedicated offscreen render target scaled by `renderScale` (0.50x to 1.50x), leaving 2D canvas backbuffer at native 1:1 window resolution for pin-sharp UI text.
  - Hooked up lighting preset to `ambientLight` and sun tinting via `h3d.scene.fwd.LightSystem`.
  - Connected hardware antialiasing to `Engine.ANTIALIASING`.
- **Responsive UI Layout & Viewport Scrolling**:
  - Fixed OptionsView Back button hitzone overlap (`BACK_BUTTON_WIDTH = 100.0`), preventing collision with Tab 0 ("GRAPHICS").
  - Added vertical scrolling (`scrollOffset`, `maxVisibleRows`) with navigation arrows and mouse wheel support in `GraphicsOptionsPanel.hx`.
  - Dynamic responsive card backplate sizing in `CardBackplate.hx` preventing lower-resolution overflow.
- **Comprehensive Dual-Tier Automated Testing Infrastructure (`tests/` & `web/test-suite.html`)**:
  - Headless Unit Test Suite with `utest` (1.13.2) compatible with VSCode `Haxe Test Explorer`, testing 12 fixtures (Audio, Camera, Core Version, Entities, Input, Physics, SplineMath, Save, Graphics Options, Touch Controls, Track) with 197 assertions passing in under 0.10s.
  - Automated Browser Visual/Programmatic Testing Suite (`web/test-suite.html`) driven headlessly via Microsoft Edge and CDP (`tests/run-browser-tests.js`), verifying trademark boot resolution, independent UI vs 3D render scaling, graphics dependency locking, global sensitivity slider persistence, and simulated in-game track driving with nitrous consumption and recharge.
- **Graphics Options Hierarchy & Dependency Graying Out (`GraphicsOptionsPanel.hx`)**:
  - Automatically disables, grays out, labels `[DISABLED]`, and blocks value cycling for dependent settings when parent options are disabled (`shadowLevel == "Off"` -> `shadowRes`; `mipmapping == false` -> `anisotropic`; `aaType == "None"` -> `aaLevel`; `modelReflections == false` -> `reflectionLevel`).
- **Dedicated Touch Controls Options Tab (`ControlsOptionsPanel.hx`, `TouchControlsHUD.hx`, `SaveSystem.hx`)**:
  - Added dedicated 5th tab to Options menu supporting Default layout vector schematic and Custom layout position adjustment with fine-grained offsets, scale, and 1-click Reset to Defaults.
- **Dynamic Speed Camera & Controlled Lag Refinements (`ChaseCamera.hx`)**:
  - Replaced extreme physical camera pull-back with a subtle, controlled lagging back (+0.85m at max speed) anchored with velocity feedforward (`0.65`) and adaptive spring stiffness.
  - Dynamically scaled FOV based on speed using a smooth non-linear curve (`pow(speedRatio, 1.25)`), bounded between 65.0° and 77.0° (+3.5° under nitro boost) to prevent fisheye warping at high velocities.
  - Zero per-frame object allocations in camera update loops.

*For detailed notes, see [`changelogs/2026-10-10-v0.2.2-hud-overhaul-controls-qol.md`](./changelogs/2026-10-10-v0.2.2-hud-overhaul-controls-qol.md) and [`changelogs/2026-10-11-v0.2.2-automated-test-suite-and-options-overhaul.md`](./changelogs/2026-10-11-v0.2.2-automated-test-suite-and-options-overhaul.md).*

---

## [0.2.1] - 2026-10-09
### Added
- **Ergonomic Virtual Touch Driving HUD (`TouchControlsHUD.hx`)**:
  - Proportional virtual analog steering joystick for left thumb with continuous deflection tracking, directional crosshair ticks, and spring-return centering.
  - Left-hand Nitrous Boost button placed above the joystick, allowing concurrent steering and boosting with thumb and index fingers.
  - Enlarged 88px diameter Gas pad positioned in the prime right-thumb rest zone with hit hysteresis to eliminate finger drift drops.
  - Arched Drift / Handbrake button positioned directly above Gas and Brake, enabling seamless right-hand drift initiation while holding throttle.
  - Native DOM TouchEvent integration (`touchstart`, `touchmove`, `touchend`, `touchcancel`) with `passive: false` and `preventDefault()` to prevent browser gesture cancellation and desynchronization.
  - Independent per-touch role mapping (`activeRoles: Map<Int, String>`) enabling full multi-touch concurrency across all simultaneous chords (Gas + Steer, Gas + Nitro, Gas + Drift, Drift + Nitro, Brake + Nitro, Steer + Gas + Nitro + Drift).
- **Runtime Tunable Driving Physics Architecture (`CarPhysics.hx` & `CarConfig.hx`)**:
  - `tireSlipBias` (range `[-1.0 .. 1.0]`): Front vs rear tire slip bias. Negative values induce rear-axle breakaway / oversteer drifting; positive values induce front-axle push / understeer; `0.0` provides neutral balanced slip.
  - Dedicated handbrake breakaway function: immediately reduces rear lateral tire adhesion (`rearGripMult *= 0.20 + (bias + 1.0) * 0.08`), applies longitudinal drag, and injects yaw impulse.
  - `driftTriggerAngle`: Configurable vehicle slip angle threshold (default `0.22 rad` / `~12.6°`) that automatically engages arcade drift physics upon threshold reach.
  - `bodyRollScale`: Dynamically scales centrifugal body roll lean affecting suspension spring compression and extension, clamped on flat surfaces to prevent rolling over while allowing track bumps and ramps to pitch/roll the chassis.
  - `groundFriction`: Global ground contact scalar multiplying tire adhesion, braking, and rolling resistance.
  - `wheelspinAmount`: Burnout wheelspin simulation for standstill full-throttle launches and power-oversteer cornering exits.
  - Public runtime properties directly tunable on `CarPhysics`: `tireSlipBias`, `driftTriggerAngle`, `bodyRollScale`, `groundFriction`, `wheelspinAmount`, `baseAcceleration`, `boostAcceleration`.
- **Burnout Wheelspin Visual Animation (`Main.hx`)**:
  - Decoupled rear wheel mesh rotation from vehicle ground speed, incorporating dynamic `wheelSpinVelocity` to visually spin rear wheels during full-throttle launches and power slides.
- **Build & Cache Tracking**:
  - Bumped semantic version to `0.2.1` and iterated build compilation counter to `Build 4`.
  - Updated PWA service worker cache name to `mob-motors-on-boost-v2-1` in `sw.js` and updated cache-buster to `game.js?v=0.2.1` in `index.html`.

*For detailed notes, see [`changelogs/2026-10-09-v0.2.1-touch-joystick-physics-tuning.md`](./changelogs/2026-10-09-v0.2.1-touch-joystick-physics-tuning.md).*

---

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

### Fixed
- **Track Obstruction Cleanup (`Track.hx`)**:
  - Removed overlapping scenery skyscraper object at `(X: 295, Y: 130)` that clipped across 9 circuit waypoints without collision.

*For detailed notes, see [`changelogs/2026-10-09-v0.2.0-arcade-vehicle-dynamics.md`](./changelogs/2026-10-09-v0.2.0-arcade-vehicle-dynamics.md).*

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
  - Browser `touchcancel` event handler providing fail-safe input register resets on OS gesture interrupts.
- **Decoupled 3D Graphics & UI Resolution Scaling**:
  - Independent 3D rendering resolution scaling separate from UI layout dimensions.
  - Configurable 2D UI resolution presets (`720p`, `1080p`, `1440p`, `2160p`, `Native / Match Window`) using Heaps `AutoZoom`.

### Fixed
- **Invisible Text on High-DPI Displays**: Fixed missing `baseLine` property on TrueType font descriptors in `FontManager.hx`, restoring crisp text across high-DPI displays.
- **Vehicle Mesh Artifacts (`CarMesh.hx`)**: Resolved polygon clipping and geometry misalignment, increasing vertex density across wheel arches, chassis lines, and spoiler.
- **Intro Transition Sequence**: Fixed transition from trademark disclaimer screen to 3D rotating showcase with clean, fully opaque black curtain cross-fading.

*For detailed notes, see [`changelogs/2026-10-09-v0.1.4-ui-touch-resolution-versioning.md`](./changelogs/2026-10-09-v0.1.4-ui-touch-resolution-versioning.md).*

---

## [0.1.1] - 2026-10-06
### Changed
- Completed project-wide refactoring from working title ("BURNOUT // OVERDRIVE") to finalized title **M.O.B. // MOTORS ON BOOST**.
- Migrated browser `localStorage` persistence key to `mob_motors_on_boost_save_v1` with seamless fallback for existing legacy test saves.
- Corrected PWA service worker asset paths in `sw.js` to target `./icons/icon-192.png` and `./icons/icon-512.png`.
- Standardized in-game credits and documentation references.

*For detailed notes, see [`changelogs/2026-10-06-v0.1.1-branding-persistence.md`](./changelogs/2026-10-06-v0.1.1-branding-persistence.md).*

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