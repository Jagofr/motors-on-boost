# M.O.B. // MOTORS ON BOOST — Systems & Parameter Reference

This ledger records active tuning variables across physics, input, track geometry, and traffic simulation.

---

## 1. 4-Wheel Raycast Suspension & Vehicle Dynamics (`src/physics/`)

| Parameter / Module | Current Value / Design | Description / Impact |
|---|---|---|
| Fixed Integration | `1 / 240` s (`FIXED_SUBSTEP`) | Deterministic 240Hz micro-stepping (`dt <= 0.05s`) synchronized with `oimo.dynamics.World`. |
| `chassis.massKg / cogHeight` | `1450.0` kg / `0.48` m | Vehicle curb mass and COG elevation (`CarConfig.WHEELBASE = 2.70m`, `TRACK_WIDTH = 1.96m`). |
| `suspension.restLength` | `0.36` m (`min 0.14`, `unloaded 0.50`) | Loaded equilibrium strut length matching `CarMesh.TIRE_RADIUS = 0.36m` ground contact. |
| `suspension.springStiffness` | `25400.0` N/m | Four-wheel raycast spring rate yielding `0.14m` curb sag against `-9.81 m/s^2` gravity. |
| `suspension.bumpDamping / reboundDamping` | `3950.0` / `5450.0` Ns/m | Asymmetric damper curve absorbing compressions smoothly and controlling rebound. |
| `suspension.antiRollStiffness` | `14500.0` N/m | Front and rear axle Anti-Roll Bar load transfer resisting excessive cornering body roll. |
| `tires.pacejkaB / C / D / E` | `9.2 / 1.52 / 1.08 / -0.35` | Pacejka Magic Formula lateral adhesion with combined Friction Circle (`|F_xy| <= mu * F_z`). |
| `tires.relaxationLength / minSlipSpeed` | `0.34` m / `1.2` m/s | Distance-filtered slip relaxation and low-speed denominator stabilization. |
| `tires.stictionSpeed` | `0.65` m/s | Static contact holding canceling slope gravity creep and standstill jitter at rest. |
| `tires.maxSteerAngle / ackermannFactor` | `0.54` rad / `0.65` | Speed-blended Ackermann inner/outer front wheel geometry (`highSpeedSteerDamp = 0.026`). |
| `drivetrain.gearRatios / finalDrive` | `[3.42, 2.28, 1.65, 1.28, 1.02, 0.84]` / `3.75` | 6-speed automatic + reverse (`-3.15`) transmission, `560 Nm` peak torque, `950 - 7600 RPM`. |
| `drivetrain.maxForwardSpeed` | `72.0` m/s (`+14.0` boost bonus) | Governed top speed (~259 km/h base, ~309 km/h with nitrous boost thrust `7800 N`). |
| `boost.maxFuel / burnRate / regenRate` | `1.0` / `0.28 /s` / `0.12 /s` | Nitrous fuel reserve capacity, combustion burn rate, and passive idle recharge rate. |

---

## 2. Multi-Device Analog & Digital Controls (`src/input/InputController.hx` & `src/save/SaveSystem.hx`)

| Parameter | Current Value | Description / Impact |
|---|---|---|
| Steering Sign Convention | `-1.0 = Left (-X / yaw < 0)`, `+1.0 = Right (+X / yaw > 0)` | Uniform sign mapping across keyboard, analog gamepad thumbstick, D-pad, and virtual touch stick. |
| `rawDigitalSteer` | Internal `[ -1.0, 1.0 ]` | Persistent keyboard/D-pad rack state kept decoupled from analog overrides and `steerSensitivity`. |
| `steerSensitivity` | `1.0` (`[0.1, 1.0]`) | Applied solely to final combined output so sensitivity never compounds across frames. |
| `STEER_SPEED / RETURN_SPEED` | `4.2` / `6.5` rad/s | Turn-in slew and return-to-center rates for digital inputs. |
| `GAMEPAD_DEADZONE` | `0.12` (rescaled `[0..1]`) | Deadzone-rescaled thumbstick response (`pow(norm, 1.35)`) for smooth analog precision. |

---

## 3. Circuit Dimensions & Boundaries (`src/world/Track.hx` & `src/entities/TrafficSystem.hx`)

| Parameter | Current Value | Description / Impact |
|---|---|---|
| `ROAD_WIDTH` | `20.0` m | Total width of the 4-lane asphalt highway. |
| `HALF_WIDTH` | `10.0` m | Distance from track centerline to outer edge. |
| `ACTIVE_HALF_WIDTH`| `9.7` m | Collision boundary triggering guardrail contact before clipping. |
| `BED_EXTRA_WIDTH` | `4.0` m | Width of the downward-sloping gravel shoulder along the track. |
| `ROAD_LIFT` | `0.06` m | Vertical separation preventing z-fighting with the roadbed. |
| `RAIL_HEIGHT` | `0.65` m | Vertical height of continuous Armco galvanized steel barriers. |
| `WALL_STICKINESS` | `0.94` | Momentum preservation ratio applied while grinding guardrails. |

