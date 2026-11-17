const { test, expect } = require('@playwright/test');
const path = require('path');
const fs = require('fs');
const zlib = require('zlib');
const { getScreenshotDir, gotoGame } = require('./test-helpers');

let SCREENSHOT_DIR = path.resolve(__dirname, '..', 'screenshots');

function sampleCornerPixelLuma(pngBuffer) {
  let pos = 8, width = 0, height = 0, colorType = 6;
  const idat = [];
  while (pos < pngBuffer.length) {
    const len = pngBuffer.readUInt32BE(pos);
    const type = pngBuffer.slice(pos + 4, pos + 8).toString('ascii');
    const data = pngBuffer.slice(pos + 8, pos + 8 + len);
    if (type === 'IHDR') { width = data.readUInt32BE(0); height = data.readUInt32BE(4); colorType = data[9]; }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    pos += 12 + len;
  }
  const bpp = colorType === 6 ? 4 : 3;
  const stride = width * bpp + 1;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const recon = Buffer.alloc(height * width * bpp);
  for (let y = 0; y < height; y++) {
    const rowIn = y * stride, filter = raw[rowIn], rowOut = y * width * bpp, prev = (y - 1) * width * bpp;
    for (let x = 0; x < width * bpp; x++) {
      const val = raw[rowIn + 1 + x];
      const a = x >= bpp ? recon[rowOut + x - bpp] : 0;
      const b = y > 0 ? recon[prev + x] : 0;
      const c = (x >= bpp && y > 0) ? recon[prev + x - bpp] : 0;
      let o = val;
      if (filter === 1) o = (val + a) & 0xff;
      else if (filter === 2) o = (val + b) & 0xff;
      else if (filter === 3) o = (val + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        o = (val + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c))) & 0xff;
      }
      recon[rowOut + x] = o;
    }
  }
  // Top-left corner strip inside intro viewport (should stay near pure black during fade-to-black)
  let maxCornerLuma = 0;
  for (let y = 6; y < 28; y += 4) {
    for (let x = 6; x < 28; x += 4) {
      const idx = (y * width + x) * bpp;
      const luma = recon[idx] + recon[idx + 1] + recon[idx + 2];
      if (luma > maxCornerLuma) maxCornerLuma = luma;
    }
  }
  return { maxCornerLuma };
}

