# M.O.B. (Motors on Boost)

A high-performance arcade highway racing prototype built for the web using **Haxe** and **Heaps.io**. Inspired by classic early-2000s arcade racers like *Need for Speed: Most Wanted (2005)* and *Burnout Revenge (2005)*, **M.O.B.** serves as the first playable baseline in the series, establishing core handling dynamics, procedural highway traffic, and WebGL rendering ahead of future iterations (including the planned Godot variant, *M.O.B. // Sektr*).

---

## Technical Overview

- **Language & Compiler:** Haxe 4.3+ targeting JavaScript / WebGL 2.0
- **Rendering Engine:** Heaps.io (`h3d` for 3D physics, track, and camera systems; `h2d` for HUD & UI)
- **Deployment Format:** Progressive Web App (PWA) with Service Worker caching and installable fullscreen standalone support
- **Input Architecture:** Full Gamepad API integration (PXN P50L, Xbox, and standard profiles) with edge-triggered bumper tab navigation and rebindable keyboard fallback
- **Asset Pipeline:** Embedded resources (`hxd.Res.initEmbed`) combined with an asynchronous DOM Canvas-to-Texture decoder (`loadWebpTile`) for 1080p WebP branding assets
- **Typography & Iconography:** Stack Sans Headline paired with procedural vector icons (`UIIcons.hx`) drawn via `h2d.Graphics`

---

## Engine & Subsystem Architecture

### 1. Sequential Boot & Preloader (`src/Main.hx`)
The application starts with a 3-part intro sequence driven by an explicit delta-time state machine:
- **Screen 1 (Studio Splash):** Dev Studio & Lead Developer branding (`intro/jagofr-rvl-splash.webp`). Skippable via any key/click.
- **Screen 2 (Engine Splash):** Heaps.io and Haxe engine credits (`intro/heaps-haxe-splash.webp`). Skippable.
- **Screen 3 (Disclaimer & Attribution):** Locked for a mandatory minimum duration (`disclaimerMinDuration = 5.5s`). Asset preloading (`startBackgroundLoading()`) executes asynchronously during this phase while displaying legal disclosures, FOSS acknowledgments, healthy gaming advisories, and ecosystem badge icons.
- **Showcase Hand-off:** On preloading completion, an opaque curtain (`showcaseCurtain`) cross-fades out over 1.2 seconds, unveiling the 3D rotating vehicle showcase and pulsating splash prompt without pop-in.

### 2. Physics & Handling Model (`src/physics/CarPhysics.hx`)
- Custom raycast-style suspension with dynamic compression and pitch/roll chassis settling.
- Multi-component friction modeling: forward acceleration, engine braking, rolling resistance, aerodynamic drag, and lateral tire slip.
- Explicit drift transition mechanics triggered via handbrake, counter-steering, or throttle manipulation, feeding dynamic trauma camera shake.

### 3. Highway Traffic Generation (`src/entities/TrafficSystem.hx`)
- Infinite procedural waypoint tracking across variable lane configurations.
- Spatial partitioning and proximity checks to manage vehicle density around the player.
- Dynamic lane-following AI with overtake and collision routines.

### 4. Dynamic Camera & Audio (`src/core/ChaseCamera.hx`, `src/core/AudioManager.hx`)
- Spring-arm camera with velocity look-ahead, speed-based FOV dilation, and non-linear trauma shake decay.
- Synthesized Web Audio pipeline handling engine frequency shifts, tire screech noise profiles, and nitro boost resonance.

---

## Project Structure

```text
├── compile.hxml              # Haxe compiler configuration
├── res/                      # Embedded binary and font assets
│   └── fonts/
│       ├── StackSansHeadline-VariableFont_wght.ttf
│       └── symbols.ttf
├── src/
│   ├── Main.hx               # Boot sequencing, async loader & primary loop
│   ├── core/
│   │   ├── AudioManager.hx   # Web Audio synthesizer & gain staging
│   │   ├── ChaseCamera.hx    # Spring-arm chase camera with trauma shake
│   │   ├── ControlDiagrams.hx# Dynamic gamepad and keyboard SVG/vector diagrams
│   │   ├── FontManager.hx    # Font atlas building and typography presets
│   │   ├── GraphicsManager.hx# Shadow maps, lighting buffers, and resolution scaling
│   │   ├── SaveSystem.hx     # LocalStorage persistence for settings & active runs
│   │   ├── UIIcons.hx        # Vector graphics procedural icon generator
│   │   └── UIManager.hx      # Navigation tabs, settings sliders, HUD & credits
│   ├── entities/
│   │   ├── CarMesh.hx        # Procedural vehicle chassis, wheels & materials
│   │   └── TrafficSystem.hx  # Highway traffic state machine & collision logic
│   ├── input/
│   │   └── InputController.hx# Edge-triggered digital/analog input coordinator
│   ├── physics/
│   │   └── CarPhysics.hx     # Suspension, friction, velocity & drift model
│   └── world/
│       └── Track.hx          # Procedural highway spline & track lift
└── web/                      # Web distribution & PWA host root
    ├── index.html            # WebGL canvas shell & <noscript> alert card
    ├── manifest.json         # PWA installation manifest
    ├── sw.js                 # Service worker cache strategy
    ├── game.js               # Compiled application bundle (generated)
    ├── icon-192.png          # App icon (192x192)
    ├── icon-512.png          # App icon (512x512)
    └── intro/                # Splash branding assets
        ├── jagofr-rvl-splash.webp
        ├── heaps-haxe-splash.webp
        └── icons/
            ├── logo_haxe.webp
            ├── logo_heaps.webp
            └── logo_webgl.webp

```

---

## Installation & Setup

### 1. Requirements

* [Haxe 4.3.0+](https://haxe.org/download/)
* Heaps library installed via Haxelib:
```bash
haxelib install heaps

```



### 2. Compile

From the project root:

```bash
haxe compile.hxml

```

### 3. Serve Locally

Because WebGL, Web Audio, and Service Workers require a secure origin (or `localhost`), serve the `web/` folder using any static HTTP server:

```bash
# Using Python 3:
cd web
python -m http.server 8000

```

Or:

```bash
# Using Node:
npx serve web

```

Open `http://localhost:8000` in any modern Chromium, Gecko, or WebKit browser.

---

## Controls

| Action | Keyboard | Gamepad (Standard / Xbox) |
| --- | --- | --- |
| **Throttle (Gas)** | `W` / `Up Arrow` | `RT` (Right Trigger) |
| **Brake / Reverse** | `S` / `Down Arrow` | `LT` (Left Trigger) |
| **Steering** | `A` / `D` or `Left` / `Right` | Left Analog Stick / D-Pad |
| **Handbrake (Drift)** | `Space` | `B` / `RB` |
| **Nitro Boost** | `Left Shift` | `A` / `LB` |
| **Pause / Menu** | `Esc` | `Start` / `Menu` |
| **Menu Navigation** | `Up` / `Down` / `Left` / `Right` | D-Pad / Left Stick |
| **Tab Switch** | `Q` / `E` | `LB` / `RB` |
| **Confirm** | `Enter` / `Space` | `A` (Bottom Face Button) |
| **Back / Cancel** | `Esc` / `Backspace` | `B` (Right Face Button) |

---

## Credits & Attributions

* **Lead Architect & Technical Designer:** Gerard "Jamie" (Jagofr) Francis
* **Published & Developed In-House By:** RvL // ROGUE
* **AI Engineering Collaboration:** Google Gemini 3.8 Flash
* **Engine Framework:** [Heaps.io](https://heaps.io/) by Nicolas Cannasse
* **Typography:** Stack Sans Headline & Material Symbols Sharp