---

## 4. Visual Shaders & Environment Architecture (`src/graphics/` & `src/world/`)

| System / Shader | File | Key Parameters | Description |
|---|---|---|---|
| Radial Motion Blur | `RadialBlurShader.hx` | `blurOrigin: Vec2`, `blurIntensity: Float` | Screen-space 8-tap directional blur active at speeds > 140 km/h. |
| Post-Process Pass | `PostProcessRenderer.hx` | Extends `h3d.scene.fwd.Renderer` | Offscreen buffer pass executed only when blur is active (zero idle overhead). |
| Skybox Gradient | `Skybox.hx` | `topColor: #1052B8, horizonColor: #7AC2F2` | Geodesic celestial dome synchronized dynamically with camera position. |
| Solar Directional Light | `Main.hx` | Pos: `(350, -250, 140)`, Dir: `(-0.55, 0.78, -0.32)` | Directional sunlight placed at the tallest south-east point of the map. |

---

## 5. Chase Camera & Collision Trauma (`src/camera/ChaseCamera.hx`)

| Parameter | Current Value | Description / Impact |
|---|---|---|
| `BASE_DISTANCE` | `6.8` m | Nominal trailing follow distance (`+1.5m` speed pull-back, `+0.75m` boost surge). |
| `BASE_HEIGHT` | `2.55` m | Nominal camera height above vehicle wheel contact reference with slope pitch lift. |
| `BASE_FOV` | `65.0`° | Baseline vertical FOV (`+10.5°` speed bonus, `+11.5°` nitrous boost bonus). |
| `MAX_BANK_RAD` | `0.055` rad | Subtle bounded camera roll (~3.2°) aligned with lateral cornering and chassis roll. |
| `MIN_GROUND_CLEARANCE` | `0.95` m | Minimum ground clearance guarded against `IGroundProvider` terrain during steep climbs. |
| Tracking Filter | `SmoothDamp` + velocity alignment | Blends chassis heading and velocity direction above `3.5 m/s` with look-ahead target. |
| `trauma` / `addTrauma()` | `[0.0, 1.0]` (`0.5x` softened) | Quadratic trauma shake with linear decay (`1.45 / s`). |

---

## 6. Graphics Pipeline & PWA Storage Architecture (`src/graphics/GraphicsManager.hx` & `src/save/SaveSystem.hx`)

| Setting | Options / Values | Scope / Availability | Impact |
|---|---|---|---|
| `Textures` | `Off, Very Low, Low, Medium, High, Ultra, Unreal` | Main Menu Only | Texture filtering atlas tier. |
| `Shadow Level` | `Off, Normal, High, Ultra, Dynamic` | In-Game & Menu | Shadow mapping pass & specular activation. |
| `Shadow Res` | `512, 1024, 2048, 4096` | In-Game & Menu | Resolution buffer of directional depth maps. |
| `Lighting` | `Low, Medium, High, Ultra (RTX/Path)` | Main Menu Only | Light bounce profile and ambient tone mapping. |
| `Lighting Res` | `512, 1024, 2048` | In-Game & Menu | Buffer resolution for illumination maps. |
| `Mipmapping` | `Enabled / Disabled` | Main Menu Only | Trilinear texture downsampling. |
| `Anisotropic` | `1x, 2x, 4x, 8x, 16x` | Main Menu Only | Oblique angle texture clarity. |
| `Anti-Aliasing` | `None, FXAA, TSAA, SMAA, MSAA` | In-Game & Menu | Edge smoothing shader pass. |
| `AA Level` | `2x, 4x, 8x` | In-Game & Menu | Sampling multiplier. |
| `Model Geometry`| `Very Low, Low, Medium, High, Ultra` | Main Menu Only | Primitive vertex density & LOD. |
| `Reflections` | `On / Off` | In-Game & Menu | Real-time car shader reflection cubemap. |
| `Reflection Level`| `Low, Medium, High, Ultra` | In-Game & Menu | Update frequency of reflection maps. |
| `Render Scale` | `0.25x, 0.334x, 0.5x, 0.75x, 1.0x, 2.0x, 3.0x, 4.0x` | In-Game & Menu | Viewport internal framebuffer 3D rendering scale. |
| `UI Resolution` | `720p (HD), 1080p (FHD), 1440p (2K), 2160p (4K), Native / Match Window` | In-Game & Menu | 2D scene coordinate scale and layout projection. |

### PWA Storage Spec (`localStorage`):
- Version: `4` (Application Release: `v0.3.0`, Build: `0005`)
- Primary Key: `mob_motors_on_boost_save_v4`
- Backwards-Compatible Fallback Keys: `mob_motors_on_boost_save_v3`, `mob_motors_on_boost_save_v2`, `mob_motors_on_boost_save_v1`, `burnout_overdrive_save_v1`
- Forward Migration: Older save records are loaded, schema-migrated to version 4 with `steerSensitivity` (1.0) and `touchSettings` (`mode: "Default"`, custom offsets and scale), stamped with `buildNumber: 5` (`0005`), and committed back to `mob_motors_on_boost_save_v4`.
- Preserves: `version`, `buildNumber`, `hasActiveRun`, `posX`, `posY`, `posZ`, `yaw`, `forwardSpeed`, `masterVol`, `musicVol`, `sfxVol`, `steerSensitivity`, `touchSettings`, and `graphics` profile.

