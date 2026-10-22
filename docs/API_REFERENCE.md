# M.O.B. // MOTORS ON BOOST — API & Function Reference Manual

**Application Release:** `v1.0.0` (Build `0006`)  
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
- `buildIntroScreens():Void` — Instantiates intro containers, background plates, studio/engine splashes, and trademark disclaimer text.
- `setIntroScreen(target:IntroState):Void` — Switches active intro stage and triggers background resource loading when reaching `Disclaimer`.
- `updateIntro(dt:Float):Void` — Advances intro screen timers, evaluates skip inputs for studio/engine logos, and enforces minimum disclaimer duration.
- `finishIntroSequence():Void` — Disposes intro containers, transitions to `InGameUI`, starts the 1.2s cross-fade curtain, and presents the main splash menu.
- `startBackgroundLoading():Void` — Asynchronously loads saved settings, audio subsystems, 3D meshes, traffic fleet, and UI while the disclaimer is displayed.
- `resetCarToStartLine():Void` — Resets car coordinates to `(0, 0, 0)`, yaw to `PI/2`, velocity to 0, boost fuel to 100%, and resets wheel orientations.
- `saveCurrentRun():Void` — Commits player coordinates, yaw, velocity, audio levels, steering sensitivity, and graphics settings to `LocalStorage` schema v4.
- `handleMenuAction(action:MenuAction):Void` — Dispatches menu selections (`StartGame`, `ResumeGame`, `OpenOptions`, `OpenCredits`, `QuitToTitle`).
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
- `NUMBER:String = "0.3.0"` — Semantic version string (`Major.Minor.Patch`).
- `BUILD:Int = 5` — Monotonically increasing compilation counter tallied from 0 for the milestone.
- `BUILD_STRING:String = "0005"` — Build counter formatted in zero-padded 4-digit (`0000`) format.
- `CHANNEL:String = "Alpha"` — Release maturity designation.
- `DISPLAY:String = "v0.3.0 (Build 0005)"` — Full formatted display badge for title screens and disclaimers.
- `SHORT:String = "v0.3.0"` — Abbreviated version string.
- `BUILD_DATE:String = "2026-10-11"` — Release compilation date.

---

## 2. Vehicle Dynamics & Raycast Simulation (`src/physics/`)

### `CarPhysics`
**Location:** [`src/physics/CarPhysics.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/CarPhysics.hx)  
**Description:** High-performance hybrid vehicle dynamics simulator combining an OimoPhysics 3D rigid body backbone for mass, inertia, world collisions, and restitution, driven by analytical multi-link raycast suspension, Pacejka slip-angle tire adhesion, and Criterion-style (*Need for Speed: Most Wanted 2012*) arcade drift mechanics. Designed with zero runtime allocations in frame update loops.

#### Enums:
- `WheelIndex`:
  - `FrontLeft = 0` — Front-left suspension strut.
  - `FrontRight = 1` — Front-right suspension strut.
  - `RearLeft = 2` — Rear-left suspension strut.
  - `RearRight = 3` — Rear-right suspension strut.
- `Gear`:
  - `Reverse = -1`, `Neutral = 0`, `First = 1` through `Sixth = 6`.

#### Runtime Tunable Properties:
- `tireSlipBias:Float` (Range `[-1.0 .. 1.0]`) — Front vs rear tire slip bias. Negative induces oversteer/drift; positive induces understeer; 0.0 is neutral.
- `driftTriggerAngle:Float` (Default `0.22 rad` / `~12.6°`) — Chassis slip angle threshold that triggers arcade drift physics.
- `bodyRollScale:Float` (Default `1.0`) — Centrifugal chassis lean multiplier affecting suspension compression.
- `groundFriction:Float` (Default `1.0`) — Global contact scalar for tire grip, braking, and rolling drag.
- `wheelspinAmount:Float` (Default `1.2`) — Wheelspin burnout multiplier during launches and harsh power corners.
- `baseAcceleration:Float` — Engine torque delivery rate in m/s².
- `boostAcceleration:Float` — Nitrous oxide augmented acceleration rate in m/s².

#### Telemetry & State Fields:
- `physicsWorld:oimo.dynamics.World` — Underlying OimoPhysics rigid body simulation world (gravity: $Z = -9.81\text{ m/s}^2$).
- `chassisBody:oimo.dynamics.rigidbody.RigidBody` — 3D inertial rigid body representing vehicle chassis and collision hull.
- `pos:Vector` — World coordinates of vehicle chassis center point.
- `yaw:Float`, `pitch:Float`, `roll:Float` — Chassis rotational orientation in radians.
- `forwardSpeed:Float`, `lateralVelocity:Float`, `verticalVelocity:Float` — Longitudinal, lateral, and vertical velocity vectors in m/s.
- `isDrifting:Bool`, `driftDirection:Float`, `driftAngle:Float` — Active drift slide flags and visual slip angles.
- `currentGear:Int`, `engineRPM:Float`, `isShifting:Bool` — Drivetrain state.
- `boostFuel:Float` (Range `[0.0, 1.0]`), `isBoosting:Bool` — Nitrous fuel capacity and active burn state.
- `suspLength:Array<Float>`, `suspCompression:Array<Float>`, `wheelOnGround:Array<Bool>` — 4-wheel suspension travel arrays.
- `wheelSlipAngles:Array<Float>`, `wheelSpinVelocity:Array<Float>` — Wheel kinematics.

#### Methods:
- `new(startX:Float, startY:Float, startZ:Float, ?initialConfig:VehicleConfigData)` — Constructs simulator, allocates OimoPhysics rigid body, and initializes spring resting lengths.
- `setConfig(newConfig:VehicleConfigData):Void` — Replaces active physics configuration at runtime.
- `resetState(startX:Float, startY:Float, startZ:Float, newYaw:Float = 1.5707963):Void` — Resets vehicle transform, velocities, transmission, and Oimo rigid body.
- `update(dt:Float, input:InputController, ?waypoints:Array<Vector>, ?groundProvider:world.IGroundProvider):Void` — Master physics integration step executing suspension raycasts, drivetrain shifts, acceleration/braking, lateral slip, and stepping Oimo rigid body dynamics.
- `updateLateralAndDrift(dt:Float, input:InputController, fwdX:Float, fwdY:Float, rightX:Float, rightY:Float):Void` — Evaluates slip angles, Pacejka-like grip curves, handbrake rear traction breakaway, drift counter-steer assist, and forward velocity momentum biasing.
- `updateChassisAttitude(dt:Float, input:InputController):Void` — Calculates centrifugal body roll lean (clamped on flat surfaces) and acceleration squat / braking dive pitch.

---

### `CarConfig`
**Location:** [`src/physics/CarConfig.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/physics/CarConfig.hx)  
**Description:** Strongly typed vehicle specification configuration data structure with JSON import/export round-trip capability.

