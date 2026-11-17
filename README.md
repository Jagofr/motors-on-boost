# M.O.B. // MOTORS ON BOOST

<div align="center">

![Version](https://img.shields.io/badge/Version-0.8.0--Alpha%20(Build%200016)-00E5FF?style=for-the-badge)
![Haxe](https://img.shields.io/badge/Haxe-4.3%2B-FA7E0A?style=for-the-badge&logo=haxe&logoColor=white)
![WebGPU](https://img.shields.io/badge/Engine-hlwgpu%20%2F%20Ash%20Wasm32-00E5FF?style=for-the-badge&logo=webgpu&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-WebGPU%20%2F%20PWA-111418?style=for-the-badge&logo=pwa&logoColor=00E5FF)
![Graphics](https://img.shields.io/badge/Graphics-WebGPU%20%2B%20WGSL-1E88E5?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Active%20Prototype-FF9800?style=for-the-badge)
![License](https://img.shields.io/badge/License-Proprietary%20%2F%20All%20Rights%20Reserved-red?style=for-the-badge)
![Controller](https://img.shields.io/badge/Input-Gamepad%2C%20Keyboard%20%26%20Touch-4CAF50?style=for-the-badge&logo=gamepad&logoColor=white)
![Audio](https://img.shields.io/badge/Audio-Web%20Audio%20Synth-9C27B0?style=for-the-badge)
![AI Collaboration](https://img.shields.io/badge/AI%20Engineering-Google%20Gemini-4285F4?style=for-the-badge&logo=google&logoColor=white)

<p align="center">
  <strong>High-octane browser-native WebGPU &amp; Ash WebAssembly arcade racing prototype.</strong><br>
  Built with <strong>Haxe</strong>, <strong>hlwgpu (xgpu)</strong>, <strong>hlwindow</strong>, and <strong>OimoPhysics</strong>, compiled AOT to multi-threaded Wasm32.
</p>

[Overview](#overview) • [Key Features](#key-features) • [Architecture](#architecture--systems) • [Controls](#controls--hardware-support) • [Installation](#installation--setup) • [Repository Governance](#repository-governance--ip) • [Credits](#credits--attributions)

</div>

---

## Overview

**M.O.B. (Motors on Boost)** is an aggressive arcade highway racing prototype inspired by mid-2000s classics—principally *Need for Speed: Most Wanted (2005)* and *Burnout Revenge (2005)*.

Built in Haxe 4.3+ and compiled AOT via **Ash** (`wasm32-wasip1-threads`) onto hardware-accelerated **WebGPU (`hlwgpu` / `xgpu`)** and **WGSL** shaders, **M.O.B.** combines 240 Hz 4-wheel raycast vehicle physics (`AWD`, `FWD`, and `RWD` drivetrain layouts), procedural compute-generated multi-lane highway tracks, an open stunt sandbox proving grounds, autonomous traffic AI, P2P multiplayer via `/relay.ashx`, Web Audio procedural synthesis, and responsive HTML5/CSS3 overlays synchronized over a zero-copy SharedArrayBuffer `WebBridge`.

---

## Key Features

* **WebGPU Forward+ & Post-Processing Pipeline (`WebGpuRenderer.hx`)**: Native `hlwgpu` (`xgpu`) + WGSL shader pipeline compiled to WebAssembly via Ash, featuring atmospheric procedural `SkyShader`, directional Blinn-Phong lighting (`SceneLitShader`), compute track mesh generation (`TrackComputeShader`), dynamic radial speed blur (`RadialBlurShader`), and runtime-selectable **FXAA 3.11**, **SMAA 1x** (3-pass edge/blend/neighborhood), **Hardware 4x MSAA** (multisample color/depth + resolve), and **TSAA** (8x/16x/32x temporal reprojection).
* **Hybrid OimoPhysics Rigid Body & 4-Wheel Raycast Dynamics (`CarPhysics.hx`)**: OimoPhysics rigid body collision backbone coupled with independent four-wheel spring-damper suspension (`SuspensionSolver.hx`), normalized Pacejka-style tire grip & dynamic drivetrain torque split (`TireSlipSolver.hx`, `DrivetrainSolver.hx`), front/rear slip bias, drift angle engagement, counter-steer stability assist, and nitro boost (`boostFuel`).
* **Garage Vehicle Class Selection & Paint Customization (`CarSelectView.hx`, `CarConfig.hx`)**: Post-map car selector with 3 distinct chassis presets — **GT Race Car (AWD 35/65)**, **Sports Hatch (FWD 100/0)**, and **Low Sports Coupe (RWD 0/100)** — custom `CarMesh` proportions, live 8-swatch paint customization, and persistent garage saves via `SaveSystem.hx`.
* **SharedArrayBuffer HTML5/CSS3 Overlay HUD & UI (`WebBridge.hx`, `web/ui-overlay.js`)**: Zero-GC-stall Worker-to-DOM SharedArrayBuffer IPC driving crisp glassmorphic UI views, angled digital speedometer, curved tachometer RPM & nitro arcs, real-time procedural circuit minimap, black-curtain transitions, and independent `UI Interface Target` scaling alongside `3D Render Resolution`.
* **P2P LAN & Relay Multiplayer (`MultiplayerManager.hx`, `web/relay.ashx`)**: Cross-device client-server lobby flow with invite codes, state synchronization (`NetworkProtocol.hx`), WebSocket/HTTP relay transport (`SocketTransport.hx`), and remote racer rendering (`RemoteCarActor.hx`).
* **Multi-Device Input & Frosted Glass Touch HUD (`InputController.hx`, `TouchControlsHUD.hx`)**: Unified steering contract (`- = Left`, `+ = Right`) across Keyboard (`WASD`/Arrows with custom remapping), Gamepad (analog stick + D-Pad), and an isolated DOM `#touch-stick-zone` virtual analog stick plus concurrent multi-touch Gas, Brake, Drift, and Nitro pads.
* **Dynamic Speed Chase Camera (`ChaseCamera.hx`)**: Velocity-aligned damped chase camera with speed-dependent dynamic FOV dilation, boost pull-back, and exponential trauma decay.
* **Two-World Architecture (`Track.hx`, `SandboxMap.hx`, `TrafficSystem.hx`)**: Closed-loop curved Highway Circuit with barriers, apex solar lighting, and autonomous multi-lane traffic AI, plus an open Sandbox Proving Grounds test facility with ramps and dynamic props.
* **Dual-Tier Automated Testing (`tests/`, `aitests/`)**: Headless HashLink/Ash unit test suite via `utest` covering physics, multi-device anti-inversion contracts, UI flows, and persistence (`ash bin/test.hl`), paired with automated Chromium/Edge WebGPU Playwright E2E specs (`aitests/specs/`).
* **Web Audio Synthesis & Persistence (`AudioManager.hx`, `SaveSystem.hx`)**: Procedural Web Audio engine RPM synthesis, tire screech, and UI audio feedback with schema-migrated `LocalStorage` settings and mid-race checkpoints.

---

## Architecture & Systems

```
                              ┌────────────────────────┐
                              │        Main.hx         │
                              │ (Ash Wasm / Boot Loop) │
                              └───────────┬────────────┘
                                          │
            ┌─────────────────────────────┼────────────────────────────┐
            ▼                             ▼                            ▼
  ┌───────────────────┐         ┌───────────────────┐        ┌───────────────────┐
  │   Graphics & 3D   │         │    Physics & AI   │        │   UI & IPC / Net  │
  ├───────────────────┤         ├───────────────────┤        ├───────────────────┤
  │ • WebGpuRenderer  │         │ • CarPhysics.hx   │        │ • WebBridge.hx    │
  │ • WGSL Shaders    │         │ • TireSlipSolver  │        │ • ui-overlay.js   │
  │ • FXAA/SMAA/MSAA/ │         │ • CarConfig.hx    │        │ • UIManager.hx    │
  │   TSAA Passes     │         │ • Track/Sandbox   │        │ • TouchControls   │
  │ • ChaseCamera.hx  │         │ • TrafficSystem   │        │ • MultiplayerMgr  │
  └───────────────────┘         └───────────────────┘        └───────────────────┘
```

### Module Breakdown

| Module | Location | Responsibility |
|---|---|---|
| **Entry Point** | `src/Main.hx` | Ash Wasm/HL runtime entry point, fixed-step simulation loop, and showcase state machine. |
| **WebGPU Renderer** | `src/graphics/WebGpuRenderer.hx` | `hlwgpu` (`xgpu`) forward 3D pass, FXAA/SMAA/4x MSAA/TSAA AA pipeline, and radial blur. |
| **WGSL Shaders** | `src/graphics/shaders/` | Skybox, lit 3D material, SMAA 3-pass, temporal TSAA resolve, and compute track shaders. |
| **Vehicle Dynamics** | `src/physics/CarPhysics.hx` | OimoPhysics rigid body + raycast suspension, drift states, boost, and preset integration. |
| **Car Specs & Tire Solver** | `src/physics/CarConfig.hx`, `TireSlipSolver.hx` | AWD/FWD/RWD vehicle presets, wheelbase leverage, Pacejka slip grip, and paint colors. |
| **World & Traffic** | `src/world/`, `src/entities/TrafficSystem.hx` | Highway Circuit, Sandbox Proving Grounds, waypoints, barriers, and autonomous traffic AI. |
| **Camera** | `src/camera/ChaseCamera.hx` | Velocity-aligned damped chase camera with dynamic FOV dilation and collision trauma. |
| **HTML5 UI & Bridge** | `src/core/WebBridge.hx`, `web/ui-overlay.js` | SharedArrayBuffer Worker-to-DOM HUD/menus, car garage UI, and isolated touch controls. |
| **UI State & Views** | `src/ui/UIManager.hx`, `src/ui/views/` | Navigation state machine (`MapSelect -> CarSelect -> Drive`), options, and pause/credits. |
| **Input Handler** | `src/input/InputController.hx` | Keyboard, Gamepad API, and virtual touch stick input with enforced left/right polarity. |
| **Multiplayer** | `src/net/MultiplayerManager.hx`, `web/relay.ashx` | P2P host/join lobby, invite codes, socket/relay transport, and remote racer replication. |
| **Audio & Persistence** | `src/audio/AudioManager.hx`, `src/save/SaveSystem.hx` | Web Audio procedural engine/tire synthesis and versioned `LocalStorage` persistence. |

---

## Project Structure

```text
├── CHANGELOG.md                   # Chronological milestone changelog
├── CONTRIBUTING                   # Project contribution and governance terms
├── LICENSE                        # Custom proprietary software license
├── README                         # This README document
├── SECURITY.md                    # Security vulnerability reporting policy
├── compile.hxml                   # Ash Wasm32 + HL compiler configuration
├── test.hxml                      # Headless utest configuration (bin/test.hl)
├── changelogs/                    # Detailed milestone release records
├── src/
│   ├── Main.hx                    # Entry point & simulation loop
│   ├── Version.hx                 # Semantic version & build number constants
│   ├── audio/                     # Web Audio engine & tire synthesizers
│   ├── camera/                    # Velocity-aligned damped chase camera
│   ├── config/                    # Game & world configuration constants
│   ├── core/                      # Preloader, intro controller, WebBridge IPC
│   ├── entities/                  # CarMesh presets, remote actors, traffic AI
│   ├── graphics/                  # WebGpuRenderer, SceneGraph, WGSL shaders
│   ├── input/                     # Keyboard, gamepad, and touch input pipeline
│   ├── math/                      # Vec3, Mat4, and SoA memory helpers
│   ├── net/                       # Multiplayer manager, protocol, and transport
│   ├── physics/                   # CarConfig, CarPhysics, TireSlip, Suspension
│   ├── save/                      # LocalStorage persistence & schema migration
│   ├── ui/                        # UIManager, views (incl. CarSelectView), HUD
│   └── world/                     # Track, SandboxMap, Skybox, WorldManager
├── tests/                         # Headless Ash/HL unit tests (utest)
│   ├── TestMain.hx                # Master unit test suite runner
│   └── ...                        # audio, camera, core, entities, input, net, physics, save, ui, world
├── aitests/                       # Automated WebGPU Playwright E2E suite (IIS + gh-pages)
│   ├── playwright.config.js       # Dual-project WebGPU matrix (iis + gh-pages)
│   ├── server.js                  # Local IIS & gh-pages subpath/header simulator
│   ├── verify-iis-webgpu.js       # Live IIS HTTPS WebGPU verification script
│   └── specs/                     # aa-visual, controls-direction, mob-ui-and-maps specs
├── scripts/
│   └── prepare-gh-pages.js        # Packages web/ -> dist/gh-pages with SW COI injection
├── .github/workflows/
│   └── deploy-pages.yml           # Automatic main -> GitHub Pages mirror workflow
└── web/                           # Production web root & IIS / PWA bundle
    ├── index.html                 # COOP/COEP Worker launcher & COI SW bootstrapper
    ├── mob-env.js                 # Host environment descriptor (iis vs gh-pages)
    ├── ui-overlay.js              # Responsive DOM menu/HUD/touch overlay runtime
    ├── ui-overlay.css             # Glassmorphic overlay styling & virtual stick
    ├── game.wasm                  # Compiled Ash WebAssembly binary (generated)
    ├── game.hl                    # Compiled HashLink bytecode binary (generated)
    ├── hlwgpu.js / xgpu.wasm      # hlwgpu WebGPU host bridge & Wasm bindings
    ├── relay.ashx / web.config    # IIS multiplayer relay (CORS) & COOP/COEP headers
    ├── manifest.json / sw.js      # PWA manifest & Service Worker (optional COI mode)
    ├── fonts/ / icons/ / intro/   # Stack Sans / Symbols fonts, icons, splash assets
```

---

## Controls & Hardware Support

### Default Key Bindings

| Action | Primary Keyboard | Secondary Keyboard | Gamepad (Xbox / Standard) |
|---|---|---|---|
| **Throttle (Gas)** | `W` | `Up Arrow` | `RT` (Right Trigger) |
| **Brake / Reverse** | `S` | `Down Arrow` | `LT` (Left Trigger) |
| **Steer Left** | `A` | `Left Arrow` | Left Stick (X-Axis) / D-Pad Left |
| **Steer Right** | `D` | `Right Arrow` | Left Stick (X-Axis) / D-Pad Right |
| **Handbrake (Drift)** | `Space` | — | `B` / `RB` (Right Bumper) |
| **Nitro Boost** | `Left Shift` | — | `A` / `LB` (Left Bumper) |
| **Pause / Menu** | `Escape` | — | `Start` / `Menu` |
| **UI Navigate** | `W` / `S` / `A` / `D` | Arrow Keys | D-Pad / Left Stick |
| **Tab Switch (LB/RB)** | `Q` (Prev) / `E` (Next) | — | `LB` (Prev) / `RB` (Next) |
| **Confirm / Select** | `Enter` | `Space` | `A` (Bottom Face Button) |
| **Back / Cancel** | `Backspace` | `Escape` | `B` (Right Face Button) |

### Device Isolation Mode
Under **Options $\to$ Keyboard / Gamepad**, players can toggle between `BOTH ACTIVE`, `KEYBOARD ONLY`, or `GAMEPAD ONLY` to prevent multi-device interference during intense driving sessions.

---

## Installation & Setup

### Prerequisites
1. **Haxe Compiler:** [Haxe 4.3.0+](https://haxe.org/download/)
2. **Ash Wasm32 & WebGPU Libraries:** `hlwgpu`, `hlwindow`, `ash-future`, `oimo`, `utest`

### 1. Compilation & Dual-Target Packaging (IIS + GitHub Pages)
Build the HashLink bytecode, link the threaded WebGPU Wasm module, deploy to IIS, and package the static GitHub Pages mirror (`dist/gh-pages`):
```powershell
$env:PATH="$env:USERPROFILE\.ash\bin;$env:PATH"
$env:ASH_WASM_FIBERS="1"
haxe compile.hxml
ash --build web/game.wasm --target wasm32-wasip1-threads web/game.hl
node scripts/prepare-gh-pages.js dist/gh-pages
```
Or run the default VSCode build task (`Ctrl+Shift+B`), which executes `.vscode/build-deploy.ps1` to sync `web/*` to `C:\inetpub\mob-web` **and** build `dist/gh-pages` (`sw.js` COOP/COEP header injection + `.nojekyll` + cross-origin relay config). Pushing `main` triggers `.github/workflows/deploy-pages.yml` automatically.

### 2. Running Automated Tests

#### Haxe Unit Test Suite (`utest` via Ash)
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .vscode\run-tests.ps1
```
Executes **611 assertions** across all physics, input, UI, multiplayer, world, and camera suites (including the 3-car drivetrain/turning-radius and multi-device anti-inversion regression contract).

#### Dual-Target Playwright E2E Suite (`iis` + `gh-pages`)
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .vscode\run-e2e.ps1
```
Runs every spec against **both** targets automatically:
* **`[iis]`** (`http://127.0.0.1:7725/`): native COOP/COEP headers + `/relay.ashx` WS/HTTP relay.
* **`[gh-pages]`** (`http://127.0.0.1:7726/motors-on-boost/`): static host simulation with zero HTTP COOP/COEP headers, exercising `sw.js` isolation injection, one-time reload, subpath routing, and static fallback.

Covers **FXAA / SMAA / MSAA / TSAA** (`specs/aa-visual.spec.js`), Desktop + Mobile **anti-inversion controls** (`specs/controls-direction.spec.js`), and UI/options/car-select workflows (`specs/mob-ui-and-maps.spec.js`).

### 3. Running Locally
```powershell
# IIS simulation (native COOP/COEP + relay on port 7725):
node aitests/server.js --mode=iis --port=7725

# GitHub Pages mirror simulation (no HTTP COOP/COEP + /motors-on-boost/ subpath on port 7726):
node aitests/server.js --mode=gh-pages --port=7726
```
Navigate to `http://127.0.0.1:7725` or `http://127.0.0.1:7726/motors-on-boost/` in a WebGPU-capable browser (Edge, Chrome, or Safari iOS 18+/26+).

---

## Repository Governance & IP

This repository is maintained as an **in-house commercial prototype**. 

* **Contributions**: External contributions, unsolicited pull requests, and public feature branches are **strictly not accepted**. Please review [`CONTRIBUTING`](./CONTRIBUTING) for further details.
* **License**: All custom source code, shaders, procedural track logic, vehicle handling models, audio synthesizers, and graphic assets are licensed under a **Strict Proprietary License**. See [`LICENSE`](./LICENSE) for terms.
* **Security**: For responsible disclosure of vulnerabilities or defects, please consult [`SECURITY.md`](./SECURITY.md).

---

## Credits & Attributions

* **Lead Architect & Technical Designer:** Gerard "Jamie" (Jagofr) Francis
* **Published & Developed In-House By:** RvL // ROGUE
* **Graphics & Runtime Stack:** Haxe + Ash Wasm32 + `hlwgpu` / `hlwindow` (WebGPU) + OimoPhysics
* **Typography & Icons:**
  * *Stack Sans Headline* (SIL Open Font License)
  * *Material Symbols Sharp* (Apache License 2.0)
* **Homage & Gameplay Inspiration:**
  * *Need for Speed: Most Wanted (2005)* (Electronic Arts / Criterion Games)
  * *Burnout Revenge (2005)* (Electronic Arts / Criterion Games)

---

<div align="center">
  <sub>M.O.B. (Motors on Boost) is an original interactive project. All custom codebases, vehicles, handling physics, procedural tracks, and visual designs are the proprietary intellectual property of the creators. All rights reserved.</sub>
</div>