### Graphics Options Dependency Hierarchy (`GraphicsOptionsPanel.hx`):
- `Shadow Buffer Size (shadowRes)` is automatically disabled and marked `[DISABLED]` if `shadowLevel == "Off"`.
- `Anisotropic Filtering (anisotropic)` is automatically disabled and marked `[DISABLED]` if `mipmapping == false`.
- `Anti-Aliasing Multiplier (aaLevel)` is automatically disabled and marked `[DISABLED]` if `aaType == "None"`.
- `Reflection Level (reflectionLevel)` is automatically disabled and marked `[DISABLED]` if `modelReflections == false`.

---

## 7. Mobile Multi-Touch Virtual Controls HUD (`src/ui/components/TouchControlsHUD.hx`)

| Component | Dimensions / Bounds | Screen Placement | Geometry Model / Detection |
|---|---|---|---|
| `Virtual Analog Joystick` | `140 x 140` px base, `54px` thumbstick | Bottom-Left (`x = 110.0 + stickOffsetX`, `y = sh - 110.0 + stickOffsetY`) | Continuous proportional deflection with spring return |
| `Nitro Boost` (Flame Icon) | `74 x 74` px | Mid-Left (`x = 75.0 + nitroOffsetX`, `y = sh - 225.0 + nitroOffsetY`) | Bounding radius hitzone with multi-touch hold |
| `Gas (Throttle)` (Pedal Icon) | `88 x 88` px | Bottom-Right Outer (`x = sw - 92.0 + gasOffsetX`, `y = sh - 95.0 + gasOffsetY`) | High-capacity prime right-thumb rest zone |
| `Brake / Reverse` (Disc Icon) | `74 x 74` px | Upper-Right (`x = sw - 182.0 + brakeOffsetX`, `y = sh - 215.0 + brakeOffsetY`) | Independent braking zone |
| `Handbrake Drift` (Lever Icon)| `78 x 78` px | Mid-Right (`x = sw - 192.0 + driftOffsetX`, `y = sh - 115.0 + driftOffsetY`) | Curved drift breakaway actuator |
| `Pause Toggle` (`\|\|`) | `52 x 52` px | Top-Right (`x = sw - 80.0`, `y = 28.0`) | Rectangular bounding box with `18px` padding |

### Touch Input Pipeline & Camera Projection:
1. **Screen-to-Camera Coordinate Mapping**: Raw window/touch pixel events are projected into 2D virtual scene space via `s2d.interactiveCamera.eventToCamera(scratchEvent)` before local transformation, ensuring accuracy across high-DPI (Retina) and arbitrary browser zoom levels.
2. **Zero-Allocation Scratch Instances**: Reuses internal `scratchPoint` and `scratchEvent` to eliminate runtime garbage collection churn on WebGL and mobile targets.
3. **Multi-Touch Concurrency**: Maintains an active touch pointer map (`activeTouches: Map<Int, String>`) assigning unique finger touch IDs (`e.touchId`) to button states. Supports simultaneous throttle, steering, and boost actuation without input cancellations.
4. **Touch Cancel Safeguard**: Listens to browser `touchcancel` events to immediately reset input registers if an OS gesture, notification shade, or window blur occurs.
5. **Touch Layout Customization**: Supports Default mode (ergonomic tablet schematic) and Custom mode (repositioning analog stick, nitro, gas, brake, and handbrake offsets and scale in real-time) via Options $\to$ Touch tab.

---

## 8. Dual-Tier Automated Testing Infrastructure

### 1. Headless Unit Test Suite (`tests/` & `test.hxml`)
- Powered by `utest` (1.13.2) and `vshaxe.haxe-test-adapter`.
- Statically builds via `haxe test.hxml` and runs headlessly in Node.js via `tests/node-runner.js`.
- Shims DOM and local storage environments cleanly for Heaps.
- 12 comprehensive test fixtures with 200 assertions passing in under 0.06s.

### 2. Browser Visual / UI Automation Suite (`web/test-suite.html` & `tests/run-browser-tests.js`)
- Runs Microsoft Edge headlessly with an isolated profile and dynamic CDP debugging port.
- Verifies:
  1. Trademark disclosure screen display and 1280x720 baseline resolution.
  2. 2D UI resolution decoupling from 3D render scaling.
  3. Graphics options dependency locking and `[DISABLED]` graying out.
  4. Steering sensitivity slider persistence across Keyboard, Gamepad, and Touch tabs.
  5. Dedicated Touch tab Default schematic vs Custom offset adjustment and Reset Defaults.
  6. In-game physics and track drive simulation with throttle acceleration and nitrous depletion/recharge.