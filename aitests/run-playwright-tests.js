const http = require('http');
const fs = require('fs');
const path = require('path');
const { attachSocketRelay } = require('../server/socket-relay');

// Resolve Playwright from local node_modules or npx cache
const npxNodeModules = path.join(process.env.LOCALAPPDATA || '', 'npm-cache', '_npx', 'e41f203b7505f1fb', 'node_modules');
let playwright;
try {
  playwright = require('playwright');
} catch (e) {
  playwright = require(path.join(npxNodeModules, 'playwright'));
}

const PORT = 7725;
const WEB_DIR = path.resolve(__dirname, '..', 'web');
const SCREENSHOT_DIR = path.resolve(__dirname, 'screenshots');

if (!fs.existsSync(SCREENSHOT_DIR)) {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
}

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css', '.wasm': 'application/wasm', '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm'
};

function startServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      let reqPath = decodeURI(req.url.split('?')[0]);
      if (reqPath === '/' || reqPath === '') reqPath = '/index.html';
      const filePath = path.join(WEB_DIR, reqPath);

      if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
        console.warn('[AITests Static 404]', reqPath);
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found: ' + reqPath);
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      const contentType = MIME_TYPES[ext] || 'application/octet-stream';

      res.writeHead(200, {
        'Content-Type': contentType,
        'Cache-Control': 'no-cache, no-store, must-revalidate', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp', 'Cross-Origin-Resource-Policy': 'same-origin'
      });
      fs.createReadStream(filePath).pipe(res);
    });

    attachSocketRelay(server, '/ws');

    server.on('error', reject);
    server.listen(PORT, '127.0.0.1', () => {
      console.log(`[AITests] Node static server + WS relay listening on http://127.0.0.1:${PORT}`);
      resolve(server);
    });
  });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
  console.log(`  PASS: ${message}`);
}

/**
 * Installs a cold-boot spy hook before game.js runs so we can count any 3D scene
 * render calls during IntroSequence, plus a W3C Gamepad API simulator when enabled.
 */
function bootAndGamepadInitScript(useGamepad) {
    window.__bootMetrics = {
      rendered3DWhileIntro: 0,
      uiVisibleWhileIntro: false,
      s3dHooked: false
    };

    let realApp = null;
    Object.defineProperty(window, 'app', {
      configurable: true,
      enumerable: true,
      get() { return realApp; },
      set(val) {
        realApp = val;
        if (val && val.s3d && !window.__bootMetrics.s3dHooked) {
          window.__bootMetrics.s3dHooked = true;
          const origRender = val.s3d.render.bind(val.s3d);
          val.s3d.render = function(e) {
            if (realApp.appState && realApp.appState._hx_name === 'IntroSequence') {
              window.__bootMetrics.rendered3DWhileIntro++;
            }
            if (realApp.appState && realApp.appState._hx_name === 'IntroSequence' && realApp.ui && realApp.ui.visible) {
              window.__bootMetrics.uiVisibleWhileIntro = true;
            }
            return origRender(e);
          };
        }
      }
    });

    if (useGamepad) {
      const buttons = [];
      for (let i = 0; i < 16; i++) buttons.push({ pressed: false, touched: false, value: 0 });
      window.__mockPad = {
        id: 'Xbox 360 Controller (STANDARD GAMEPAD)',
        index: 0,
        connected: true,
        mapping: 'standard',
        timestamp: performance.now(),
        axes: [0, 0, 0, 0],
        buttons
      };
      navigator.getGamepads = () => [window.__mockPad];
    }
}

/**
 * Builds an input driver abstraction exposing uniform UI & driving primitives
 * across 'keyboard', 'gamepad', and 'touch' profiles using real browser events.
 */
