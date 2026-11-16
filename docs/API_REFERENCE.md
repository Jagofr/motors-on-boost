# M.O.B. // MOTORS ON BOOST — API & Function Reference Manual

**Application Release:** `v0.6.1` (Build `0014`)  
**Language Target:** Haxe 4.3.7 / Heaps.io 2.1.0 (WebGL 2.0 / JavaScript PWA)  
**Author:** Gerard "Jamie" (Jagofr) Francis  
**Publisher:** RvL // ROGUE  

---

## Table of Contents
- [M.O.B. // MOTORS ON BOOST — API \& Function Reference Manual](#mob--motors-on-boost--api--function-reference-manual)
  - [Table of Contents](#table-of-contents)
  - [1. Core \& Boot State Machine (`src/`)](#1-core--boot-state-machine-src)
    - [`Main`](#main)
      - [Constants \& Static Properties:](#constants--static-properties)
      - [Core State Fields:](#core-state-fields)
      - [Methods:](#methods)
    - [`Version`](#version)
      - [Static Properties:](#static-properties)
  - [2. Vehicle Dynamics \& Raycast Simulation (`src/physics/`)](#2-vehicle-dynamics--raycast-simulation-srcphysics)
    - [`CarPhysics`](#carphysics)
      - [Enums:](#enums)
      - [Runtime Tunable Properties:](#runtime-tunable-properties)
      - [Telemetry \& State Fields:](#telemetry--state-fields)
      - [Methods:](#methods-1)
    - [`CarConfig`](#carconfig)
      - [Typedefs:](#typedefs)
      - [Methods:](#methods-2)
    - [`SplineMath`](#splinemath)
      - [Typedefs:](#typedefs-1)
      - [Methods:](#methods-3)
  - [3. Camera \& Visual Perspective (`src/camera/`)](#3-camera--visual-perspective-srccamera)
    - [`ChaseCamera`](#chasecamera)
      - [Constants:](#constants)
      - [Methods:](#methods-4)
  - [4. Input \& Hardware Control (`src/input/`)](#4-input--hardware-control-srcinput)
    - [`InputController`](#inputcontroller)
      - [Enums:](#enums-1)
      - [Driving Registers:](#driving-registers)
      - [Touch Driving Direct Registers:](#touch-driving-direct-registers)
      - [Methods:](#methods-5)
  - [5. World, Environment \& Celestial Rendering (`src/world/`)](#5-world-environment--celestial-rendering-srcworld)
    - [`IGroundProvider`](#igroundprovider)
      - [Methods:](#methods-6)
    - [`Track`](#track)
      - [Constants:](#constants-1)
      - [Methods:](#methods-7)
    - [`SandboxMap`](#sandboxmap)
      - [Constants:](#constants-2)
      - [Methods:](#methods-8)
    - [`Skybox & SkyGradientShader`](#skybox--skygradientshader)
      - [Methods:](#methods-9)
  - [6. Autonomous Highway Traffic AI (`src/entities/`)](#6-autonomous-highway-traffic-ai-srcentities)
    - [`TrafficSystem`](#trafficsystem)
      - [Enums \& Constants:](#enums--constants)
      - [Methods:](#methods-10)
    - [`CarMesh & TrafficCarMesh`](#carmesh--trafficcarmesh)
  - [7. Graphics Hardware Pipeline \& Post-Processing (`src/graphics/`)](#7-graphics-hardware-pipeline--post-processing-srcgraphics)
    - [`GraphicsManager`](#graphicsmanager)
      - [Methods:](#methods-11)
    - [`PostProcessRenderer & RadialBlurShader`](#postprocessrenderer--radialblurshader)
  - [8. Audio Synthesis \& Sound Engine (`src/audio/`)](#8-audio-synthesis--sound-engine-srcaudio)
    - [`AudioManager`](#audiomanager)
      - [Methods:](#methods-12)
  - [9. Persistence \& Save Migration (`src/save/`)](#9-persistence--save-migration-srcsave)
    - [`SaveSystem`](#savesystem)
      - [Typedefs:](#typedefs-2)
      - [Methods:](#methods-13)
  - [10. User Interface \& Touch Controls Layer (`src/ui/`)](#10-user-interface--touch-controls-layer-srcui)
    - [`UIManager & UIBuilder`](#uimanager--uibuilder)
    - [`FontManager & UIIcons`](#fontmanager--uiicons)
    - [`TouchControlsHUD`](#touchcontrolshud)
      - [Methods:](#methods-14)
    - [`InGameHUDView & Options Panels`](#ingamehudview--options-panels)
  - [11. Automated Testing Infrastructure (`tests/`)](#11-automated-testing-infrastructure-tests)
    - [`TestMain`](#testmain)
      - [Features:](#features)
    - [Dual-Tier Test Suite Summary](#dual-tier-test-suite-summary)

---

## 1. Core & Boot State Machine (`src/`)

### `Main`
**Extends:** `hxd.App`  
**Location:** [`src/Main.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/Main.hx)  
**Description:** The primary application entry point and engine orchestrator for M.O.B. Manages asynchronous WebP texture decoding, multi-stage boot splash sequencing, 3D world instantiation, the main physics/render update loop, camera tracking, and UI lifecycle.

#### Constants & Static Properties:
- `VIRTUAL_BASE_WIDTH:Int = 1280` — Target virtual UI baseline width in pixels.
- `VIRTUAL_BASE_HEIGHT:Int = 720` — Target virtual UI baseline height in pixels.
- `DISCLAIMER_MIN_DURATION:Float = 5.5` — Mandatory locked duration (seconds) for legal disclaimer display.
- `SHOWCASE_FADE_DURATION:Float = 1.2` — Cross-fade curtain transition time (seconds) into 3D showcase.
- `RADIAL_BLUR_SPEED_THRESHOLD_KMH:Float = 140.0` — Speed threshold where screen-space radial blur activates.
- `CAMERA_FAR_PLANE:Float = 1500.0` — Maximum zFar clipping distance for the 3D scene camera.

#### Core State Fields:
- `appState:AppState` — Top-level lifecycle state: `IntroSequence` or `InGameUI`.
- `introState:IntroState` — Sequential boot stage: `None`, `Studio`, `Engine`, `Disclaimer`, or `Complete`.
- `ui:UIManager` — Master 2D user interface controller.
- `audio:AudioManager` — Procedural Web Audio synthesizer singleton.
- `gfx:GraphicsManager` — Hardware graphics profile and resolution manager.
- `saveData:GameSaveData` — Active serialized player profile and settings snapshot.
- `carPhysics:CarPhysics` — Four-wheel raycast vehicle dynamics simulation.
- `chaseCam:ChaseCamera` — Third-person spring-damped tracking camera.
- `track:Track` — Procedural circuit highway mesh and spline waypoints.
- `traffic:TrafficSystem` — Autonomous civilian highway traffic system.
- `playerMesh:CarMesh` — Procedural 3D composite vehicle model.

#### Methods:
- `init():Void` — Initializes Heaps engine, loads embedded assets, configures `AutoZoom(1280, 720)`, builds intro screens, and binds `window.app`.
- `loadWebpTile(path:String, onLoaded:Tile->Void):Void` — Asynchronously decodes WebP images via an offscreen HTML5 canvas buffer pipeline into RGBA byte arrays and uploads them to GPU textures.
- `scaleAndCenterSplash(bmp:Bitmap, sw:Float, sh:Float, naturalW:Int, naturalH:Int):Void` — Scales and centers intro splash bitmaps using `Math.max(sw / naturalW, sh / naturalH)` cover scaling so Studio and Engine boot screens fill 100% of the viewport edge-to-edge without letterboxing.
- `buildIntroScreens():Void` — Instantiates intro containers, background plates, studio/engine splashes, and framed trademark disclaimer text.
- `setIntroScreen(target:IntroState):Void` — Switches active intro stage and triggers background resource loading when reaching `Disclaimer`.
- `updateIntro(dt:Float):Void` — Advances intro screen timers, evaluates skip inputs for studio/engine logos, and enforces minimum disclaimer duration.
- `finishIntroSequence():Void` — Disposes intro containers, transitions to `InGameUI`, starts the 1.2s cross-fade curtain, and presents the main splash menu.
- `startBackgroundLoading():Void` — Asynchronously loads saved settings, audio subsystems, 3D meshes, traffic fleet, and UI while the disclaimer is displayed.
- `loadMap(mode:MapMode):Void` — Switches the active 3D environment (`Circuit` vs. `Sandbox`), toggling visibility and updating `currentMapMode`.
- `resetCarToStartLine():Void` — Resets car coordinates to `(0, 0, 0)`, yaw to `PI/2`, velocity to 0, boost fuel to 100%, and resets wheel orientations.
- `resetCarToSandboxCenter():Void` — Resets car to the center of the Sandbox Proving Grounds `(0, 0, z + 0.50)` with `yaw = PI/2`.
- `saveCurrentRun():Void` — Commits player coordinates, yaw, velocity, active `mapMode`, audio levels, steering sensitivity, and graphics settings to `LocalStorage` schema v4.
- `handleMenuAction(action:MenuAction):Void` — Dispatches menu selections (`OpenMapSelect`, `StartGame`, `StartSandbox`, `RestartRace`, `ResumeGame`, `OpenOptions`, `OpenCredits`, `QuitToTitle`). `RestartRace` reloads and resets the currently active `currentMapMode` (`Circuit` or `Sandbox`).
- `layoutIntro():Void` — Responsive layout calculator for intro headers, body text, partner logos, and version indicators.
- `onResize():Void` — Synchronizes 2D UI resolution scaling, applies 3D offscreen render scaling, updates curtain bounds, and invokes UI relayout.
- `update(dt:Float):Void` — Master frame loop executing physics integration, traffic AI, chase camera updates, wheel spin/steer rotations, radial blur scaling, and HUD telemetry refresh.
- `getS2d():h2d.Scene` — Returns the Heaps 2D UI scene instance.
- `getS3d():h3d.scene.Scene` — Returns the Heaps 3D world scene instance.
- `getEngine():h3d.Engine` — Returns the low-level rendering hardware engine.

---

### `Version`
**Location:** [`src/Version.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/Version.hx)  
**Description:** Centralized single source of truth for semantic versioning, build compilation counters, release channel designations, and build timestamps.

#### Static Properties:
- `NUMBER:String = "0.6.1"` — Semantic version string (`Major.Minor.Patch`).
- `BUILD:Int = 14` — Monotonically increasing compilation counter tallied from 0 for the milestone.
- `BUILD_STRING:String = "0014"` — Build counter formatted in zero-padded 4-digit (`0000`) format.
- `CHANNEL:String = "Alpha"` — Release maturity designation.
- `DISPLAY:String = "v0.6.1 (Build 0014)"` — Full formatted display badge for title screens and disclaimers.
- `SHORT:String = "v0.6.1"` — Abbreviated version string.
- `BUILD_DATE:String = "2026-11-15"` — Release compilation date.

---

## 2. Vehicle Dynamics & Raycast Simulation (`src/physics/`)

### `CarPhysics`
**Location:** [`src/physics/CarPhysics.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/CarPhysics.hx)  
**Description:** Fixed 240Hz sub-stepped 4-wheel raycast vehicle physics engine synchronized with an OimoPhysics `World` and `RigidBody` collider hull. Delegates terrain strut sensing (`SuspensionSolver`), multi-gear torque & nitrous delivery (`DrivetrainSolver`), and Pacejka/Ackermann/Friction-Circle traction (`TireSlipSolver`).

#### State & Telemetry Fields:
- `physicsWorld:oimo.dynamics.World` — Underlying OimoPhysics world hosting static wall/prop colliders and dynamic bodies.
- `chassisBody:oimo.dynamics.rigidbody.RigidBody` — Dynamic Oimo rigid body aligned with `pos + (0, 0, cogHeight)` with wheel-clearance collision box.
- `config:VehicleConfigData`, `groundProvider:IGroundProvider` — Active clamped configuration and last ground surface provider.
- `pos:Vector` — World position anchored at bottom-of-wheels ground plane (`Track.ROAD_LIFT` on circuit).
- `yaw:Float`, `pitch:Float`, `roll:Float`, `driftAngle:Float` — 3D chassis attitude in radians (`yaw < 0` = Left/-X, `yaw > 0` = Right/+X, `pitch > 0` = Nose Up, `roll > 0` = Lean Right).
- `forwardSpeed:Float`, `lateralVelocity:Float`, `verticalVelocity:Float` — Chassis velocity projections in m/s.
- `yawRate:Float`, `pitchRate:Float`, `rollRate:Float` — 6-DOF rotational rates in rad/s.
- `isGrounded:Bool`, `groundedWheelCount:Int`, `isDrifting:Bool`, `isBoosting:Bool` — Contact, drift, and nitrous activity flags.
- `currentGear:Int` (`-1` Reverse, `1..6` Forward), `engineRPM:Float`, `boostFuel:Float` — Drivetrain and boost reserve telemetry.
- `suspLength:Array<Float>`, `wheelNormalLoads:Array<Float>`, `wheelFriction:Array<Float>`, `wheelSpinVelocity:Array<Float>` — Per-wheel `[FL, FR, RL, RR]` telemetry arrays.

#### Methods:
- `new(x:Float = 0.0, y:Float = 0.0, z:Float = 0.0, ?initialConfig:VehicleConfigData, ?worldConfig:PhysicsWorldConfig)` — Constructs physics world, dynamic collider, and sub-solvers.
- `setConfig(newConfig:VehicleConfigData):Void` — Validates, clamps, and swaps active vehicle tuning at runtime.
- `resetState(x:Float, y:Float, z:Float, yawAngle:Float = 0.0):Void` — Resets position, attitude, velocities, solver relaxation states, and Oimo `chassisBody`.
- `syncToOimoBody():Void` / `syncFromOimoBody():Void` — Bidirectional transform/velocity sync between `CarPhysics` state and Oimo `chassisBody`.
- `update(dt:Float, input:InputController, ?waypoints:Array<Vector>, ?ground:IGroundProvider):Void` — Executes 240Hz fixed sub-steps, Oimo obstacle overlap resolution, and `IGroundProvider` barrier containment.

---

### `SuspensionSolver`, `DrivetrainSolver` & `TireSlipSolver`
**Locations:**
- [`src/physics/SuspensionSolver.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/SuspensionSolver.hx) — Evaluates `[FL, FR, RL, RR]` wheel raycasts against `IGroundProvider` and non-self Oimo colliders (`WheelRayCallback`), computing asymmetric bump/rebound spring forces, front/rear Anti-Roll Bar load transfer, and chassis pitch/roll restoring torques.
- [`src/physics/DrivetrainSolver.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/DrivetrainSolver.hx) — 6-speed + reverse sequential automatic transmission with RPM hysteresis, bell-shaped engine torque delivery, foot/engine braking, and nitrous boost fuel/thrust simulation.
- [`src/physics/TireSlipSolver.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/TireSlipSolver.hx) — Speed-blended Ackermann wheel angles, axle weight transfer, relaxation-filtered slip angles, Pacejka lateral curves, combined Friction Circle clamping (`|F| <= mu * F_z`), and low-speed static stiction holding.

---

### `CarConfig`
**Location:** [`src/physics/CarConfig.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/CarConfig.hx)  
**Description:** Static vehicle geometry constants (`TIRE_RADIUS=0.36`, `TIRE_WIDTH=0.30`, `CHASSIS_WIDTH=1.88`, `CHASSIS_LENGTH=4.30`, `COG_HEIGHT=0.48`, `WHEELBASE=2.70`, `TRACK_WIDTH=1.96`), nested typedefs (`ChassisConfig`, `SuspensionConfig`, `DrivetrainConfig`, `TireConfig`, `BoostConfig`, `VehicleConfigData`), safe `clamp()`, `getDefault()`, and JSON helpers (`toJson`, `fromJson`).

---

### `SplineMath`
**Location:** [`src/physics/SplineMath.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/SplineMath.hx)  
**Description:** Mathematical utilities for cubic Catmull-Rom spline curves and track segment projections.

#### Typedefs:
- `SegmentProjection`: Contains `centerPoint:Vector`, `distSq:Float`, `z:Float`, `segDirX:Float`, `segDirY:Float`.

#### Methods:
- `catmullRom(p0:Float, p1:Float, p2:Float, p3:Float, t:Float):Float` — Evaluates standard cubic Catmull-Rom spline interpolation with tangent continuity across adjacent control nodes.
- `projectOntoSegment(p:Vector, a:Vector, b:Vector):SegmentProjection` — Projects an arbitrary 3D position onto a finite 3D line segment, clamping projection ratio to `[0.0, 1.0]`.
- `getClosestSegment(p:Vector, waypoints:Array<Vector>):SegmentProjection` — Finds the nearest spline segment along an entire waypoint array and calculates exact orthogonal projection.

---

## 3. Camera & Visual Perspective (`src/camera/`)

### `ChaseCamera`
**Location:** [`src/camera/ChaseCamera.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/camera/ChaseCamera.hx)  
**Description:** Velocity-aligned third-person chase camera using critically-damped `SmoothDamp` tracking, speed/boost dynamic FOV scaling, subtle bounded lateral-G roll banking, terrain clearance floor protection, and quadratic trauma shake decay.

#### Constants & Fields:
- `BASE_DISTANCE:Float = 6.8`, `BASE_HEIGHT:Float = 2.55`, `BASE_FOV:Float = 65.0`, `SPEED_FOV_BONUS:Float = 10.5`, `BOOST_FOV_BONUS:Float = 11.5`, `MAX_BANK_RAD:Float = 0.055`, `MIN_GROUND_CLEARANCE:Float = 0.95`.
- `trauma:Float` — Normalized shake intensity `[0.0, 1.0]`.

#### Methods:
- `new(camera:Camera, startX:Float, startY:Float, startZ:Float)` — Constructs chase camera bound to active scene `h3d.Camera`.
- `snapBehind(carPhysics:CarPhysics):Void` — Snaps camera position and velocity cleanly behind vehicle heading.
- `addTrauma(amount:Float):Void` — Injects trauma impulse scaled by `0.5` and clamped `[0, 1]`.
- `update(dt:Float, carPhysics:CarPhysics, isBoosting:Bool):Void` — Updates velocity-blended direction, `SmoothDamp` eye position, look-ahead target, FOV, banking, terrain clearance, and trauma decay.

---

## 4. Input & Hardware Control (`src/input/`)

### `InputController`
**Location:** [`src/input/InputController.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/input/InputController.hx)  
**Description:** Unified multi-device input coordinator normalizing desktop keyboard, analog gamepad thumbsticks/triggers/D-pad (`hxd.Pad`), and mobile multi-touch virtual joystick/pedals under a single consistent coordinate sign convention (`- = Left`, `+ = Right`).

#### Enums & Registers:
- `InputAction`, `ExclusiveDevice` (`Both`, `KeyboardOnly`, `GamepadOnly`), `ControllerLayout`.
- `steer:Float` (`[-1.0, +1.0]`), `throttle:Float`, `brake:Float`, `handbrake:Bool`, `boost:Bool`, `steerSensitivity:Float` (`[0.1, 1.0]` applied exclusively to final combined output without mutating `rawDigitalSteer`).
- `touchSteer:Float`, `touchThrottle:Float`, `touchBrake:Float`, `touchHandbrake:Bool`, `touchBoost:Bool`, `isTouchActive:Bool`.

#### Methods:
- `update(dt:Float):Void` — Polls keyboard, deadzone-rescaled analog gamepad (`pow(norm, 1.35)`), D-pad, and rescaled touch joystick; merges inputs cleanly without state cross-corruption.
- `flushInputs():Void` — Resets UI edge triggers and clears `rawDigitalSteer`.

---

## 5. World, Environment & Celestial Rendering (`src/world/`)

### `IGroundProvider`
**Interface:** [`src/world/IGroundProvider.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/world/IGroundProvider.hx)  
**Description:** Universal interface for 3D world maps and driving surfaces. Enables high-speed 4-wheel elevation raycasting, slope normal evaluation for chassis attitude, and perimeter boundary enforcement.

#### Methods:
- `getGroundElevation(x:Float, y:Float):Float` — Computes ground contact plane elevation Z in meters at coordinate (x, y).
- `getGroundNormal(x:Float, y:Float, outNormal:Vector):Void` — Populates scratch vector with unit-length normal (nx, ny, nz).
- `enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float }` — Clamps vehicle within legal bounds and returns impact velocity multipliers.

---

### `Track`
**Extends:** `h3d.scene.Object`  
**Implements:** `IGroundProvider`  
**Location:** [`src/world/Track.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir\haxe-projs\Haxe\racing-game\src\world\Track.hx)  
**Description:** Procedural 4-lane highway circuit builder. Generates smooth Catmull-Rom roadbed ribbon meshes, asphalt surface with RoadLift offset, continuous galvanized Armco steel barrier guardrails, illuminated highway street light poles with warm phosphor luminaires, and background urban cityscape skyscraper geometry.

#### Constants:
- `ROAD_WIDTH:Float = 20.0` — Total 4-lane asphalt width in meters.
- `HALF_WIDTH:Float = 10.0` — Centerline-to-asphalt-edge distance in meters.
- `BED_EXTRA_WIDTH:Float = 4.0` — Gravel shoulder width extending beyond asphalt borders.
- `ROAD_LIFT:Float = 0.06` — Vertical offset preventing coplanar Z-fighting with foundation bed.
- `RAIL_HEIGHT:Float = 0.65` — Barrier guardrail height above roadway in meters.

#### Methods:
- `new(?parent:Object)` — Synthesizes waypoints, roadbed, asphalt ribbon, guardrails, street lights, and skyscrapers.
- `buildCircuitWaypoints():Void` — Interpolates 12 key control nodes via Catmull-Rom splines into high-density waypoint arrays.
- `buildRoadBed():Void` — Generates wide gravel foundation sub-base ribbon geometry.
- `buildRoadRibbon():Void` — Generates dark asphalt road surface ribbon geometry with normals and UV coordinates.
- `buildContinuousGuardrails():Void` — Generates continuous left and right Armco steel barrier ribbons.
- `buildStreetLights():Void` — Generates 16+ illuminated highway luminaire poles lining the Armco barriers.
- `buildCityscape():Void` — Generates background skyscraper building geometry with varying elevations and silhouettes.
- `getGroundElevation(x:Float, y:Float):Float` — Samples asphalt elevation at the closest spline segment.
- `getGroundNormal(x:Float, y:Float, outNormal:Vector):Void` — Calculates surface slope normal.
- `enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float)` — Clamps vehicle inside the guardrail corridor.

---

### `SandboxMap`
**Extends:** `h3d.scene.Object`  
**Implements:** `IGroundProvider`  
**Location:** [`src/world/SandboxMap.hx`](file:///g:/My%20Drive/Organized\Backup\Documents\Github\project-working-dir\haxe-projs\Haxe\racing-game\src\world\SandboxMap.hx)  
**Description:** Open 400m x 400m proving grounds terrain environment for comprehensive physics and suspension testing. Features continuous analytical heightfield evaluations, rolling moguls, steep 12.5m apex hill climb, high-speed launch ramp with sharp crest lip, banked 25° high-speed bowl, central flat staging tarmac, 4 high-mast perimeter floodlight towers, and invisible elastic boundary collision walls at +/-195 meters.

#### Constants:
- `HALF_SPAN:Float = 200.0` — Proving grounds boundary half-span in meters.
- `WALL_LIMIT:Float = 195.0` — Invisible collision wall perimeter limit in meters.
- `HILL_APEX_Z:Float = 12.5` — Apex mountain pass maximum elevation in meters.
- `RAMP_CREST_Z:Float = 3.8` — Speed launch ramp crest elevation in meters.

#### Methods:
- `new(?parent:Object)` — Constructs terrain polygon mesh, center skidpad, floodlights, and agility obstacles.
- `getGroundElevation(x:Float, y:Float):Float` — Continuous analytical terrain elevation function.
- `getGroundNormal(x:Float, y:Float, outNormal:Vector):Void` — Finite-difference spatial normal gradient calculator.
- `enforceBoundaries(pos:Vector, forwardSpeed:Float, lateralVelocity:Float)` — Clamps position within +/-195m walls and reflects velocity with bumper restitution.

---

### `Skybox & SkyGradientShader`
**Location:** [`src/world/Skybox.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/world/Skybox.hx)  
**Description:** Geodesic celestial sphere with custom HxSL atmospheric gradient shader blending azure zenith blue (`#1052B8`), atmospheric horizon cyan (`#7AC2F2`), and dusk nadir tones. Translates dynamically with camera to create an infinite horizon.

#### Methods:
- `syncCamera(camPos:Vector):Void` — Positions the skybox center point synchronously with the camera eye coordinate.

---

## 6. Autonomous Highway Traffic AI (`src/entities/`)

### `TrafficSystem`
**Extends:** `h3d.scene.Object`  
**Location:** [`src/entities/TrafficSystem.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/entities/TrafficSystem.hx)  
**Description:** Highway traffic simulation managing a fleet of autonomous civilian vehicles flowing in same-direction and oncoming traffic corridors. Enforces lead-car follow headway buffers, handles mutual traffic separation, processes solid player-to-traffic vehicular impacts with impulse exchange, and bounds vehicles to track boundaries.

#### Enums & Constants:
- `TrafficLane`: `RightLane = 0` (+4.8m offset), `LeftLane = 1` (-4.8m offset).
- `ACTIVE_HALF_WIDTH:Float = 9.7` — Boundary threshold before guardrail contact.
- `PLAYER_RADIUS:Float = 1.6` — Collision cylinder radius for player in meters.
- `TRAFFIC_RADIUS:Float = 1.5` — Collision cylinder radius for civilian cars in meters.
- `HIT_THRESHOLD:Float = 3.1` — Combined player-traffic collision distance threshold.
- `TRAFFIC_FOLLOW_BUFFER:Float = 10.0` — Forward distance triggering autonomous braking.
- `WALL_STICKINESS:Float = 0.94` — Velocity conservation ratio applied while scraping rails.

#### Methods:
- `new(trackWaypoints:Array<Vector>, ?parent:Object)` — Spawns traffic fleet distributed along waypoints.
- `update(dt:Float, playerPhysics:CarPhysics, chaseCam:ChaseCamera):Void` — Simulates lead-car detection, advances waypoint navigation, resolves traffic-traffic separation, processes player collisions, and clamps coordinates to track half-width.
- `clampToTrack(point:Vector, maxHalfWidth:Float):Bool` — Projects and clamps a 3D coordinate point to the legal asphalt half-width corridor.

---

### `CarMesh & TrafficCarMesh`
**Location:** [`src/entities/CarMesh.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/entities/CarMesh.hx) & [`src/entities/TrafficCarMesh.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/entities/TrafficCarMesh.hx)  
**Description:** Procedural composite 3D mesh hierarchies. `CarMesh` constructs the high-poly player vehicle (sculpted hood, cabin canopy, front splitter, side skirts, rear diffuser, downforce wing, LED headlights, neon taillights, quad exhaust tips, steerable front wheel assemblies with rim caps). `TrafficCarMesh` constructs lightweight civilian sedans with randomized body colors.

---

## 7. Graphics Hardware Pipeline & Post-Processing (`src/graphics/`)

### `GraphicsManager`
**Location:** [`src/graphics/GraphicsManager.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/graphics/GraphicsManager.hx)  
**Description:** Hardware configuration manager. Dynamically applies 3D render scaling, 2D UI resolution presets, shadow map passes, directional sunlight color temperatures, texture filtering, and antialiasing profiles.

#### Methods:
- `applyAll():Void` — Re-applies all graphics sub-pipelines.
- `applyRenderScale():Void` — Sets 3D offscreen render target scale (0.25x to 4.0x) on `PostProcessRenderer`.
- `applyUIResolution():Void` — Configures 2D canvas resolution (720p, 1080p, 1440p, 2160p, or Native Window).
- `applyShadows():Void` — Adjusts shadow map resolution (512 to 4096) and bias.
- `applyLighting():Void` — Sets directional sun color and ambient illumination tones.
- `applyTexturesAndFiltering():Void` — Configures hardware antialiasing multiplier on `Engine.ANTIALIASING`.

---

### `PostProcessRenderer & RadialBlurShader`
**Location:** [`src/graphics/PostProcessRenderer.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/graphics/PostProcessRenderer.hx) & [`src/graphics/RadialBlurShader.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/graphics/RadialBlurShader.hx)  
**Description:** Custom forward renderer providing offscreen render target scaling decoupled from native UI canvas. When `renderScale != 1.0`, it dynamically allocates matching `Depth24Stencil8` depth targets. Executes screen-space 8-tap radial directional motion blur at high vehicle speeds (> 140 km/h).

---

## 8. Audio Synthesis & Sound Engine (`src/audio/`)

### `AudioManager`
**Location:** [`src/audio/AudioManager.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/audio/AudioManager.hx)  
**Description:** Web Audio API sound manager. Procedurally synthesizes UI navigation feedback tones, menu chirps, and manages volume attenuation across master, music, and sound effects channels without external audio files.

#### Methods:
- `new()` — Establishes browser `AudioContext` with graceful headless/autoplay fallbacks.
- `playMenuBeep(freq:Float = 440.0, duration:Float = 0.06):Void` — Synthesizes an instantaneous sine wave tone with exponential gain ramping to prevent clipping.

---

## 9. Persistence & Save Migration (`src/save/`)

### `SaveSystem`
**Location:** [`src/save/SaveSystem.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/save/SaveSystem.hx)  
**Description:** Local storage persistence coordinator implementing schema v4 (`mob_motors_on_boost_save_v4`). Handles mid-race checkpoints, audio gains, steering sensitivity, touch control layouts, and graphics profiles with automated backwards-compatible migration from v1, v2, and v3 saves.

#### Typedefs:
- `GameSaveData`: `version`, `buildNumber`, `hasActiveRun`, `playerState`, `masterVol`, `musicVol`, `sfxVol`, `graphics`, `steerSensitivity`, `touchSettings`.
- `PlayerSaveState`: `posX`, `posY`, `posZ`, `yaw`, `forwardSpeed`.
- `GraphicsSettings`: `textures`, `shadowLevel`, `shadowRes`, `lightingLevel`, `lightingRes`, `mipmapping`, `anisotropic`, `aaType`, `aaLevel`, `modelGeometry`, `modelReflections`, `reflectionLevel`, `renderScale`, `uiResolution`.
- `TouchSettings`: `mode`, `scale`, `stickOffsetX`, `stickOffsetY`, `nitroOffsetX`, `nitroOffsetY`, `gasOffsetX`, `gasOffsetY`, `brakeOffsetX`, `brakeOffsetY`, `driftOffsetX`, `driftOffsetY`.

#### Methods:
- `load():GameSaveData` — Reads active profile with fallback discovery across older versions and automated migration to v4.
- `save(data:GameSaveData):Void` — Commits save snapshot to `localStorage`.
- `clear():Void` — Erases persisted save keys.
- `getDefaultSettings():GraphicsSettings` — Returns baseline hardware quality profile.
- `getDefaultTouchSettings():TouchSettings` — Returns default touch button layout offsets.

---

## 10. User Interface & Touch Controls Layer (`src/ui/`)

### `UIManager & UIBuilder`
**Location:** [`src/ui/UIManager.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/UIManager.hx), [`src/ui/UIBuilder.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/UIBuilder.hx), [`src/ui/views/mapselect/MapSelectView.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/views/mapselect/MapSelectView.hx), [`src/ui/views/multiplayer/MultiplayerMenuView.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/views/multiplayer/MultiplayerMenuView.hx), [`src/ui/views/multiplayer/MultiplayerLobbyView.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/views/multiplayer/MultiplayerLobbyView.hx), & [`src/ui/components/CardBackplate.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/components/CardBackplate.hx)  
**Description:** Master UI hierarchy and component factory. Manages transitions between `Splash`, `MainMenu`, `MapSelect`, `MultiplayerMenu` (Host or Join + Invite Code input), `MultiplayerLobby`, `InGameHUD`, `PauseMenu`, `OptionsMenu`, and `CreditsScreen`. `MainMenuView` consolidates singleplayer map entry under `"PLAY SINGLEPLAYER"` (`MenuAction.OpenMapSelect`) and opens `MultiplayerMenuView` under `"MULTIPLAYER LOBBY"` (`MenuAction.OpenMultiplayer`). `PauseMenuView` dispatches `MenuAction.RestartRace` via `"RESTART MAP"` to restart whichever map the player selected. `CardBackplate` renders chamfered cyber panels (`drawChamferedBox`), corner brackets, and procedural map/multiplayer schematics.

---

### `FontManager & UIIcons`
**Location:** [`src/ui/FontManager.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/FontManager.hx) & [`src/ui/UIIcons.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/UIIcons.hx)  
**Description:** `FontManager` caches high-legibility bitmap fonts (`regularFont`, `titleFont`, `heroFont`) with headless-safe fallbacks. `UIIcons` draws resolution-independent vector UI symbols via `h2d.Graphics` and caches them to `h2d.Tile` textures.

---

### `TouchControlsHUD`
**Extends:** `h2d.Object`  
**Location:** [`src/ui/components/TouchControlsHUD.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/components/TouchControlsHUD.hx)  
**Description:** Full-screen mobile multi-touch driving HUD. Features a left-thumb virtual analog steering joystick, left-finger Nitro button, right-thumb Gas pedal pad, upper-right Brake pad, and arched Handbrake drift button. Incorporates native PNG asset loading (`res/icons/`) with procedural vector fallback, screen-to-camera projection, scratch point reuse, and discrete multi-touch role mapping (`activeTouches: Map<Int, String>`) for full multi-touch chord concurrency.

#### Methods:
- `applyCustomOffsets(settings:TouchSettings):Void` — Dynamically repositions button centers according to user custom offsets and global scale.
- `resetLayout():Void` — Restores factory default ergonomic tablet schematic coordinates.
- `layout():Void` — Re-anchors buttons relative to current screen dimensions (`sw`, `sh`).

---

### `InGameHUDView & Options Panels`
- **`InGameHUDView`**: Displays top-left angled telemetry badge with digital KM/H speedometer, gear indicator, and drift alert; lap and race timer; procedural circuit minimap with directional heading dot; top-center tachometer RPM arc; bottom-center nitro capacity arc; and top-right real-time FPS counter.
- **`GraphicsOptionsPanel`**: Includes vertical scrolling viewport (`scrollOffset`), adaptive backplate sizing, and automatic dependency locking (disables and labels `[DISABLED]` child options when parent settings are turned off).
- **`ControlsOptionsPanel`**: Features a permanent steering sensitivity slider (0% to 100% in 2% steps) across Keyboard, Gamepad, and Touch tabs, plus interactive layout adjustment in the Touch tab.

---

## 11. Automated Testing Infrastructure (`tests/`)

### `TestMain`
**Location:** [`tests/TestMain.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/tests/TestMain.hx)  
**Description:** Central test suite orchestration runner for unit testing and CI/CD automation.

#### Features:
- **Headless Shims**: Stubs WebGL texture allocations via `h3d.mat.Texture.fromColor` and Web Audio contexts for Node.js execution.
- **Modular Filtering**: Accepts CLI arguments (`process.argv`) or environment variables (`process.env.TEST_FILTER`) to filter execution by module name (e.g. `camera`, `physics`, `ui`) or specific test class name.
- **`utest` Runner**: Configures `utest.Runner` with `PrintReport`, executing 289 assertions across 14 test fixtures with a 100% pass rate in <0.06s.

### Dual-Tier Test Suite Summary
1. **Headless Unit Tests (`test.hxml` / `node tests/node-runner.js`)**:
   - `TestChaseCamera`, `TestCarPhysics`, `TestCarConfig`, `TestSplineMath`, `TestInputController`, `TestTouchControls`, `TestGraphicsOptions`, `TestMapSelectAndRestart`, `TestSaveSystem`, `TestTrack`, `TestSandboxMap`, `TestTrafficSystem`, `TestVersion`, `TestAudioManager` (289/289 assertions passing).
2. **Automated Browser Visual Suite (`tests/run-browser-tests.js` / `web/test-suite.html`)**:
   - Spawns headless Microsoft Edge via CDP on dynamic debugging ports.
   - Verifies trademark disclosure boot resolution, decoupled 3D render scaling, graphics dependency graying out, global steering sensitivity persistence, dedicated touch tab customization, and simulated in-game track driving with nitrous depletion/recharge (15/15 scenarios passed).
3. **Playwright E2E & Visual Screenshot Verification Suite (`aitests/run-playwright-tests.js` / `aitests/specs/mob-ui-and-maps.spec.js`)**:
   - Runs against `https://mob.24-7.ro/` or local static server (`aitests/server.js` on port `7725`) after the VSCode build & deploy task, capturing 18 verification screenshots into `aitests/screenshots/` covering full-viewport boot intro screens, styled UI views, Singleplayer Map Selection flow, Map-Aware Restart, steering direction (`+X` Right / `-X` Left), left/right alloy wheel rim rendering, and traffic/ground OimoPhysics collision sync.

