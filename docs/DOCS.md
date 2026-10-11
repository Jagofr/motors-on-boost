# M.O.B. // MOTORS ON BOOST — Systems & Parameter Reference

This ledger records active tuning variables across physics, input, track geometry, and traffic simulation.

---

## 1. Raycast Suspension & Arcade Vehicle Dynamics (`src/physics/CarPhysics.hx` & `CarConfig.hx`)

| Parameter | Current Value | Target Range | Description / Impact |
|---|---|---|---|
| `TOP_SPEED` | `68.0` m/s (~245 km/h) | `62.0 - 70.0` | Base maximum speed under normal engine throttle. |
| `BOOST_TOP_SPEED` | `88.0` m/s (~316 km/h) | `82.0 - 90.0` | Maximum velocity ceiling during active nitrous injection. |
| `ACCELERATION` | `28.0` m/s² | `24.0 - 30.0` | Engine torque bite. Scaled by shift disengagement latency and ground friction. |
| `BOOST_ACCEL` | `48.0` m/s² | `42.0 - 52.0` | Forward surge when nitrous oxide is engaged. |
| `BRAKING` | `38.0` m/s² | `36.0 - 44.0` | Threshold foot-brake deceleration rate scaled by ground friction. |
| `suspension.restLength` | `0.45` m | `0.40 - 0.50` | Unloaded spring height from chassis to road contact. |
| `suspension.springRate` | `32000.0` N/m | `28000 - 36000` | Linear spring stiffness for road surface tracking. |
| `suspension.damping` | `2600.0` Ns/m | `2200 - 3000` | Shock absorber viscous compression/rebound damping. |
| `suspension.antiRollStiffness` | `9500.0` N/m | `8000 - 12000` | Transverse anti-roll bar torque preventing unnatural roll. |
| `suspension.bodyRollScale` | `1.0` | `0.5 - 2.0` | Dynamic chassis roll scaling directly affecting suspension spring compression/extension. |
| `tires.peakSlipAngle` | `0.16` rad (~9.2°) | `0.14 - 0.18` | Slip angle at which lateral tire adhesion peaks. |
| `tires.baseLateralStiffness` | `34.0` | `30.0 - 38.0` | Baseline cornering stiffness in linear slip region. |
| `tires.tireSlipBias` | `-0.45` | `-1.0 to 1.0` | Front vs rear slip bias. Negative = rear bias / oversteer; Positive = front bias / understeer; 0 = neutral. |
| `tires.groundFriction` | `1.0` | `0.2 - 2.0` | Global ground contact scalar multiplying tire adhesion, braking, and rolling drag. |
| `tires.wheelspinAmount` | `1.2` | `0.5 - 3.0` | Burnout wheelspin scalar for standstill full-throttle launches and power cornering. |
| `drift.driftTriggerAngle` | `0.22` rad (~12.6°) | `0.10 - 0.35` | Chassis angle relative to velocity required to engage active drift physics. |
| `drift.lateralStiffnessScale` | `0.35` (35%) | `0.30 - 0.40` | Lateral grip scale during active drift slide. |
| `drift.counterSteerTorque` | `3.4` | `2.8 - 3.8` | Artificial yaw torque assist when counter-steering slide. |
| `drift.forwardBiasRate` | `3.8` | `3.0 - 4.5` | Momentum blending rate aligning velocity to vehicle heading. |
| `drivetrain.gearRatios` | `[3.40, 2.20, 1.55, 1.18, 0.92, 0.76]` | Progressive 6-speed | Progressive gear reductions with final drive `3.73`. |
| `drivetrain.idleRPM / redlineRPM` | `1000.0 / 8000.0` | `1000 / 8000` | Engine flywheel RPM limits and shift window (`3400 - 7200`). |
| `boost.capacity` | `1.0` (100%) | `1.0` | Nitrous oxide reservoir capacity. |
| `boost.drainRate` | `0.25` / s | `0.20 - 0.35` | Nitrous burn rate during active boost (4.0s sustained full boost). |
| `boost.rechargeRate` | `0.10` / s | `0.05 - 0.15` | Passive idle recharge rate (10.0s empty-to-full). |

---

## 2. Steering Rack Emulation & Controls (`src/input/InputController.hx` & `src/save/SaveSystem.hx`)

| Parameter | Current Value | Description / Impact |
|---|---|---|
| `steerSensitivity` | `1.0` (100%) | Granular steering sensitivity multiplier scalable from 0% to 100% in 2% steps. |
| `STEER_SPEED` | `4.2` | Turn-in rate for digital keyboard inputs (WASD / Arrows). |
| `RETURN_SPEED` | `6.5` | Self-centering rate returning wheels to neutral upon key release. |
| `GAMEPAD_DEADZONE` | `0.12` | Deadzone threshold filtering stick drift on analog gamepads. |

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
| `BASE_DISTANCE` | `7.5` m | Follow distance behind vehicle at zero speed. |
| `BASE_HEIGHT` | `2.8` m | Vertical elevation above vehicle chassis at zero speed. |
| `BASE_FOV` | `65.0°` | Base vertical field of view angle when cruising or stationary. |
| `MAX_SPEED_FOV` | `77.0°` | Smoothly dilated FOV angle at terminal velocity (+3.5° under nitrous boost). |
| `accelPullBack` | Dynamic (`0.0 - 0.55m`) | Spring-damped camera pull-back during forward acceleration (+0.35m boost). |
| `velocityFeedforward` | `0.65` | Forward velocity feedforward anchoring camera tightly behind chassis at 200+ km/h. |
| `MAX_TRAUMA_CEILING` | `0.55` | Clamped maximum trauma ceiling preventing violent screen disorientation. |
| `TRAUMA_DECAY_RATE` | `3.8` | Rapid exponential decay settling trauma crisp and punchy. |

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