function createInputDriver(page, profile) {
  async function waitFrames(count = 2) {
    await page.evaluate((n) => new Promise((resolve) => {
      let left = n;
      const tick = () => {
        if (--left <= 0) resolve();
        else requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }), count);
  }

  async function stepAppFrames(frames = 18, dt = 1 / 60) {
    if (profile === 'gamepad') {
      // Allow Heaps hxd.Pad.syncPads() (MainLoop rAF) to poll navigator.getGamepads() first
      await waitFrames(2);
    }
    await page.evaluate(({ n, step }) => {
      for (let i = 0; i < n; i++) window.app.update(step);
    }, { n: frames, step: dt });
  }

  async function focusCanvas() {
    if (profile !== 'touch') {
      await page.evaluate(() => {
        const c = (document.getElementById('screen') || document.getElementById('webgl'));
        if (c) c.focus();
      });
      await waitFrames(1);
    }
  }

  // ---- Gamepad helpers ----
  async function connectGamepadIfNeeded() {
    if (profile !== 'gamepad') return;
    await page.evaluate(() => {
      const ev = new Event('gamepadconnected');
      ev.gamepad = window.__mockPad;
      window.dispatchEvent(ev);
    });
    await stepAppFrames(16);
  }

  async function padSetButton(idx, down, value) {
    await page.evaluate(({ idx, down, val }) => {
      const pad = window.__mockPad;
      pad.buttons[idx].pressed = down;
      pad.buttons[idx].touched = down;
      pad.buttons[idx].value = val !== undefined ? val : (down ? 1 : 0);
      pad.timestamp = performance.now();
    }, { idx, down, val: value });
  }

  async function padTapButton(idx) {
    await padSetButton(idx, true, 1);
    await waitFrames(2);
    await stepAppFrames(3);
    await padSetButton(idx, false, 0);
    await waitFrames(2);
    await stepAppFrames(16);
  }

  async function padSetAxis(axisIdx, value) {
    await page.evaluate(({ axisIdx, value }) => {
      const pad = window.__mockPad;
      pad.axes[axisIdx] = value;
      pad.timestamp = performance.now();
    }, { axisIdx, value });
  }

  // ---- Keyboard helpers ----
  async function keyTap(code) {
    await page.keyboard.down(code);
    await stepAppFrames(2);
    await page.keyboard.up(code);
    await stepAppFrames(16);
  }

  // ---- Touch helpers ----
  async function tapInteractive(getterPath) {
    // Allow at least 2 animation frames so Heaps s2d.render() syncs absX/absY & interactive hit list
    await waitFrames(2);
    const pt = await page.evaluate((pathStr) => {
      const app = window.app;
      let target = app;
      for (const seg of pathStr.split('.')) {
        if (target == null) return null;
        if (seg.endsWith(']')) {
          const m = seg.match(/^(.+)\[(\d+)\]$/);
          target = target[m[1]][parseInt(m[2], 10)];
        } else {
          target = target[seg];
        }
      }
      if (!target) return null;
      const canvas = (document.getElementById('screen') || document.getElementById('webgl'));
      const rect = canvas.getBoundingClientRect();
      const s2d = app.s2d;
      const sx = target.absX + target.width * 0.5;
      const sy = target.absY + target.height * 0.5;
      const relX = sx * s2d.viewportScaleX + s2d.offsetX;
      const relY = sy * s2d.viewportScaleY + s2d.offsetY;
      return {
        x: rect.left + (relX / app.getEngine().width) * rect.width,
        y: rect.top + (relY / app.getEngine().height) * rect.height
      };
    }, getterPath);
    if (!pt) throw new Error(`Could not resolve touch interactive path: ${getterPath}`);
    await page.touchscreen.tap(pt.x, pt.y);
    await waitFrames(2);
    await stepAppFrames(16);
  }

  async function getTouchHudClientPoint(hudPropX, hudPropY, dxOffset = 0, dyOffset = 0) {
    return page.evaluate(({ propX, propY, dx, dy }) => {
      const app = window.app;
      const hud = app.ui.builder.touchControlsHUD;
      const s2d = app.s2d;
      const rect = (document.getElementById('screen') || document.getElementById('webgl')).getBoundingClientRect();
      const hx = (typeof hud[propX] === 'number' ? hud[propX] : 0) + dx;
      const hy = (typeof hud[propY] === 'number' ? hud[propY] : 0) + dy;
      return {
        x: rect.left + (hx / s2d.width) * rect.width,
        y: rect.top + (hy / s2d.height) * rect.height
      };
    }, { propX: hudPropX, propY: hudPropY, dx: dxOffset, dy: dyOffset });
  }

  async function dispatchCanvasTouch(type, activeTouchSpecs, changedTouchSpecs) {
    await page.evaluate(({ type, activeSpecs, changedSpecs }) => {
      const canvas = (document.getElementById('screen') || document.getElementById('webgl'));
      const makeTouch = (spec) => new Touch({
        identifier: spec.id,
        target: canvas,
        clientX: spec.x,
        clientY: spec.y,
        pageX: spec.x,
        pageY: spec.y,
        radiusX: 12,
        radiusY: 12,
        force: type === 'touchend' ? 0 : 1
      });
      const touches = activeSpecs.map(makeTouch);
      const changedTouches = changedSpecs.map(makeTouch);
      const ev = new TouchEvent(type, {
        bubbles: true,
        cancelable: true,
        touches,
        targetTouches: touches,
        changedTouches
      });
      canvas.dispatchEvent(ev);
    }, { type, activeSpecs: activeTouchSpecs, changedSpecs: changedTouchSpecs });
  }

  return {
    profile,
    waitFrames,
    stepAppFrames,
    focusCanvas,
    connectGamepadIfNeeded,
    tapInteractive,
    getTouchHudClientPoint,
    dispatchCanvasTouch,

    // Uniform UI navigation across Keyboard & Gamepad (Touch uses direct taps)
    async uiUp() {
      if (profile === 'keyboard') await keyTap('ArrowUp');
      else if (profile === 'gamepad') await padTapButton(12); // DPAD_UP
    },
    async uiDown() {
      if (profile === 'keyboard') await keyTap('ArrowDown');
      else if (profile === 'gamepad') await padTapButton(13); // DPAD_DOWN
    },
    async uiLeft() {
      if (profile === 'keyboard') await keyTap('ArrowLeft');
      else if (profile === 'gamepad') await padTapButton(14); // DPAD_LEFT
    },
    async uiRight() {
      if (profile === 'keyboard') await keyTap('ArrowRight');
      else if (profile === 'gamepad') await padTapButton(15); // DPAD_RIGHT
    },
    async uiConfirm() {
      if (profile === 'keyboard') await keyTap('Enter');
      else if (profile === 'gamepad') await padTapButton(0); // BTN_SOUTH (A)
    },
    async uiCancel() {
      if (profile === 'keyboard') await keyTap('Escape');
      else if (profile === 'gamepad') await padTapButton(1); // BTN_EAST (B)
    },
    async uiNextTab() {
      if (profile === 'keyboard') await keyTap('KeyE');
      else if (profile === 'gamepad') await padTapButton(5); // BTN_RB
    },
    async uiPrevTab() {
      if (profile === 'keyboard') await keyTap('KeyQ');
      else if (profile === 'gamepad') await padTapButton(4); // BTN_LB
    },
    async pauseFromGame() {
      if (profile === 'keyboard') await keyTap('Escape');
      else if (profile === 'gamepad') await padTapButton(9); // BTN_START
      else {
        const pt = await getTouchHudClientPoint('pauseX', 'pauseY');
        await page.touchscreen.tap(pt.x, pt.y);
        await stepAppFrames(16);
      }
    },

    // Drive forward for durationFrames with optional steering (-1 = Left, 0 = Straight, +1 = Right)
    async drive(steerDir = 0, durationFrames = 45) {
      if (profile === 'keyboard') {
        await focusCanvas();
        await page.keyboard.down('KeyW');
        if (steerDir < 0) await page.keyboard.down('KeyA');
        else if (steerDir > 0) await page.keyboard.down('KeyD');
        await stepAppFrames(durationFrames);
        if (steerDir < 0) await page.keyboard.up('KeyA');
        else if (steerDir > 0) await page.keyboard.up('KeyD');
        await page.keyboard.up('KeyW');
        await stepAppFrames(4);
      } else if (profile === 'gamepad') {
        await padSetButton(7, true, 1.0); // TRIG_RT Gas
        await padSetAxis(0, steerDir);
        await waitFrames(3);
        await stepAppFrames(durationFrames);
        await padSetAxis(0, 0);
        await padSetButton(7, false, 0.0);
        await waitFrames(2);
        await stepAppFrames(4);
      } else {
        // Real DOM multi-touch on TouchControlsHUD Virtual Gas Pedal + Virtual Analog Steering Wheel
        const gasPt = await getTouchHudClientPoint('gasX', 'gasY');
        const stickTravel = await page.evaluate(() => window.app.ui.builder.touchControlsHUD.stickMaxTravel);
        const stickStart = await getTouchHudClientPoint('stickBaseX', 'stickBaseY');
        const stickTarget = await getTouchHudClientPoint('stickBaseX', 'stickBaseY', steerDir * stickTravel, 0);

        const fingers = [{ id: 102, x: gasPt.x, y: gasPt.y }];
        if (steerDir !== 0) {
          const stickFinger = { id: 101, x: stickStart.x, y: stickStart.y };
          await dispatchCanvasTouch('touchstart', [stickFinger], [stickFinger]);
          stickFinger.x = stickTarget.x;
          stickFinger.y = stickTarget.y;
          fingers.unshift(stickFinger);
          await dispatchCanvasTouch('touchmove', fingers, [stickFinger]);
        }
        await dispatchCanvasTouch('touchstart', fingers, [{ id: 102, x: gasPt.x, y: gasPt.y }]);
        await stepAppFrames(durationFrames);
        await dispatchCanvasTouch('touchend', [], fingers);
        await stepAppFrames(4);
      }
    }
  };
}

/**
 * Executes the full 5-scenario smoke test suite under a specific input profile:
 * 'keyboard', 'gamepad', or 'touch'.
 */
async function runProfileGamut(browser, targetUrl, profile) {
  console.log(`\n======================================================================`);
  console.log(`[PROFILE: ${profile.toUpperCase()}] Starting full 5-Scenario Smoke Gamut`);
  console.log(`======================================================================`);

  const isTouch = (profile === 'touch');
  const contextOptions = isTouch
    ? { viewport: { width: 915, height: 412 }, hasTouch: true, isMobile: true }
    : { viewport: { width: 1280, height: 720 } };

  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();

  // Also test boot anti-flash under pre-saved 1080p/non-default UI resolution on Keyboard,
  // clean empty storage on Gamepad & Touch.
  await page.addInitScript(bootAndGamepadInitScript, profile === 'gamepad');

  const runtimeErrors = [];
  page.on('pageerror', (err) => runtimeErrors.push(`pageerror: ${err.message}`));
  page.on('response', (res) => {
    if (res.status() >= 400) runtimeErrors.push(`http ${res.status()}: ${res.url()}`);
  });
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      const loc = msg.location();
      runtimeErrors.push(`console.error: ${msg.text()} (${loc ? loc.url : ''})`);
    }
  });

  try {
    const driver = createInputDriver(page, profile);

    // =========================================================================
    // SCENARIO 1: No Game Flash During Boot -> Studio -> Engine -> Disclaimer -> Splash
    // =========================================================================
    console.log(`[${profile}][Scenario 1] Boot anti-flash + Studio -> Engine -> Disclaimer + silent preload -> Splash...`);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });

    await page.waitForFunction(() => {
      return window.app && window.app.s2d && window.app.introController;
    }, { timeout: 15000 });

    // Wait across the 30ms deferred world warm-up window while staying in IntroSequence
    await page.waitForTimeout(220);

    const earlyBootCheck = await page.evaluate(() => ({
      appState: window.app.appState ? window.app.appState._hx_name : null,
      introState: window.app.introState ? window.app.introState._hx_name : null,
      rendered3DWhileIntro: window.__bootMetrics.rendered3DWhileIntro,
      uiVisibleWhileIntro: window.__bootMetrics.uiVisibleWhileIntro || (window.app.ui ? window.app.ui.visible : false),
      domProgressEls: document.querySelectorAll('progress, [role="progressbar"], .progress, #progress, #loading-bar').length
    }));

    assert(earlyBootCheck.appState === 'IntroSequence', `App stays in IntroSequence on boot (state=${earlyBootCheck.appState})`);
    assert(earlyBootCheck.rendered3DWhileIntro === 0, `Zero 3D game frames rendered during early boot (${earlyBootCheck.rendered3DWhileIntro})`);
    assert(!earlyBootCheck.uiVisibleWhileIntro, 'UI views stay hidden before boot intro finishes');
    assert(earlyBootCheck.domProgressEls === 0, 'Zero progress bar DOM elements shown during boot/preloading');

    // Wait for Studio/Engine splash bitmaps to finish background decoding
    await page.waitForFunction(() => {
      return window.app.studioSplashBmp && window.app.engineSplashBmp && window.app.world;
    }, { timeout: 15000 });

    await page.screenshot({ path: path.join(SCREENSHOT_DIR, `${profile}-01-studio-boot.png`) });

    // Verify Disclaimer gating holds behind pending background loading and still renders ZERO 3D frames
    const gating = await page.evaluate(() => {
      const app = window.app;
      const releasePending = app.preloader.beginExternalTask();
      app.setIntroScreen(window.IntroState.Studio);
      app.introController.update(app.preloader.config.studioDuration + 0.1);
      const reachedEngine = app.introState._hx_name === 'Engine';
      app.introController.update(app.preloader.config.engineDuration + 0.1);
      const reachedDisclaimer = app.introState._hx_name === 'Disclaimer';

      app.introController.update(1.0);
      app.introController.update(app.preloader.config.disclaimerMinDuration + 2.0);
      const heldDisclaimer = app.introState._hx_name === 'Disclaimer' && (!app.ui || !app.ui.visible);

      releasePending();
      const preloaderFinished = app.preloader.isComplete;
      app.introController.update(app.preloader.config.disclaimerFadeOutDuration + 0.2);

      // Step showcase reveal curtain so Splash is fully interactive
      for (let i = 0; i < 35; i++) app.update(1 / 20);

      return {
        reachedEngine,
        reachedDisclaimer,
        heldDisclaimer,
        rendered3DWhileIntro: window.__bootMetrics.rendered3DWhileIntro,
        preloaderFinished,
        completedIntroState: app.introState._hx_name,
        splashActive: app.ui && app.ui.visible && app.ui.currentState._hx_name === 'Splash'
      };
    });

    assert(gating.reachedEngine && gating.reachedDisclaimer, 'Boot traverses Studio -> Engine -> Disclaimer');
    assert(gating.heldDisclaimer, 'Splash held behind Disclaimer until background loading finishes');
    assert(gating.rendered3DWhileIntro === 0, `Zero 3D game frames rendered across entire IntroSequence (${gating.rendered3DWhileIntro})`);
    assert(gating.preloaderFinished && gating.completedIntroState === 'Complete' && gating.splashActive, 'Splash activates automatically after preload & Disclaimer finish');

    await driver.connectGamepadIfNeeded();
    await driver.focusCanvas();
    await page.evaluate(() => {
      localStorage.clear();
      window.app.saveData.hasActiveRun = false;
      window.app.ui.setHasActiveSave(false);
    });

    // Enter Main Menu from Splash using the active profile's real input!
    if (isTouch) {
      await driver.tapInteractive('ui.builder.splashView.screenHit');
    } else {
      await driver.uiConfirm();
    }
    const enteredMenuState = await page.evaluate(() => window.app.ui.currentState._hx_name);
    assert(enteredMenuState === 'MainMenu', `${profile} input entered Main Menu from Splash`);

    // =========================================================================
    // SCENARIO 2: Exercise ALL 6 Main Menu Buttons via Active Input
    // =========================================================================
    console.log(`[${profile}][Scenario 2] Exercising ALL 6 Main Menu buttons...`);
    const mmLabels = await page.evaluate(() => window.app.ui.builder.mainMenuView.rows.map(r => r.labelTxt.text));
    assert(mmLabels.length === 6 && mmLabels[0] === 'PLAY SINGLEPLAYER' && mmLabels[2] === 'MULTIPLAYER LOBBY',
      `Main Menu exposes all 6 entries (${JSON.stringify(mmLabels)})`
    );

    // 1. PLAY SINGLEPLAYER -> MapSelect -> Back
    if (isTouch) {
      await driver.tapInteractive('ui.builder.mainMenuView.rows[0].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MapSelect', 'Touch PLAY SINGLEPLAYER -> MapSelect');
      await driver.tapInteractive('ui.builder.mapSelectView.backInteractive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch MapSelect Back -> MainMenu');

      // 2. RESUME SAVED RACE (disabled while no active save)
      await driver.tapInteractive('ui.builder.mainMenuView.rows[1].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch RESUME blocked without save');

      // 3. MULTIPLAYER LOBBY -> MultiplayerMenu -> Back
      await driver.tapInteractive('ui.builder.mainMenuView.rows[2].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MultiplayerMenu', 'Touch MULTIPLAYER LOBBY -> MultiplayerMenu');
      await driver.tapInteractive('ui.builder.multiplayerMenuView.backInteractive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch Multiplayer Back -> MainMenu');

      // 4. OPTIONS -> Back
      await driver.tapInteractive('ui.builder.mainMenuView.rows[3].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'OptionsMenu', 'Touch OPTIONS -> OptionsMenu');
      await driver.tapInteractive('ui.builder.optionsView.backInteractive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch Options Back -> MainMenu');

      // 5. CREDITS -> Back
      await driver.tapInteractive('ui.builder.mainMenuView.rows[4].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'CreditsScreen', 'Touch CREDITS -> CreditsScreen');
      await driver.tapInteractive('ui.builder.creditsView.backInteractive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch Credits Back -> MainMenu');

      // 6. EXIT TO SPLASH -> Splash -> Re-enter
      await driver.tapInteractive('ui.builder.mainMenuView.rows[5].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'Splash', 'Touch EXIT TO SPLASH -> Splash');
      await driver.stepAppFrames(30); // Wait Splash cooldown
      await driver.tapInteractive('ui.builder.splashView.screenHit');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch Splash -> MainMenu');
    } else {
      // Row 0: PLAY SINGLEPLAYER -> Cancel Back
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MapSelect', `${profile} PLAY SINGLEPLAYER -> MapSelect`);
      await driver.uiCancel();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} MapSelect Cancel -> MainMenu`);

      // Row 1: RESUME SAVED RACE (disabled while empty)
      await driver.uiDown();
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} RESUME blocked without save`);

      // Row 2: MULTIPLAYER LOBBY -> MultiplayerMenu -> Cancel Back
      await driver.uiDown();
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MultiplayerMenu', `${profile} MULTIPLAYER LOBBY -> MultiplayerMenu`);
      await driver.uiCancel();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} Multiplayer Cancel -> MainMenu`);

      // Row 3: OPTIONS -> Cancel Back (cursor resets to 0 after returning from subview, so step 3 down)
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'OptionsMenu', `${profile} OPTIONS -> OptionsMenu`);
      await driver.uiCancel();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} Options Cancel -> MainMenu`);

      // Row 4: CREDITS -> Cancel Back (step 4 down)
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'CreditsScreen', `${profile} CREDITS -> CreditsScreen`);
      await driver.uiCancel();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} Credits Cancel -> MainMenu`);

      // Row 5: EXIT TO SPLASH -> Re-enter
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'Splash', `${profile} EXIT TO SPLASH -> Splash`);
      await driver.stepAppFrames(30); // Wait Splash cooldown
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} Splash Confirm -> MainMenu`);
    }

    // =========================================================================
    // SCENARIO 3: Exercise ALL 5 Options Tabs & Controls via Active Input
    // =========================================================================
    console.log(`[${profile}][Scenario 3] Exercising ALL 5 Options tabs & controls...`);
    if (isTouch) {
      await driver.tapInteractive('ui.builder.mainMenuView.rows[3].interactive');

      // Tab 0: Graphics
      const beforeShadow = await page.evaluate(() => window.app.ui.gfxSettings.shadowLevel);
      await driver.tapInteractive('ui.builder.optionsView.gfxPanel.interactives[1]');
      const afterShadow = await page.evaluate(() => window.app.ui.gfxSettings.shadowLevel);
      assert(beforeShadow !== afterShadow, `Touch Graphics Shadow cycled (${beforeShadow} -> ${afterShadow})`);
      await page.evaluate((orig) => {
        const g = window.app.ui.builder.optionsView.gfxPanel;
        while (window.app.ui.gfxSettings.shadowLevel !== orig) g.cycleOption(1, 1);
      }, beforeShadow);

      // Tab 1: Audio
      await driver.tapInteractive('ui.builder.optionsView.tabInteractives[1]');
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Audio', 'Touch switched to Audio tab');
      const beforeMaster = await page.evaluate(() => window.app.audio.masterVolume);
      await driver.tapInteractive('ui.builder.optionsView.audioPanel.interactives[0]');
      assert(await page.evaluate(() => window.app.audio.masterVolume) !== beforeMaster, 'Touch adjusted Master volume');

      // Tab 2: Keyboard
      await driver.tapInteractive('ui.builder.optionsView.tabInteractives[2]');
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Keyboard', 'Touch switched to Keyboard tab');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.toggleViewModeInter');
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.controlsPanel.controlViewMode) === 'Custom', 'Touch toggled Keyboard Custom mode');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.toggleViewModeInter');

      // Tab 3: Gamepad
      await driver.tapInteractive('ui.builder.optionsView.tabInteractives[3]');
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Gamepad', 'Touch switched to Gamepad tab');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.toggleExclusiveInter');
      assert(await page.evaluate(() => window.app.input.exclusiveDevice._hx_name) === 'GamepadOnly', 'Touch toggled GamepadOnly device');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.toggleExclusiveInter'); // Restore Both

      // Tab 4: Touch + sensitivity + layout reset
      await driver.tapInteractive('ui.builder.optionsView.tabInteractives[4]');
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Touch', 'Touch switched to Touch tab');
      const beforeSens = await page.evaluate(() => window.app.input.steerSensitivity);
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.sensDecrInter');
      assert(Math.abs((beforeSens - 0.02) - await page.evaluate(() => window.app.input.steerSensitivity)) < 0.001, 'Touch decremented sensitivity slider');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.sensIncrInter');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.toggleViewModeInter');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.remapIncrInteractives[0]');
      assert(await page.evaluate(() => window.app.saveData.touchSettings.stickOffsetX) === 10, 'Touch +10 increased Stick X offset to +10');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.remapDecrInteractives[0]');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.remapDecrInteractives[0]');
      assert(await page.evaluate(() => window.app.saveData.touchSettings.stickOffsetX) === -10, 'Touch -10 decreased Stick X offset to -10');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.remapDecrInteractives[10]');
      assert(await page.evaluate(() => window.app.saveData.touchSettings.scale) < 1.0, 'Touch -5% decreased HUD Scale');
      await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'touch-custom-offsets.png') });
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.remapInteractives[11]');
      assert(await page.evaluate(() => window.app.saveData.touchSettings.stickOffsetX === 0 && window.app.saveData.touchSettings.scale === 1.0), 'Touch Reset Default Layout restored defaults');
      await driver.tapInteractive('ui.builder.optionsView.controlsPanel.toggleViewModeInter');

      // Back
      await driver.tapInteractive('ui.builder.optionsView.backInteractive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch Options Back -> MainMenu');
    } else {
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiConfirm(); // Opens OPTIONS on Graphics tab (row 3)

      // Tab 0: Graphics
      const beforeShadow = await page.evaluate(() => window.app.ui.gfxSettings.shadowLevel);
      await driver.uiDown(); // index 1 = Shadow Quality
      await driver.uiRight();
      const afterShadow = await page.evaluate(() => window.app.ui.gfxSettings.shadowLevel);
      assert(beforeShadow !== afterShadow, `${profile} Graphics Shadow cycled (${beforeShadow} -> ${afterShadow})`);
      await page.evaluate((orig) => {
        const g = window.app.ui.builder.optionsView.gfxPanel;
        while (window.app.ui.gfxSettings.shadowLevel !== orig) g.cycleOption(1, 1);
      }, beforeShadow);

      // Tab 1: Audio
      await driver.uiNextTab();
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Audio', `${profile} switched to Audio tab`);
      const beforeMaster = await page.evaluate(() => window.app.audio.masterVolume);
      await driver.uiLeft();
      assert(await page.evaluate(() => window.app.audio.masterVolume) !== beforeMaster, `${profile} adjusted Master volume`);

      // Tab 2: Keyboard
      await driver.uiNextTab();
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Keyboard', `${profile} switched to Keyboard tab`);
      const kbdBeforeSens = await page.evaluate(() => window.app.input.steerSensitivity);
      await driver.uiLeft();
      assert(Math.abs((kbdBeforeSens - 0.02) - await page.evaluate(() => window.app.input.steerSensitivity)) < 0.001, `${profile} adjusted sensitivity on Keyboard tab`);
      await driver.uiRight();
      await driver.uiConfirm(); // Diagram -> Custom via Confirm
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.controlsPanel.controlViewMode) === 'Custom', `${profile} Confirm toggled Keyboard Custom mode`);
      await driver.uiDown();
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.controlsPanel.remapIndex) === 1, `${profile} navigated Custom remap rows`);

      // Tab 3: Gamepad
      await driver.uiNextTab();
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Gamepad', `${profile} switched to Gamepad tab`);

      // Tab 4: Touch
      await driver.uiNextTab();
      assert(await page.evaluate(() => window.app.ui.builder.optionsView.currentTab._hx_name) === 'Touch', `${profile} switched to Touch tab`);
      const stickBeforeX = await page.evaluate(() => window.app.saveData.touchSettings.stickOffsetX);
      await driver.uiUp(); // Back to row 0 (stickOffsetX) since Custom mode remembered remapIndex = 1
      await driver.uiRight();
      assert(await page.evaluate(() => window.app.saveData.touchSettings.stickOffsetX) !== stickBeforeX, `${profile} adjusted Touch Stick X offset`);
      // Reset layout row (row 11 = 1 step up from 0)
      await driver.uiUp();
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.saveData.touchSettings.stickOffsetX) === 0, `${profile} reset Touch layout defaults`);
      // Restore Diagram mode cleanly for subsequent tabs
      await page.evaluate(() => window.app.ui.builder.optionsView.controlsPanel.toggleCustomMode());

      await driver.uiCancel();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} Options Back -> MainMenu`);
    }

    // =========================================================================
    // SCENARIO 4: Map 1 Load -> Pause Restart -> Main Menu -> Map 2 Load -> Pause Restart -> Resume
    // =========================================================================
    console.log(`[${profile}][Scenario 4] Map 1 -> Pause Restart -> Main Menu -> Map 2 -> Pause Restart -> Resume...`);

    // Launch Map 1 (Circuit)
    if (isTouch) {
      await driver.tapInteractive('ui.builder.mainMenuView.rows[0].interactive');
      await driver.tapInteractive('ui.builder.mapSelectView.mapInteractives[0]');
    } else {
      await driver.uiConfirm(); // PLAY SINGLEPLAYER
      await driver.uiConfirm(); // Map 0 = Circuit
    }

    const circuitLoaded = await page.evaluate(() => ({
      mode: window.app.currentMapMode._hx_name,
      uiState: window.app.ui.currentState._hx_name,
      touchVisible: window.app.ui.builder.touchControlsHUD.visible
    }));
    assert(circuitLoaded.mode === 'Circuit' && circuitLoaded.uiState === 'InGameHUD', `${profile} loaded Map 1 (Circuit)`);
    if (isTouch) assert(circuitLoaded.touchVisible, 'Virtual TouchControlsHUD visible automatically on mobile touch screen');

    await driver.drive(0, 45);
    const circuitDist = await page.evaluate(() => Math.hypot(window.app.carPhysics.pos.x, window.app.carPhysics.pos.y));
    assert(circuitDist > 2.0, `${profile} drove car forward on Circuit (${circuitDist.toFixed(2)}m)`);

    // Pause -> RESTART MAP on Circuit
    await driver.pauseFromGame();
    assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'PauseMenu', `${profile} paused Circuit into PauseMenu`);
    if (isTouch) {
      await driver.tapInteractive('ui.builder.pauseMenuView.rows[1].interactive');
    } else {
      await driver.uiDown(); // row 1 = RESTART MAP
      await driver.uiConfirm();
    }
    const circuitRestart = await page.evaluate(() => ({
      mode: window.app.currentMapMode._hx_name,
      uiState: window.app.ui.currentState._hx_name,
      dist: Math.hypot(window.app.carPhysics.pos.x, window.app.carPhysics.pos.y)
    }));
    assert(circuitRestart.mode === 'Circuit' && circuitRestart.uiState === 'InGameHUD' && circuitRestart.dist < 0.05, `${profile} Pause RESTART MAP reset Circuit car`);

    // Pause -> MAIN MENU -> Select Map 2 (Sandbox)
    await driver.pauseFromGame();
    if (isTouch) {
      await driver.tapInteractive('ui.builder.pauseMenuView.rows[3].interactive');
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', 'Touch Pause MAIN MENU -> MainMenu');
      await driver.tapInteractive('ui.builder.mainMenuView.rows[0].interactive');
      await driver.tapInteractive('ui.builder.mapSelectView.mapInteractives[1]');
    } else {
      await driver.uiDown(); // row 1
      await driver.uiDown(); // row 2
      await driver.uiDown(); // row 3 = MAIN MENU
      await driver.uiConfirm();
      assert(await page.evaluate(() => window.app.ui.currentState._hx_name) === 'MainMenu', `${profile} Pause MAIN MENU -> MainMenu`);
      await driver.uiUp(); // With active save, MainMenu defaults to row 1; step up to row 0 (PLAY SINGLEPLAYER)
      await driver.uiConfirm(); // PLAY SINGLEPLAYER
      await driver.uiRight(); // Map 1 = Sandbox
      await driver.uiConfirm();
    }

    assert(await page.evaluate(() => window.app.currentMapMode._hx_name === 'Sandbox' && window.app.ui.currentState._hx_name === 'InGameHUD'), `${profile} switched cleanly to Map 2 (Sandbox)`);

    await driver.drive(0, 45);
    const sandboxDist = await page.evaluate(() => Math.hypot(window.app.carPhysics.pos.x, window.app.carPhysics.pos.y));
    assert(sandboxDist > 2.0, `${profile} drove car forward on Sandbox (${sandboxDist.toFixed(2)}m)`);

    // Pause -> RESTART MAP on Sandbox
    await driver.pauseFromGame();
    if (isTouch) {
      await driver.tapInteractive('ui.builder.pauseMenuView.rows[1].interactive');
    } else {
      await driver.uiDown(); // RESTART MAP
      await driver.uiConfirm();
    }
    const sandboxRestartDist = await page.evaluate(() => Math.hypot(window.app.carPhysics.pos.x, window.app.carPhysics.pos.y));
    assert(sandboxRestartDist < 0.05, `${profile} Pause RESTART MAP reset Sandbox car (${sandboxRestartDist.toFixed(2)}m)`);

    // Drive forward, Pause -> MAIN MENU -> RESUME SAVED RACE
    await driver.drive(0, 45);
    await driver.pauseFromGame();
    const savedY = await page.evaluate(() => window.app.saveData.playerState.posY);
    if (isTouch) {
      await driver.tapInteractive('ui.builder.pauseMenuView.rows[3].interactive');
      await driver.tapInteractive('ui.builder.mainMenuView.rows[1].interactive');
    } else {
      await driver.uiDown();
      await driver.uiDown();
      await driver.uiDown(); // MAIN MENU
      await driver.uiConfirm();
      await driver.uiUp();
      await driver.uiDown(); // Confirm cursor sits on RESUME SAVED RACE (row 1)
      await driver.uiConfirm();
    }
    const resumed = await page.evaluate(() => ({
      mode: window.app.currentMapMode._hx_name,
      uiState: window.app.ui.currentState._hx_name,
      posY: window.app.carPhysics.pos.y
    }));
    assert(
      resumed.mode === 'Sandbox' && resumed.uiState === 'InGameHUD' && savedY > 3.0 && resumed.posY >= savedY - 0.05 && Math.abs(resumed.posY - savedY) < 10.0,
      `${profile} RESUME SAVED RACE restored Sandbox position (savedY=${savedY.toFixed(2)}m, resumedY=${resumed.posY.toFixed(2)}m)`
    );

    // =========================================================================
    // SCENARIO 5: Left/Right Steering Direction Accuracy + Rims + Traffic + Circuit Y=195
    // =========================================================================
    console.log(`[${profile}][Scenario 5] Verifying Left/Right steering accuracy, wheel rims, traffic & Circuit Y=195...`);

    await page.evaluate(() => {
      window.app.resetCarToSandboxCenter();
      window.app.input.flushInputs();
    });
    await driver.drive(-1, 60);
    const leftRes = await page.evaluate(() => ({
      posX: window.app.carPhysics.pos.x,
      posY: window.app.carPhysics.pos.y,
      yaw: window.app.carPhysics.yaw
    }));
    assert(
      leftRes.posX > 0.8 && leftRes.posY > 3.5 && leftRes.yaw > 0.15,
      `${profile} STEER LEFT moved +X (${leftRes.posX.toFixed(2)}m) and yaw > 0 (${leftRes.yaw.toFixed(3)} rad)`
    );

    await page.evaluate(() => {
      window.app.resetCarToSandboxCenter();
      window.app.input.flushInputs();
    });
    await driver.drive(1, 60);
    const rightRes = await page.evaluate(() => ({
      posX: window.app.carPhysics.pos.x,
      posY: window.app.carPhysics.pos.y,
      yaw: window.app.carPhysics.yaw
    }));
    assert(
      rightRes.posX < -0.8 && rightRes.posY > 3.5 && rightRes.yaw < -0.15,
      `${profile} STEER RIGHT moved -X (${rightRes.posX.toFixed(2)}m) and yaw < 0 (${rightRes.yaw.toFixed(3)} rad)`
    );

    await page.screenshot({ path: path.join(SCREENSHOT_DIR, `${profile}-05-steering-verified.png`) });

    if (profile === 'gamepad' || profile === 'touch') {
      await page.evaluate(() => {
        window.app.resetCarToSandboxCenter();
        window.app.input.flushInputs();
      });
      await driver.drive(-0.5, 60);
      const analogLeft = await page.evaluate(() => ({
        posX: window.app.carPhysics.pos.x,
        yaw: window.app.carPhysics.yaw
      }));
      assert(
        analogLeft.posX > 0.15 && analogLeft.yaw > 0.04 && analogLeft.yaw < leftRes.yaw,
        `${profile} ANALOG 50% LEFT steered gently +X (${analogLeft.posX.toFixed(2)}m, yaw=${analogLeft.yaw.toFixed(3)})`
      );

      await page.evaluate(() => {
        window.app.resetCarToSandboxCenter();
        window.app.input.flushInputs();
      });
      await driver.drive(0.5, 60);
      const analogRight = await page.evaluate(() => ({
        posX: window.app.carPhysics.pos.x,
        yaw: window.app.carPhysics.yaw
      }));
      assert(
        analogRight.posX < -0.15 && analogRight.yaw < -0.04 && analogRight.yaw > rightRes.yaw,
        `${profile} ANALOG 50% RIGHT steered gently -X (${analogRight.posX.toFixed(2)}m, yaw=${analogRight.yaw.toFixed(3)})`
      );
    }

    // Verify wheel rims, traffic collision damping, Circuit rail support, and Y=195 free navigation
    const worldChecks = await page.evaluate(() => {
      const app = window.app;
      app.resetCarToSandboxCenter();
      app.update(1 / 60);
      const pm = app.playerMesh;
      const rimsOk = pm.bodyMesh.y === 0 && pm.rimCaps[0].z < 0 && pm.rimCaps[2].z < 0 && pm.rimCaps[1].z > 0 && pm.rimCaps[3].z > 0;

      app.loadMap(window.MapMode.Circuit);
      app.resetCarToStartLine();
      const tc = app.traffic.trafficList[0];
      tc.isOncoming = false;
      tc.currentSpeed = 10.0;
      tc.pos.x = 0.0;
      tc.pos.y = 2.2;
      tc.pos.z = 0.06;

      app.carPhysics.pos.x = 0.0;
      app.carPhysics.pos.y = 0.0;
      app.carPhysics.pos.z = 0.06;
      app.carPhysics.yaw = 0.0;
      app.carPhysics.forwardSpeed = 32.0;
      app.carPhysics.syncToOimoBody();
      app.update(1 / 60);
      const speedAfterHit = app.carPhysics.forwardSpeed;

      // Ride along right Armco guardrail and confirm wheels/chassis never clip below roadbed
      app.carPhysics.resetState(9.2, 10.0, 0.06, 0.0);
      app.carPhysics.forwardSpeed = 28.0;
      app.carPhysics.syncToOimoBody();
      app.input.flushInputs();
      app.input.throttle = 1.0;
      let minRailClearance = 999.0;
      for (let i = 0; i < 45; i++) {
        app.update(1 / 60);
        const surfZ = app.track.getGroundElevation(app.carPhysics.pos.x, app.carPhysics.pos.y);
        const clearance = app.carPhysics.pos.z - surfZ;
        if (clearance < minRailClearance) minRailClearance = clearance;
      }

      app.carPhysics.pos.x = 45.0;
      app.carPhysics.pos.y = 185.0;
      app.carPhysics.pos.z = 2.0;
      app.carPhysics.yaw = 0.70;
      app.carPhysics.forwardSpeed = 35.0;
      app.carPhysics.syncToOimoBody();
      for (let i = 0; i < 40; i++) app.update(1 / 60);

      return {
        rimsOk,
        speedAfterHit,
        minRailClearance,
        circuitY: app.carPhysics.pos.y,
        circuitZ: app.carPhysics.pos.z,
        circuitSpeed: app.carPhysics.forwardSpeed
      };
    });

    assert(worldChecks.rimsOk, `${profile} CarMesh centered & 4 wheel rims outward`);
    assert(worldChecks.speedAfterHit < 28.0, `${profile} Traffic collision damped speed (${worldChecks.speedAfterHit.toFixed(1)} m/s)`);
    assert(worldChecks.minRailClearance >= -0.05, `${profile} Circuit guardrail riding stayed above road surface (minClearance=${worldChecks.minRailClearance.toFixed(3)}m)`);
    assert(worldChecks.circuitY > 200.0 && worldChecks.circuitSpeed > 30.0 && worldChecks.circuitZ > 0.0,
      `${profile} Highway Circuit navigated past Y=195 freely (Y=${worldChecks.circuitY.toFixed(1)}m)`
    );

    assert(runtimeErrors.length === 0, `${profile} Zero console/page/HTTP errors (found: ${JSON.stringify(runtimeErrors)})`);
  } finally {
    await context.close();
  }
}

async function runOrientationLockChecks(browser, targetUrl) {
  console.log('\n[ORIENTATION GATE] Verifying mobile & tablet portrait blocking, auto-force landscape, and prompt-only fallback...');

  // 1. Mobile Portrait (412x915, touch) on device that CANNOT force landscape -> Prompt-only, 0 game load, pause/resume on rotation
  {
    const ctx = await browser.newContext({
      viewport: { width: 412, height: 915 },
      isMobile: true,
      hasTouch: true
    });
    const page = await ctx.newPage();
    await page.addInitScript(() => {
      try {
        Object.defineProperty(window.screen.orientation, 'lock', {
          configurable: true,
          value: () => Promise.reject(new DOMException('Orientation lock unsupported', 'NotSupportedError'))
        });
      } catch (_) {}
    });
    await page.addInitScript(bootAndGamepadInitScript, false);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(350);

    const blockedState = await page.evaluate(() => {
      const overlay = document.getElementById('rotate-device-overlay');
      const forceBtn = document.getElementById('force-landscape-btn');
      return {
        portraitBlockedClass: document.documentElement.classList.contains('portrait-blocked'),
        mobPortraitBlocked: Boolean(window.__mobPortraitBlocked),
        overlayDisplay: overlay ? getComputedStyle(overlay).display : null,
        forceBtnHidden: forceBtn ? forceBtn.hidden : null,
        appExists: Boolean(window.app),
        scriptTagCount: document.querySelectorAll('script[src*="game.js"]').length,
        gateLoaded: window.MOBOrientationGate ? window.MOBOrientationGate.isGameLoaded() : null
      };
    });
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'orientation-01-mobile-portrait-blocked.png') });

    assert(blockedState.portraitBlockedClass && blockedState.mobPortraitBlocked,
      `Mobile portrait set portrait-blocked gate (state=${JSON.stringify(blockedState)})`
    );
    assert(blockedState.overlayDisplay === 'flex', `Portrait overlay visible (display=${blockedState.overlayDisplay})`);
    assert(blockedState.forceBtnHidden === true, `Unsupported device shows rotate prompt only (forceBtnHidden=${blockedState.forceBtnHidden})`);
    assert(!blockedState.appExists && blockedState.scriptTagCount === 0 && blockedState.gateLoaded === false,
      `Game script did NOT load or execute while in portrait mode`
    );

    // Rotate phone to landscape -> game loads cleanly with 0 3D flash
    await page.setViewportSize({ width: 915, height: 412 });
    await page.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
    await page.waitForTimeout(250);
    const unlockedState = await page.evaluate(() => ({
      portraitBlockedClass: document.documentElement.classList.contains('portrait-blocked'),
      pausedByOrientation: Boolean(window.app.pausedByOrientation),
      appState: window.app.appState._hx_name,
      rendered3DWhileIntro: window.__bootMetrics.rendered3DWhileIntro
    }));
    assert(!unlockedState.portraitBlockedClass && !unlockedState.pausedByOrientation,
      'Rotating phone to landscape unlocks and loads game'
    );
    assert(unlockedState.appState === 'IntroSequence' && unlockedState.rendered3DWhileIntro === 0,
      `Delayed mobile load still suppresses 3D before intro screens (3D frames=${unlockedState.rendered3DWhileIntro})`
    );

    // Mid-session rotate back to portrait -> freezes update() & shows prompt
    await page.setViewportSize({ width: 412, height: 915 });
    await page.waitForFunction(() => window.app && window.app.pausedByOrientation === true, { timeout: 5000 });
    const t1 = await page.evaluate(() => window.app.introTimer);
    await page.waitForTimeout(280);
    const midBlocked = await page.evaluate(() => ({
      t2: window.app.introTimer,
      paused: window.app.pausedByOrientation,
      overlayDisplay: getComputedStyle(document.getElementById('rotate-device-overlay')).display
    }));
    assert(midBlocked.paused && midBlocked.overlayDisplay === 'flex' && Math.abs(midBlocked.t2 - t1) < 0.001,
      `Mid-session portrait rotation paused game loop (t1=${t1}, t2=${midBlocked.t2})`
    );

    // Rotate back to landscape -> resumes cleanly
    await page.setViewportSize({ width: 915, height: 412 });
    await page.waitForFunction(() => window.app && window.app.pausedByOrientation === false, { timeout: 5000 });
    await page.waitForTimeout(220);
    const t3 = await page.evaluate(() => window.app.introTimer);
    assert(t3 > midBlocked.t2, `Returning to landscape resumed game loop (t2=${midBlocked.t2.toFixed(2)}, t3=${t3.toFixed(2)})`);
    await ctx.close();
  }

  // 2. Large Tablet Portrait (1024x1366, touch) on device that CAN force landscape automatically
  {
    const ctx = await browser.newContext({
      viewport: { width: 1024, height: 1366 },
      isMobile: true,
      hasTouch: true
    });
    const page = await ctx.newPage();
    let lockCalls = 0;
    await page.exposeFunction('__pwTabletAutoLandscape', async () => {
      lockCalls++;
      await page.setViewportSize({ width: 1366, height: 1024 });
    });
    await page.addInitScript(() => {
      try {
        Object.defineProperty(window.screen.orientation, 'lock', {
          configurable: true,
          value: async (mode) => {
            if (String(mode).startsWith('landscape')) {
              await window.__pwTabletAutoLandscape();
              return;
            }
            throw new DOMException('Unsupported mode', 'NotSupportedError');
          }
        });
      } catch (_) {}
    });
    await page.addInitScript(bootAndGamepadInitScript, false);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
    await page.waitForTimeout(200);
    const tabletState = await page.evaluate(() => ({
      width: window.innerWidth,
      height: window.innerHeight,
      portraitBlocked: Boolean(window.__mobPortraitBlocked),
      overlayDisplay: getComputedStyle(document.getElementById('rotate-device-overlay')).display,
      rendered3DWhileIntro: window.__bootMetrics.rendered3DWhileIntro
    }));
    await ctx.close();
    assert(lockCalls >= 1 && tabletState.width > tabletState.height && !tabletState.portraitBlocked && tabletState.overlayDisplay === 'none',
      `Tablet portrait auto-forced landscape mode without leaving rotate prompt (lockCalls=${lockCalls}, ${tabletState.width}x${tabletState.height})`
    );
    assert(tabletState.rendered3DWhileIntro === 0,
      `Auto-forced tablet boot still rendered 0 premature 3D frames`
    );
  }

  // 3. Tablet/Mobile Portrait (768x1024, touch) where force-landscape needs fullscreen user gesture
  {
    const ctx = await browser.newContext({
      viewport: { width: 768, height: 1024 },
      isMobile: true,
      hasTouch: true
    });
    const page = await ctx.newPage();
    await page.exposeFunction('__pwGestureForceLandscape', async () => {
      await page.setViewportSize({ width: 1024, height: 768 });
    });
    await page.addInitScript(() => {
      window.__mockFullscreen = false;
      try {
        Object.defineProperty(document, 'fullscreenElement', {
          configurable: true,
          get: () => (window.__mockFullscreen ? document.documentElement : null)
        });
      } catch (_) {}
      try {
        Object.defineProperty(Element.prototype, 'requestFullscreen', {
          configurable: true,
          value: async () => {
            window.__mockFullscreen = true;
          }
        });
      } catch (e) {
        console.error('Failed to stub Element.prototype.requestFullscreen', e);
      }
      try {
        Object.defineProperty(window.ScreenOrientation.prototype, 'lock', {
          configurable: true,
          value: async (mode) => {
            if (!window.__mockFullscreen) {
              throw new DOMException('lock() requires fullscreen', 'SecurityError');
            }
            if (String(mode).startsWith('landscape')) {
              await window.__pwGestureForceLandscape();
              return;
            }
            throw new DOMException('Unsupported mode', 'NotSupportedError');
          }
        });
      } catch (e) {
        console.error('Failed to stub ScreenOrientation.prototype.lock', e);
      }
    });
    await page.addInitScript(bootAndGamepadInitScript, false);
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => document.documentElement.classList.contains('portrait-blocked'), { timeout: 5000 });
    const btnBox = await page.locator('#force-landscape-btn').boundingBox();
    const gateDebug = await page.evaluate(() => ({
      appMissing: !window.app,
      blocked: window.__mobPortraitBlocked === true,
      btnHidden: document.getElementById('force-landscape-btn').hidden
    }));
    assert(gateDebug.appMissing && gateDebug.blocked && !gateDebug.btnHidden && btnBox && btnBox.height >= 44 && btnBox.width >= 44,
      `Gesture-capable device keeps game unloaded in portrait & renders >=44px force-landscape button (${JSON.stringify({ gateDebug, btnBox })})`
    );
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'orientation-02-tablet-force-btn.png') });
    await page.locator('#force-landscape-btn').tap();
    await page.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
    const afterTap = await page.evaluate(() => ({
      width: window.innerWidth,
      height: window.innerHeight,
      blocked: Boolean(window.__mobPortraitBlocked)
    }));
    await ctx.close();
    assert(afterTap.width > afterTap.height && !afterTap.blocked,
      `Tapping Switch to Landscape forced landscape (${afterTap.width}x${afterTap.height}) and loaded game`
    );
  }
}

async function clickInteractiveMouse(page, getterPath) {
  const pt = await page.evaluate((pathStr) => {
    const app = window.app;
    if (!app) return null;
    const parts = pathStr.split('.');
    let target = app;
    for (const seg of parts) {
      if (seg.endsWith(']')) {
        const m = seg.match(/^(.+)\[(\d+)\]$/);
        target = target[m[1]][parseInt(m[2], 10)];
      } else {
        target = target[seg];
      }
    }
    if (!target) return null;
    const rect = (document.getElementById('screen') || document.getElementById('webgl')).getBoundingClientRect();
    const s2d = app.s2d;
    const sx = target.absX + target.width * 0.5;
    const sy = target.absY + target.height * 0.5;
    const relX = sx * s2d.viewportScaleX + s2d.offsetX;
    const relY = sy * s2d.viewportScaleY + s2d.offsetY;
    return {
      x: rect.left + (relX / app.getEngine().width) * rect.width,
      y: rect.top + (relY / app.getEngine().height) * rect.height
    };
  }, getterPath);
  if (!pt) throw new Error(`Could not resolve interactive click target: ${getterPath}`);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(80);
}

/**
 * Verifies peer-to-peer client/server lobby flow across two separate browser contexts:
 * Host creates room over dumb WS relay -> Client opens `?room=` invite link -> Host-validated
 * roster + map switching (Sandbox & Circuit) -> Start Match -> live 3D remote car sync.
 */
async function runMultiplayerLobbyAndMatchCheck(browser, targetUrl) {
  console.log(`\n======================================================================`);
  console.log(`[MULTIPLAYER P2P] Testing Host + Invite-Link Client over WS Relay`);
  console.log(`======================================================================`);

  const hostCtx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const clientCtx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const hostPage = await hostCtx.newPage();
  const clientPage = await clientCtx.newPage();

  const errors = [];
  for (const [label, p] of [['Host', hostPage], ['Client', clientPage]]) {
    p.on('pageerror', (e) => errors.push(`${label} pageerror: ${e.message}`));
    p.on('console', (m) => {
      if (m.type() === 'error') errors.push(`${label} console.error: ${m.text()}`);
    });
  }

  try {
    const hostDriver = createInputDriver(hostPage, 'keyboard');
    const clientDriver = createInputDriver(clientPage, 'keyboard');

    // 1. Host boots -> Splash -> Main Menu -> Multiplayer Lobby
    await hostPage.goto(targetUrl, { waitUntil: 'networkidle' });
    await hostPage.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
    await hostPage.evaluate(() => window.app.finishIntroSequence());
    await hostPage.waitForFunction(() => window.app.ui && window.app.ui.currentState._hx_name === 'Splash', { timeout: 10000 });
    await hostDriver.stepAppFrames(35);
    await hostDriver.focusCanvas();
    await hostDriver.uiConfirm();
    await hostPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'MainMenu', { timeout: 5000 });

    // Row 2 = MULTIPLAYER LOBBY -> Host or Join Menu -> Confirm Card 0 (HOST A MATCH)
    await hostDriver.uiDown();
    await hostDriver.uiDown();
    await hostDriver.uiConfirm();
    await hostPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'MultiplayerMenu', { timeout: 5000 });
    await hostDriver.uiConfirm();
    await hostPage.waitForFunction(() => {
      const mp = window.app && window.app.multiplayer;
      return window.app.ui.currentState._hx_name === 'MultiplayerLobby'
        && mp && mp.role._hx_name === 'Host'
        && mp.status._hx_name === 'WaitingInLobby'
        && mp.roomId.length > 0;
    }, { timeout: 10000 });

    const hostRoomInfo = await hostPage.evaluate(() => ({
      roomId: window.app.multiplayer.roomId,
      inviteUrl: window.app.multiplayer.getInviteLink(),
      peers: window.app.multiplayer.peers.length
    }));
    assert(hostRoomInfo.inviteUrl.includes(`?room=${hostRoomInfo.roomId}`),
      `Host opened room ${hostRoomInfo.roomId} via Host-or-Join menu with shareable invite URL (${hostRoomInfo.inviteUrl})`
    );

    // 1B. Verify HTTP POST /relay.ashx interoperability against the active WS Host room
    const httpRelayUrl = targetUrl.replace(/\/$/, '') + '/relay.ashx';
    const pingRes = await fetch(httpRelayUrl + '?ping=1').then((r) => r.json());
    assert(pingRes && pingRes.ok === true, `HTTP /relay.ashx endpoint active (relay=${pingRes && pingRes.relay})`);

    const httpProbe1 = await fetch(httpRelayUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: [{ type: 'join_room', roomId: hostRoomInfo.roomId }] })
    }).then((r) => r.json());
    const joinedEvt = (httpProbe1.events || []).find((e) => e.type === 'room_joined');
    assert(httpProbe1.ok && httpProbe1.connId && joinedEvt && joinedEvt.roomId === hostRoomInfo.roomId,
      `HTTP POST /relay.ashx peer joined live Host room ${hostRoomInfo.roomId} across WS+HTTP bridge`
    );
    await fetch(httpRelayUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ connId: httpProbe1.connId, messages: [{ type: 'leave_room' }] })
    });

    // 2A. Client checks invalid room fails cleanly (not stuck on Joining room...), then types valid Invite Code
    await clientPage.goto(targetUrl, { waitUntil: 'networkidle' });
    await clientPage.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
    await clientPage.evaluate(() => window.app.finishIntroSequence());
    await clientPage.waitForFunction(() => window.app.ui && window.app.ui.currentState._hx_name === 'Splash', { timeout: 10000 });
    await clientDriver.stepAppFrames(35);
    await clientDriver.focusCanvas();
    await clientDriver.uiConfirm();
    await clientPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'MainMenu', { timeout: 5000 });
    await clientDriver.uiDown();
    await clientDriver.uiDown();
    await clientDriver.uiConfirm();
    await clientPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'MultiplayerMenu', { timeout: 5000 });
    await clientDriver.uiRight();
    await clientPage.keyboard.type('NOPE99');
    await clientDriver.uiConfirm();
    await clientPage.waitForFunction(() => {
      const mp = window.app && window.app.multiplayer;
      return mp && mp.status._hx_name === 'Disconnected' && mp.lastError.length > 0;
    }, { timeout: 6000 });
    console.log('  PASS: Joining missing room surfaced immediate error without infinite "Joining room..."');

    await clickInteractiveMouse(clientPage, 'ui.builder.multiplayerLobbyView.backInteractive');
    await clientPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'MultiplayerMenu', { timeout: 5000 });
    await clientDriver.uiRight();
    await clickInteractiveMouse(clientPage, 'ui.builder.multiplayerMenuView.clearCodeInteractive');
    await clientPage.keyboard.type(hostRoomInfo.roomId);
    await clientPage.evaluate(() => { window.app.update(1 / 60); });
    await clientPage.screenshot({ path: path.join(SCREENSHOT_DIR, 'mp-00-host-or-join-code.png') });
    await clientDriver.uiConfirm();

    await clientPage.waitForFunction(() => {
      const mp = window.app && window.app.multiplayer;
      return window.app.ui.currentState._hx_name === 'MultiplayerLobby'
        && mp && mp.role._hx_name === 'Client'
        && mp.status._hx_name === 'WaitingInLobby'
        && mp.peers.length === 2;
    }, { timeout: 12000 });
    await hostPage.waitForFunction(() => window.app.multiplayer.peers.length === 2, { timeout: 8000 });
    console.log('  PASS: Client joined Host lobby by typing Invite Code in Host-or-Join menu (2/8 drivers)');

    // Client backs out cleanly to Host-or-Join menu before testing direct URL join
    await clickInteractiveMouse(clientPage, 'ui.builder.multiplayerLobbyView.backInteractive');
    await clientPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'MultiplayerMenu', { timeout: 5000 });
    await hostPage.waitForFunction(() => window.app.multiplayer.peers.length === 1, { timeout: 6000 });

    // 2B. Client opens Invite Link directly and auto-joins Host's lobby
    await clientPage.goto(hostRoomInfo.inviteUrl, { waitUntil: 'networkidle' });
    await clientPage.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
    await clientPage.evaluate(() => window.app.finishIntroSequence());
    await clientDriver.stepAppFrames(25);

    await clientPage.waitForFunction(() => {
      const mp = window.app && window.app.multiplayer;
      return window.app.ui.currentState._hx_name === 'MultiplayerLobby'
        && mp && mp.role._hx_name === 'Client'
        && mp.status._hx_name === 'WaitingInLobby'
        && mp.peers.length === 2;
    }, { timeout: 12000 });

    await hostPage.waitForFunction(() => window.app.multiplayer.peers.length === 2, { timeout: 8000 });
    console.log('  PASS: Client auto-joined Host lobby via invite URL and both peers see 2/8 drivers');

    // 3. Host selects Sandbox then Circuit -> verify Client follows Host map selection
    await clickInteractiveMouse(hostPage, 'ui.builder.multiplayerLobbyView.mapInteractives[1]');
    await clientPage.waitForFunction(() => window.app.multiplayer.selectedMap._hx_name === 'Sandbox', { timeout: 6000 });
    console.log('  PASS: Host switched match map to Sandbox and Client lobby synced cleanly');

    await clickInteractiveMouse(hostPage, 'ui.builder.multiplayerLobbyView.mapInteractives[0]');
    await clientPage.waitForFunction(() => window.app.multiplayer.selectedMap._hx_name === 'Circuit', { timeout: 6000 });
    await hostPage.screenshot({ path: path.join(SCREENSHOT_DIR, 'mp-01-host-lobby.png') });
    await clientPage.screenshot({ path: path.join(SCREENSHOT_DIR, 'mp-02-client-lobby.png') });

    // 4. Host starts match -> both load Circuit on staggered grid and exchange live vehicle states
    await clickInteractiveMouse(hostPage, 'ui.builder.multiplayerLobbyView.startMatchInteractive');

    await hostPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'InGameHUD', { timeout: 10000 });
    await clientPage.waitForFunction(() => window.app.ui.currentState._hx_name === 'InGameHUD', { timeout: 10000 });

    await hostPage.evaluate(() => { window.app.update(1 / 60); });
    await clientPage.evaluate(() => { window.app.update(1 / 60); });

    const matchStartState = await Promise.all([
      hostPage.evaluate(() => {
        const rc = Object.keys((window.app.world.remoteCars && window.app.world.remoteCars.h) || {}).length;
        return {
          mode: window.app.currentMapMode._hx_name,
          x: window.app.carPhysics.pos.x,
          y: window.app.carPhysics.pos.y,
          remoteCount: rc
        };
      }),
      clientPage.evaluate(() => {
        const rc = Object.keys((window.app.world.remoteCars && window.app.world.remoteCars.h) || {}).length;
        return {
          mode: window.app.currentMapMode._hx_name,
          x: window.app.carPhysics.pos.x,
          y: window.app.carPhysics.pos.y,
          remoteCount: rc
        };
      })
    ]);

    assert(matchStartState[0].mode === 'Circuit' && matchStartState[1].mode === 'Circuit',
      'Both Host and Client loaded chosen Circuit match map'
    );
    assert(matchStartState[0].remoteCount === 1 && matchStartState[1].remoteCount === 1,
      `Both Host and Client spawned remote 3D vehicle actor (hostRemotes=${matchStartState[0].remoteCount}, clientRemotes=${matchStartState[1].remoteCount})`
    );
    assert(Math.abs(matchStartState[0].x - matchStartState[1].x) > 1.0,
      `Staggered starting grid separated Host (x=${matchStartState[0].x.toFixed(2)}) and Client (x=${matchStartState[1].x.toFixed(2)})`
    );

    // 5. Drive Host forward -> verify Client observes Host vehicle moving over relay
    await hostDriver.drive(0, 55);
    await hostPage.waitForTimeout(180);
    await clientDriver.stepAppFrames(25);

    const afterDrive = await Promise.all([
      hostPage.evaluate(() => ({ y: window.app.carPhysics.pos.y })),
      clientPage.evaluate(() => {
        const h = (window.app.world.remoteCars && window.app.world.remoteCars.h) || {};
        let remoteY = -999;
        for (const k of Object.keys(h)) {
          remoteY = h[k].currentY;
        }
        return { remoteY };
      })
    ]);
    await hostPage.screenshot({ path: path.join(SCREENSHOT_DIR, 'mp-03-match-live.png') });
    assert(afterDrive[0].y > 5.0 && afterDrive[1].remoteY > 2.0,
      `Live P2P telemetry replicated Host movement (hostY=${afterDrive[0].y.toFixed(2)}m, clientSeesHostY=${afterDrive[1].remoteY.toFixed(2)}m)`
    );
    assert(errors.length === 0, `Zero console/page errors during multiplayer match (${JSON.stringify(errors)})`);
  } finally {
    await hostCtx.close();
    await clientCtx.close();
  }
}

async function runTests() {
  const targetUrl = process.env.MOB_TEST_URL || `http://127.0.0.1:${PORT}`;
  let server = null;

  if (!process.env.MOB_TEST_URL) {
    server = await startServer();
  }

  console.log(`[AITests] Launching Playwright Chromium (Edge channel) targeting ${targetUrl}...`);
  const browser = await playwright.chromium.launch({
    channel: 'msedge',
    headless: true,
    args: ['--use-gl=angle', '--enable-unsafe-webgpu']
  });

  try {
    // Also verify boot anti-flash under a non-16:9 viewport (1440x900) where LetterBox/AutoZoom mismatch used to leak 3D skybox
    console.log('\n[PRE-CHECK] Verifying non-16:9 viewport (1440x900) with pre-saved 1080p UI res renders ZERO 3D frames on boot...');
    {
      const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
      const page = await ctx.newPage();
      await page.addInitScript(() => {
        localStorage.setItem('mob_motors_on_boost_save_v4', JSON.stringify({
          version: 4,
          buildNumber: 10,
          hasActiveRun: false,
          playerState: { posX: 0, posY: 0, posZ: 0, yaw: 0, forwardSpeed: 0 },
          masterVol: 0.8,
          musicVol: 0.7,
          sfxVol: 0.9,
          steerSensitivity: 1.0,
          graphics: {
            textures: 'High', shadowLevel: 'Normal', shadowRes: 1024,
            lightingLevel: 'Medium', lightingRes: 1024, mipmapping: true,
            anisotropic: 4, aaType: 'FXAA', aaLevel: 2, modelGeometry: 'Medium',
            modelReflections: true, reflectionLevel: 'Medium', renderScale: 1.0,
            uiResolution: '1080p (FHD)'
          }
        }));
      });
      await page.addInitScript(bootAndGamepadInitScript, false);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => window.app && window.app.introController, { timeout: 15000 });
      await page.waitForTimeout(260);
      const metrics = await page.evaluate(() => ({
        appState: window.app.appState._hx_name,
        rendered3DWhileIntro: window.__bootMetrics.rendered3DWhileIntro,
        uiVisible: window.app.ui ? window.app.ui.visible : false
      }));
      await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'precheck-1440x900-boot.png') });
      await ctx.close();
      assert(metrics.appState === 'IntroSequence' && metrics.rendered3DWhileIntro === 0 && !metrics.uiVisible,
        `Non-16:9 1440x900 boot suppressed 3D world completely during intro (3D frames=${metrics.rendered3DWhileIntro})`
      );
    }

    for (const profile of ['keyboard', 'gamepad', 'touch']) {
      await runProfileGamut(browser, targetUrl, profile);
    }

    await runOrientationLockChecks(browser, targetUrl);
    await runMultiplayerLobbyAndMatchCheck(browser, targetUrl);

    console.log(`\nALL 3 INPUT PROFILES (KEYBOARD + GAMEPAD + TOUCH) + ORIENTATION LOCK + P2P MULTIPLAYER CHECKS PASSED! Screenshots: ${SCREENSHOT_DIR}`);
  } finally {
    await browser.close();
    if (server) server.close();
  }
}

runTests().catch((err) => {
  console.error('\nPLAYWRIGHT TEST FAILURE:', err);
  process.exit(1);
});
