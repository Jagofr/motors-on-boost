# M.O.B. // MOTORS ON BOOST — Systems & Parameter Reference

This ledger records active tuning variables across physics, input, track geometry, and traffic simulation.

---

## 1. Longitudinal & Drift Dynamics (`src/physics/CarPhysics.hx`)

| Parameter | Current Value | Target Range (NFS MW 2005) | Description / Impact |
|---|---|---|---|
| `TOP_SPEED` | `68.0` m/s (~245 km/h) | `62.0 - 70.0` | Base maximum speed under normal engine throttle. |
| `BOOST_TOP_SPEED` | `88.0` m/s (~316 km/h) | `82.0 - 90.0` | Maximum velocity ceiling during active nitrous injection. |
| `ACCELERATION` | `28.0` m/s² | `22.0 - 26.0` | Engine torque curve bite. Lower values convey heavier curb weight. |
| `BOOST_ACCEL` | `48.0` m/s² | `40.0 - 50.0` | Forward surge when nitrous is engaged. |
| `BRAKING` | `38.0` m/s² | `36.0 - 44.0` | Foot-brake deceleration rate. |
| `STEER_AUTHORITY` | `2.2` | `1.8 - 2.2` | Cornering turn-in response at moderate-to-high speeds. |
| `DRIFT_YAW_RATE` | `3.2` | `2.8 - 3.4` | Rotation angular velocity once lateral traction breaks. |
| `DRIFT_STICKINESS` | `0.88` | `0.88 - 0.92` | Lateral velocity damping factor per tick while in a slide. |

---

## 2. Steering Rack Emulation (`src/input/InputController.hx`)

| Parameter | Current Value | Description / Impact |
|---|---|---|
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

## 4. Traffic Flow & Collision Management (`src/entities/TrafficSystem.hx`)

| Parameter | Current Value | Description / Impact |
|---|---|---|
| `PLAYER_RADIUS` | `1.6` m | Radial hull threshold for player vehicle. |
| `TRAFFIC_RADIUS` | `1.5` m | Radial hull threshold for civilian traffic vehicles. |
| `TRAFFIC_FOLLOW_BUFFER` | `10.0` m | Ahead scan distance where trailing vehicles brake to match speed. |
| `LANE_OFFSET` | `±4.8` m | Left-hand traffic offsets: Same-direction = `-4.8m`, Oncoming = `+4.8m`. |

## 5. Graphics Pipeline & PWA Storage Architecture (`src/graphics/GraphicsManager.hx` & `src/save/SaveSystem.hx`)

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
- Version: `2` (Application Release: `v0.1.4`, Build: `148`)
- Primary Key: `mob_motors_on_boost_save_v2`
- Backwards-Compatible Fallback Keys: `mob_motors_on_boost_save_v1`, `burnout_overdrive_save_v1`
- Forward Migration: Older save records are loaded, schema-migrated to version 2 with default `uiResolution`, stamped with `buildNumber: 148`, and committed back to `mob_motors_on_boost_save_v2`.
- Preserves: `version`, `buildNumber`, `hasActiveRun`, `posX`, `posY`, `posZ`, `yaw`, `forwardSpeed`, `masterVol`, `musicVol`, `sfxVol`, and `graphics` profile.

---

## 6. Mobile Multi-Touch Virtual Controls HUD (`src/ui/components/TouchControlsHUD.hx`)

| Component | Dimensions / Bounds | Screen Placement | Geometry Model / Detection |
|---|---|---|---|
| `Steer Left` (`<`) | `84 x 84` px | Bottom-Left (`x = 28.0`, `y = sh - 112.0`) | Rectangular bounding partition with `24px` margin |
| `Steer Right` (`>`) | `84 x 84` px | Bottom-Left (`x = 128.0`, `y = sh - 112.0`) | Rectangular bounding partition with `24px` margin |
| `Gas (Throttle)` | `72 x 72` px | Bottom-Right Outer (`x = sw - 100.0`, `y = sh - 188.0`) | Euclidean distance-to-center (`radius = 54px`, min dist) |
| `Brake / Reverse` | `72 x 72` px | Bottom-Right Outer (`x = sw - 100.0`, `y = sh - 100.0`) | Euclidean distance-to-center (`radius = 54px`, min dist) |
| `Nitro Boost` | `72 x 72` px | Bottom-Right Inner (`x = sw - 188.0`, `y = sh - 188.0`) | Euclidean distance-to-center (`radius = 54px`, min dist) |
| `Handbrake Drift` | `72 x 72` px | Bottom-Right Inner (`x = sw - 188.0`, `y = sh - 100.0`) | Euclidean distance-to-center (`radius = 54px`, min dist) |
| `Pause Toggle` (`\|\|`) | `52 x 52` px | Top-Right (`x = sw - 80.0`, `y = 28.0`) | Rectangular bounding box with `18px` padding |

### Touch Input Pipeline & Camera Projection:
1. **Screen-to-Camera Coordinate Mapping**: Raw window/touch pixel events are projected into 2D virtual scene space via `s2d.interactiveCamera.eventToCamera(scratchEvent)` before local transformation, ensuring accuracy across high-DPI (Retina) and arbitrary browser zoom levels.
2. **Zero-Allocation Scratch Instances**: Reuses internal `scratchPoint` and `scratchEvent` to eliminate runtime garbage collection churn on WebGL and mobile targets.
3. **Multi-Touch Concurrency**: Maintains an active touch pointer map (`activeTouches: Map<Int, String>`) assigning unique finger touch IDs (`e.touchId`) to button states. Supports simultaneous throttle, steering, and boost actuation without input cancellations.
4. **Touch Cancel Safeguard**: Listens to browser `touchcancel` events to immediately reset input registers if an OS gesture, notification shade, or window blur occurs.