#### Typedefs:
- `VehicleConfigData`: Encompasses `mass`, `baseTopSpeed`, `boostTopSpeed`, `reverseTopSpeed`, `baseAcceleration`, `boostAcceleration`, `brakeDecel`, `suspension`, `tires`, `drift`, `drivetrain`, and `aero`.
- `SuspensionConfig`: `restLength`, `springRate`, `damping`, `antiRollStiffness`, `bodyRollScale`, `minTravel`, `maxTravel`.
- `TireConfig`: `baseLateralStiffness`, `peakSlipAngle`, `tireSlipBias`, `groundFriction`, `wheelspinAmount`, `rollingResistance`.
- `DriftConfig`: `driftTriggerAngle`, `lateralStiffnessScale`, `counterSteerTorque`, `forwardBiasRate`, `driftYawRate`, `minDriftSpeed`, `driftExitSpeed`.
- `DrivetrainConfig`: `idleRPM`, `redlineRPM`, `shiftUpRPM`, `shiftDownRPM`, `shiftDelay`, `gearRatios`, `finalDrive`, `reverseRatio`, `lsdLockRatio`.
- `AeroConfig`: `dragCoeff`, `downforceCoeff`.

#### Methods:
- `getDefault():VehicleConfigData` — Returns default balanced arcade sports vehicle specification.
- `toJson(cfg:VehicleConfigData):String` — Serializes vehicle configuration into human-readable JSON string.
- `fromJson(jsonStr:String):VehicleConfigData` — Parses JSON string into strongly typed `VehicleConfigData` with fallback validation.

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
**Description:** Third-person spring-damped chase camera. Features controlled acceleration pull-back (+0.55m max), velocity feedforward (0.65), speed-dependent dynamic FOV expansion (65.0° - 77.0°, +3.5° boost, bounded to prevent fisheye distortion), and softened collision trauma screen shake with rapid exponential decay (`3.8 * dt`). Zero heap allocations in update loops.

#### Constants:
- `BASE_DISTANCE:Float = 7.5` — Base follow distance behind chassis in meters.
- `BASE_HEIGHT:Float = 2.8` — Base vertical elevation above chassis in meters.
- `LOOK_AHEAD_DIST:Float = 6.2` — Distance ahead of vehicle along heading for focal point in meters.
- `LOOK_AHEAD_HEIGHT:Float = 1.0` — Vertical look-ahead offset in meters.
- `BASE_FOV:Float = 65.0` — Base field of view angle in degrees at rest.
- `MAX_SPEED_FOV:Float = 77.0` — Maximum cruising FOV angle in degrees at top speed.
- `BOOST_FOV_EXTRA:Float = 3.5` — Additional FOV expansion in degrees under nitrous oxide.
- `MAX_TRAUMA_CEILING:Float = 0.55` — Maximum trauma intensity ceiling.
- `TRAUMA_DECAY_RATE:Float = 3.8` — Exponential trauma settling rate per second.

