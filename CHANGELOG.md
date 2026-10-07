# Changelog

All notable changes to **M.O.B. (Motors on Boost)** will be documented in this file and tracked in the `changelogs/` directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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