test.describe('M.O.B. // WebGPU Full UI, Options, Cross-Input & Fade-to-Black Smoke Suite', () => {
  test.beforeEach(async ({ page }, testInfo) => {
    SCREENSHOT_DIR = getScreenshotDir(testInfo);
    await page.addInitScript(() => {
      // Inject controllable virtual W3C gamepad before app boots
      window.__virtualPad = null;
      const origGetGamepads = navigator.getGamepads ? navigator.getGamepads.bind(navigator) : () => [];
      navigator.getGamepads = () => (window.__virtualPad ? [window.__virtualPad] : origGetGamepads());
    });
  });

  test('1. Intro sequences fade through opaque black without flashing 3D canvas', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));

    await gotoGame(page);

    const observedStages = [];
    for (let i = 0; i < 65; i++) {
      const snap = await page.evaluate(() => {
        const il = document.getElementById('intro-layer');
        const st = il ? il.querySelector('.intro-stage') : null;
        return {
          appState: window.app?.appState,
          introState: window.app?.introState,
          uiState: window.app?.ui?.currentState,
          ilOpacity: il ? getComputedStyle(il).opacity : null,
          ilBg: il ? getComputedStyle(il).backgroundColor : null,
          stageOpacity: st ? st.style.opacity : null,
          text: document.getElementById('ui-root')?.innerText || ''
        };
      });

      if (snap.appState === 'IntroSequence' && snap.introState && snap.introState !== 'None') {
        expect(snap.ilOpacity).toBe('1');
        expect(snap.ilBg).toBe('rgb(0, 0, 0)');
        expect(snap.text).not.toContain('M.O.B. STUDIOS');
        expect(snap.text).not.toContain('Heaps.io');
        expect(snap.text).not.toContain('WebGL');

        if (!observedStages.includes(snap.introState)) {
          observedStages.push(snap.introState);
          const shot = await page.screenshot({ path: path.join(SCREENSHOT_DIR, `pw-intro-${snap.introState.toLowerCase()}.png`) });
          const px = sampleCornerPixelLuma(shot);
          // Even during fade transitions, background corner stays black/near-black (no 3D sky flash)
          if (snap.introState === 'Studio') {
            expect(px.maxCornerLuma).toBeLessThanOrEqual(45);
          }
        }
      }
      if (snap.appState === 'InGameUI') break;
      await page.waitForTimeout(250);
    }

    expect(observedStages.length).toBeGreaterThanOrEqual(1);
    await page.waitForSelector('#splash-layer', { timeout: 15000 });
    await page.waitForTimeout(950); // allow showcase black curtain to dissolve
    expect(errors).toEqual([]);
  });

  async function bootToMainMenu(page) {
    await gotoGame(page);
    for (let i = 0; i < 65; i++) {
      const state = await page.evaluate(() => ({
        intro: window.app?.introState,
        ui: window.app?.ui?.currentState,
        app: window.app?.appState
      }));
      if (state.app === 'InGameUI' && state.ui === 'Splash') break;
      if (state.app === 'IntroSequence' && (state.intro === 'Studio' || state.intro === 'Engine')) {
        await page.evaluate(() => { const il = document.getElementById('intro-layer'); if (il) il.click(); });
      }
      await page.waitForTimeout(220);
    }
    await page.waitForSelector('#splash-layer', { timeout: 15000 });
    await page.click('#btn-splash-enter');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });
  }

  test('2. Every Menu Button, Back Routing, Graphics 14 Rows & AA Modes, Pause-Options Lock & Reload Persistence', async ({ page }, testInfo) => {
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });

    await bootToMainMenu(page);
    const hostCheck = await page.evaluate(() => ({
      env: window.__MOB_ENV__,
      coi: window.crossOriginIsolated,
      hasSwController: Boolean(navigator.serviceWorker && navigator.serviceWorker.controller),
      pathname: window.location.pathname
    }));
    expect(hostCheck.coi).toBe(true);
    if (testInfo.project.name === 'iis' || testInfo.project.name === 'gh-pages') {
      expect(hostCheck.env && hostCheck.env.target).toBe(testInfo.project.name);
    }
    if (testInfo.project.name === 'gh-pages') {
      expect(hostCheck.pathname.startsWith('/motors-on-boost/')).toBe(true);
      expect(hostCheck.hasSwController).toBe(true);
    }
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'pw-main-menu.png') });

    // Check 1:1 MainMenu button alignment & keyboard ArrowDown skips disabled Row 1
    const mainBtns = await page.locator('.menu-list .mob-btn').allTextContents();
    expect(mainBtns.length).toBe(6);
    expect(mainBtns[0]).toContain('PLAY SINGLEPLAYER');
    expect(mainBtns[1]).toContain('RESUME SAVED RACE');
    expect(await page.locator('.menu-list .mob-btn').nth(1).isDisabled()).toBe(true);
    expect(mainBtns[5]).toContain('EXIT TO SPLASH');

    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(150);
    expect(await page.evaluate(() => window.app.state.mainMenuIdx)).toBe(2); // skipped idx 1
    await page.keyboard.press('ArrowUp');
    await page.waitForTimeout(150);
    expect(await page.evaluate(() => window.app.state.mainMenuIdx)).toBe(0);

    // Credits -> Back must return cleanly to MainMenu without creating a false active save
    await page.click('[data-action="OpenCredits"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'CreditsScreen', { timeout: 5000 });
    const credText = await page.locator('#ui-root').innerText();
    expect(credText).toContain('Gerard "Jamie" (Jagofr) Francis');
    expect(credText).toContain('RvL // ROGUE');
    await page.click('#btn-cred-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });
    expect(await page.evaluate(() => window.app.state.hasSavedRun)).toBe(false);

    // EXIT TO SPLASH works & re-enters cleanly
    await page.click('[data-action="QuitToTitle"]');
    await page.waitForSelector('#splash-layer', { timeout: 5000 });
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });

    // Open Options -> Graphics: verify ALL 14 options, AA cycling, dependent disables, & persistence
    await page.click('[data-action="OpenOptions"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu', { timeout: 5000 });
    expect(await page.getAttribute('.opt-tab[data-tab="Graphics"]', 'aria-selected')).toBe('true');
    expect(await page.locator('.opt-row').count()).toBe(14);

    // Cycle Anti-Aliasing Pass (row 7): FXAA -> TSAA -> SMAA -> MSAA -> None -> FXAA -> SMAA
    const clickGfxPlus = async (row) => {
      await page.locator(`.opt-step-btn[data-step-row="${row}"][data-step-dir="1"]`).click();
      await page.waitForTimeout(140);
    };
    const clickGfxMinus = async (row) => {
      await page.locator(`.opt-step-btn[data-step-row="${row}"][data-step-dir="-1"]`).click();
      await page.waitForTimeout(140);
    };

    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('FXAA');
    await clickGfxPlus(7);
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('TSAA');
    await clickGfxPlus(7);
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('SMAA');
    await clickGfxPlus(7);
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('MSAA');
    await clickGfxPlus(7);
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('None');
    // Dependent AA Quality (row 8) must become disabled for None and fixed-4x MSAA!
    expect(await page.locator('.opt-step-btn[data-step-row="8"][data-step-dir="1"]').isDisabled()).toBe(true);
    await clickGfxMinus(7); // None -> MSAA
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('MSAA');
    expect(await page.locator('.opt-step-btn[data-step-row="8"][data-step-dir="1"]').isDisabled()).toBe(true);
    await clickGfxMinus(7); // MSAA -> SMAA
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('SMAA');
    expect(await page.locator('.opt-step-btn[data-step-row="8"][data-step-dir="1"]').isDisabled()).toBe(false);
    await clickGfxPlus(8); // Low -> Medium (2 -> 4)
    expect(await page.evaluate(() => window.app.state.options.gfx.aaLevel)).toBe(4);
    await clickGfxPlus(7); // SMAA -> MSAA
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('MSAA');

    // Cycle Shadow Quality (row 1) -> Off disables Shadow Buffer (row 2), then restore High
    await clickGfxMinus(1); // Normal -> Off
    expect(await page.evaluate(() => window.app.state.options.gfx.shadowLevel)).toBe('Off');
    expect(await page.locator('.opt-step-btn[data-step-row="2"][data-step-dir="1"]').isDisabled()).toBe(true);
    await clickGfxPlus(1); // Off -> Normal
    await clickGfxPlus(1); // Normal -> High
    expect(await page.evaluate(() => window.app.state.options.gfx.shadowLevel)).toBe('High');

    // Cycle Render Scale (row 12): 1.0 -> 2.0
    await clickGfxPlus(12);
    expect(await page.evaluate(() => window.app.state.options.gfx.renderScale)).toBe(2.0);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'pw-options-graphics.png') });

    // Cycle UI Interface Target (row 13): verifies UI window card + font scale shrink/expand independently of 3D canvas
    const measureUi = async () => ({
      uiRes: await page.evaluate(() => window.app.state.options.gfx.uiResolution),
      uiScale: await page.evaluate(() => window.app.uiScale),
      cardBox: await page.locator('.menu-card').boundingBox(),
      h2Box: await page.locator('.menu-header h2').boundingBox(),
      canvasDims: await page.evaluate(() => {
        const c = document.getElementById('screen');
        return { w: c.width, h: c.height, cw: c.clientWidth, ch: c.clientHeight };
      })
    });
    const m720 = await measureUi();
    expect(m720.uiRes).toBe('720p (HD)');
    expect(m720.uiScale).toBeCloseTo(1.0, 2);

    await clickGfxPlus(13); // 1080p (FHD)
    const m1080 = await measureUi();
    expect(m1080.uiRes).toBe('1080p (FHD)');
    expect(m1080.uiScale).toBeCloseTo(0.6667, 2);
    expect(m1080.cardBox.width).toBeLessThan(m720.cardBox.width * 0.72);
    expect(m1080.h2Box.height).toBeLessThan(m720.h2Box.height * 0.78);
    expect(m1080.canvasDims).toEqual(m720.canvasDims);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'pw-ui-scale-1080p.png') });

    await clickGfxPlus(13); // 1440p (2K)
    const m1440 = await measureUi();
    expect(m1440.uiRes).toBe('1440p (2K)');
    expect(m1440.cardBox.width).toBeLessThan(m1080.cardBox.width * 0.85);
    expect(m1440.canvasDims).toEqual(m720.canvasDims);

    await clickGfxPlus(13); // 2160p (4K)
    const m2160 = await measureUi();
    expect(m2160.uiRes).toBe('2160p (4K)');
    expect(m2160.cardBox.width).toBeLessThan(m1440.cardBox.width * 0.92);

    await clickGfxPlus(13); // Native / Match Window -> expands back cleanly to 1.0x
    const mNative = await measureUi();
    expect(mNative.uiRes).toBe('Native / Match Window');
    expect(mNative.cardBox.width).toBeGreaterThan(m2160.cardBox.width * 1.8);

    // Leave at 1080p (FHD) to verify UI scale also persists across reload
    await clickGfxPlus(13); // 720p (HD)
    await clickGfxPlus(13); // 1080p (FHD)
    expect(await page.evaluate(() => window.app.state.options.gfx.uiResolution)).toBe('1080p (FHD)');

    await page.click('#btn-opt-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });

    // Singleplayer Map Select -> Car Select (3 drivetrain archetypes + paint color) -> Sandbox -> Drive -> Pause
    await page.click('[data-action="OpenMapSelect"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MapSelect', { timeout: 5000 });
    await page.click('#card-map-sandbox');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'CarSelect', { timeout: 5000 });
    expect(await page.locator('.car-card').count()).toBe(3);
    expect(await page.locator('#card-car-race_awd').innerText()).toContain('AWD');
    expect(await page.locator('#card-car-hatch_fwd').innerText()).toContain('FWD');
    expect(await page.locator('#card-car-coupe_rwd').innerText()).toContain('RWD');

    // Back from CarSelect returns cleanly to MapSelect, then re-enter & pick Sports Hatch FWD + Cobalt Blue
    await page.click('#btn-car-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MapSelect', { timeout: 5000 });
    await page.click('#card-map-sandbox');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'CarSelect', { timeout: 5000 });
    await page.click('#card-car-hatch_fwd');
    await page.locator('.paint-swatch[data-color-idx="4"]').click();
    await page.waitForFunction(() => window.app?.state?.carSelect?.carId === 'hatch_fwd' && window.app?.state?.carSelect?.colorIdx === 4, { timeout: 4000 });
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'pw-car-select.png') });
    await page.click('#btn-car-launch');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'InGameHUD' && window.app?.currentMapMode === 'Sandbox', { timeout: 8000 });
    expect(await page.evaluate(() => window.app.state.selectedCarId)).toBe('hatch_fwd');

    await page.keyboard.down('KeyW');
    await page.waitForTimeout(700);
    await page.keyboard.up('KeyW');
    expect(await page.evaluate(() => window.app.carPhysics.forwardSpeed)).toBeGreaterThan(0.5);

    await page.click('#btn-hud-pause');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });
    await page.click('[data-action="OpenOptions"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu' && window.app?.state?.isOpenedFromPause === true, { timeout: 5000 });
    expect(await page.locator('.opt-badge-lock').count()).toBeGreaterThanOrEqual(4);
    expect(await page.locator('.opt-step-btn[data-step-row="0"][data-step-dir="1"]').isDisabled()).toBe(true); // Texture Fidelity locked in pause
    await page.click('#btn-opt-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });

    // Main Menu -> Credits -> Back must go to MainMenu (NOT stale PauseMenu!)
    await page.click('[data-action="QuitToTitle"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu' && window.app?.state?.hasSavedRun === true, { timeout: 5000 });
    await page.click('[data-action="OpenCredits"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'CreditsScreen', { timeout: 5000 });
    await page.click('#btn-cred-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });

    // Reload persistence check for Graphics (aaType=MSAA, aaLevel=4, shadowLevel=High, renderScale=2)
    await page.reload();
    for (let i = 0; i < 65; i++) {
      const s = await page.evaluate(() => ({ app: window.app?.appState, ui: window.app?.ui?.currentState, intro: window.app?.introState }));
      if (s.app === 'InGameUI' && s.ui === 'Splash') break;
      if (s.app === 'IntroSequence' && (s.intro === 'Studio' || s.intro === 'Engine')) {
        await page.evaluate(() => { const il = document.getElementById('intro-layer'); if (il) il.click(); });
      }
      await page.waitForTimeout(220);
    }
    await page.waitForSelector('#splash-layer', { timeout: 15000 });
    await page.click('#btn-splash-enter');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });
    await page.click('[data-action="OpenOptions"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu', { timeout: 5000 });
    const persisted = await page.evaluate(() => window.app.state.options.gfx);
    expect(persisted.aaType).toBe('MSAA');
    expect(persisted.aaLevel).toBe(4);
    expect(persisted.renderScale).toBe(2);
    expect(persisted.uiResolution).toBe('1080p (FHD)');
    expect(await page.evaluate(() => window.app.state.selectedCarId)).toBe('hatch_fwd');
    expect(await page.evaluate(() => window.app.uiScale)).toBeCloseTo(0.6667, 2);

    expect(errors).toEqual([]);
  });

  test('3. Audio Sliders, Keyboard/Gamepad Remapping & Nav, Touch Custom Layout & Multiplayer UI', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });

    await bootToMainMenu(page);
    await page.click('[data-action="OpenOptions"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu', { timeout: 5000 });

    // Switch to Audio tab via keyboard 'e' key & adjust Master/Music/SFX
    await page.keyboard.press('KeyE');
    await page.waitForFunction(() => window.app?.state?.options?.tab === 'Audio', { timeout: 4000 });
    const masterBefore = await page.evaluate(() => window.app.state.options.audio.master);
    await page.locator('.opt-step-btn[data-step-row="0"][data-step-dir="-1"]').click();
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.options.audio.master)).toBeLessThan(masterBefore);
    await page.locator('.opt-step-btn[data-step-row="2"][data-step-dir="1"]').click();
    await page.waitForTimeout(140);

    // Switch to Keyboard tab & test Input Mode + Sensitivity + Key Remap + Reset Defaults
    await page.click('.opt-tab[data-tab="Keyboard"]');
    await page.waitForFunction(() => window.app?.state?.options?.tab === 'Keyboard', { timeout: 4000 });
    await page.click('#btn-dev-toggle');
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.options.device)).toBe('KeyboardOnly');
    await page.click('#btn-dev-toggle');
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.options.device)).toBe('Both');

    const sensBefore = await page.evaluate(() => window.app.state.options.steerSens);
    await page.locator('.opt-step-btn[data-sens-dir="-1"]').click();
    await page.waitForTimeout(160);
    const sensAfterDown = await page.evaluate(() => window.app.state.options.steerSens);
    expect(sensAfterDown).toBeLessThan(sensBefore);
    await page.locator('.opt-step-btn[data-sens-dir="1"]').click();
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.options.steerSens)).toBeGreaterThan(sensAfterDown);

    await page.locator('.opt-remap-btn[data-remap-row="0"]').click();
    await page.waitForSelector('.remap-listen-banner', { timeout: 4000 });
    await page.waitForTimeout(200);
    await page.keyboard.press('KeyI');
    await page.waitForFunction(() => window.app?.state?.options?.bindings?.throttle === 'I', { timeout: 5000 });
    await page.locator('[data-remap-row="6"]').click();
    await page.waitForFunction(() => window.app?.state?.options?.bindings?.throttle === 'W', { timeout: 5000 });

    // Switch to Gamepad tab, inject virtual controller, verify nav & button remapping
    await page.evaluate(() => {
      window.__virtualPad = {
        index: 0,
        connected: true,
        id: 'Xbox Mock Gamepad',
        mapping: 'standard',
        axes: [0, 0, 0, 0],
        buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 }))
      };
    });
    await page.keyboard.press('KeyE'); // Keyboard -> Gamepad
    await page.waitForFunction(() => window.app?.state?.options?.tab === 'Gamepad' && window.app?.state?.options?.gamepadConnected === true, { timeout: 5000 });
    await page.locator('.opt-remap-btn[data-remap-row="4"]').click(); // Handbrake (idx 4)
    await page.waitForSelector('.remap-listen-banner', { timeout: 4000 });
    await page.waitForTimeout(220);
    await page.evaluate(() => { window.__virtualPad.buttons[2] = { pressed: true, value: 1 }; }); // X (Left)
    await page.waitForFunction(() => window.app?.state?.options?.bindings?.padHandbrake === 'X (Left)', { timeout: 5000 });
    await page.evaluate(() => { window.__virtualPad.buttons[2] = { pressed: false, value: 0 }; });
    await page.locator('[data-remap-row="6"]').click();
    await page.waitForFunction(() => window.app?.state?.options?.bindings?.padHandbrake === 'B (Right)', { timeout: 5000 });

    // Test real Controller RB (buttons[5]) tab switch Gamepad -> Touch
    await page.evaluate(() => { window.__virtualPad.buttons[5] = { pressed: true, value: 1 }; });
    await page.waitForFunction(() => window.app?.state?.options?.tab === 'Touch', { timeout: 4000 });
    await page.evaluate(() => { window.__virtualPad.buttons[5] = { pressed: false, value: 0 }; window.__virtualPad = null; });

    // Verify Touch tab steppers + preview pad + mode + scale + reset
    expect(await page.locator('.opt-row').count()).toBe(12); // 1 Sensitivity + 11 Touch rows
    await page.locator('.opt-step-btn[data-step-row="0"][data-step-dir="1"]').click(); // Stick X +10px
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.touchSettings.stickOffsetX)).toBe(10);
    expect(await page.evaluate(() => window.app.state.touchSettings.mode)).toBe('Custom');

    await page.locator('.opt-step-btn[data-step-row="10"][data-step-dir="-1"]').click(); // Scale -5%
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.touchSettings.scale)).toBeCloseTo(0.95, 2);

    // Drag GAS node on interactive preview pad
    const gasNode = page.locator('.touch-preview-node[data-touch-part="gas"]');
    const box = await gasNode.boundingBox();
    expect(box).not.toBeNull();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 12, box.y + box.height / 2 - 12);
    await page.mouse.up();
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'pw-options-touch.png') });

    // Multiplayer UI host / leave / back check
    await page.click('#btn-opt-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });
    await page.click('[data-action="OpenMultiplayer"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MultiplayerMenu', { timeout: 5000 });
    await page.click('#btn-mp-host-sandbox');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MultiplayerLobby', { timeout: 5000 });
    await page.click('#btn-mp-leave');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MultiplayerMenu', { timeout: 5000 });
    await page.click('#btn-mp-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });

    expect(errors).toEqual([]);
  });

  test('4. Touch Device Layout, >=44px Coarse Targets & Custom Virtual Controls HUD Transform', async ({ browser }) => {
    const context = await browser.newContext({
      viewport: { width: 844, height: 390 },
      hasTouch: true,
      isMobile: true
    });
    const page = await context.newPage();
    await gotoGame(page);
    await page.waitForSelector('#splash-layer', { timeout: 25000 });
    await page.tap('#btn-splash-enter');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });
    await page.tap('[data-action="OpenOptions"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu', { timeout: 5000 });

    // Coarse-pointer tap target size compliance check (>= 44px)
    const stepBox = await page.locator('.opt-step-btn').first().boundingBox();
    expect(stepBox.width).toBeGreaterThanOrEqual(44);
    expect(stepBox.height).toBeGreaterThanOrEqual(44);

    // Adjust Touch stick offset & reset works cleanly on touch device
    await page.tap('.opt-tab[data-tab="Touch"]');
    await page.waitForFunction(() => window.app?.state?.options?.tab === 'Touch', { timeout: 4000 });
    await page.tap('.opt-step-btn[data-step-row="0"][data-step-dir="1"]');
    await page.waitForTimeout(180);
    await page.tap('#btn-opt-back');
    await page.tap('[data-action="OpenMapSelect"]');
    await page.tap('#card-map-circuit');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'CarSelect', { timeout: 5000 });
    const swatchBox = await page.locator('.paint-swatch').first().boundingBox();
    expect(swatchBox.width).toBeGreaterThanOrEqual(44);
    expect(swatchBox.height).toBeGreaterThanOrEqual(44);
    await page.tap('#card-car-coupe_rwd');
    await page.tap('.paint-swatch[data-color-idx="5"]');
    await page.tap('#btn-car-launch');
    await page.waitForSelector('#touch-layer #touch-stick-zone', { timeout: 8000 });
    const stickStyle = await page.getAttribute('#touch-stick-zone', 'style');
    expect(stickStyle).toContain('translate(10px,0px)');

    // Reset touch defaults restores 0px
    await page.tap('#btn-hud-pause');
    await page.tap('[data-action="OpenOptions"]');
    await page.tap('.opt-tab[data-tab="Touch"]');
    await page.tap('#btn-touch-reset');
    await page.waitForTimeout(160);
    expect(await page.evaluate(() => window.app.state.touchSettings.stickOffsetX)).toBe(0);

    await context.close();
  });
});