#### Methods:
- `new(camera:Camera, startX:Float, startY:Float, startZ:Float)` — Constructs chase camera tracker.
- `getPos():Vector` — Returns current camera eye position vector in world space.
- `getTarget():Vector` — Returns current focal target vector in world space.
- `addTrauma(amount:Float):Void` — Injects impact impulse softened by 50% and clamped to `MAX_TRAUMA_CEILING`.
- `update(dt:Float, carPhysics:CarPhysics, isNitroActive:Bool):Void` — Updates spring-arm position, dynamic FOV interpolation (`pow(speedRatio, 1.25)`), acceleration pull-back, velocity feedforward, and trauma shake translations.

---

## 4. Input & Hardware Control (`src/input/`)

### `InputController`
**Location:** [`src/input/InputController.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/input/InputController.hx)  
**Description:** Centralized input coordinator aggregating desktop keyboard keystrokes, gamepad controller buttons/axes (via Heaps `hxd.Pad`), and mobile virtual touch inputs. Features dynamic key remapping, device isolation modes, deadzone filtering, and granular steering sensitivity scaling.

#### Enums:
- `InputAction`: `SteerLeft`, `SteerRight`, `Throttle`, `Brake`, `Handbrake`, `Boost`.
- `ExclusiveDevice`: `Both`, `KeyboardOnly`, `GamepadOnly`.
- `ControllerLayout`: `StandardXbox`, `NintendoBayX`.

#### Driving Registers:
- `steer:Float` — Normalized steering deflection in range `[-1.0 .. 1.0]`.
- `throttle:Float` — Normalized forward acceleration demand in range `[0.0 .. 1.0]`.
- `brake:Float` — Normalized service braking demand in range `[0.0 .. 1.0]`.
- `handbrake:Bool` — Handbrake actuation state.
- `boost:Bool` — Nitrous oxide injection request state.
- `steerSensitivity:Float` (Range `[0.0, 1.0]`, default `1.0`) — Steering sensitivity multiplier adjustable in 2% steps.

#### Touch Driving Direct Registers:
- `touchSteer:Float`, `touchThrottle:Float`, `touchBrake:Float`, `touchHandbrake:Bool`, `touchBoost:Bool`, `isTouchActive:Bool`.

#### Methods:
- `update(dt:Float):Void` — Polls keyboard and gamepad hardware, resolves remapping listening states, applies deadzones and sensitivity multipliers, and updates edge-trigger flags.
- `startListening(action:InputAction, onDone:Void->Void):Void` — Puts controller into remapping capture mode for the specified action.
- `flushInputs():Void` — Clears edge-trigger navigation flags and resets analog input registers.
- `getKeyName(code:Int):String` — Converts keyboard scan-code integer into user-friendly display string.
- `getGamepadBtnName(btn:Int, layout:ControllerLayout):String` — Converts gamepad button index into layout-specific name.

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
**Location:** [`src/ui/UIManager.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/UIManager.hx) & [`src/ui/UIBuilder.hx`](file:///g:/My%20Drive/Organized/Backup/Documents/Github/project-working-dir/haxe-projs/Haxe/racing-game/src/ui/UIBuilder.hx)  
**Description:** Master UI hierarchy and component factory. Manages transitions between `Splash`, `MainMenu`, `InGameHUD`, `PauseMenu`, `OptionsMenu`, and `CreditsScreen`. `UIBuilder` generates frosted glass card backplates, styled buttons, toggle rows, and volume block meters.

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
- **`utest` Runner**: Configures `utest.Runner` with `PrintReport`, executing 201 assertions across 12 test fixtures with a 100% pass rate in <0.06s.

### Dual-Tier Test Suite Summary
1. **Headless Unit Tests (`test.hxml` / `node tests/node-runner.js`)**:
   - `TestChaseCamera`, `TestCarPhysics`, `TestCarConfig`, `TestSplineMath`, `TestInputController`, `TestTouchControls`, `TestGraphicsOptions`, `TestSaveSystem`, `TestTrack`, `TestTrafficSystem`, `TestVersion`, `TestAudioManager`.
2. **Automated Browser Visual Suite (`tests/run-browser-tests.js` / `web/test-suite.html`)**:
   - Spawns headless Microsoft Edge via CDP on dynamic debugging ports.
   - Verifies trademark disclosure boot resolution, decoupled 3D render scaling, graphics dependency graying out, global steering sensitivity persistence, dedicated touch tab customization, and simulated in-game track driving with nitrous depletion/recharge (15/15 scenarios passed).

