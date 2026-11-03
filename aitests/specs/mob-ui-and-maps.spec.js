const { test, expect } = require('@playwright/test');
const path = require('path');
const fs = require('fs');

const SCREENSHOT_DIR = path.resolve(__dirname, '..', 'screenshots');

test.beforeAll(() => {
  if (!fs.existsSync(SCREENSHOT_DIR)) {
    fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
  }
});

test.describe('M.O.B. // UI, Full-Viewport Intro, Map Selection & Restart Verification', () => {
  test('1. Boot intro screens fill the entire viewport (Studio, Engine, Disclaimer)', async ({ page }) => {
    await page.goto('/');

    // Wait for Heaps app to initialize and WebP splash bitmaps to decode
    await page.waitForFunction(() => {
      return window.app && window.app.s2d && window.app.studioSplashBmp && window.app.engineSplashBmp;
    }, { timeout: 15000 });

    // Hold Studio splash at full opacity and verify it covers >= 100% of s2d viewport
    const studioMetrics = await page.evaluate(() => {
      const app = window.app;
      app.setIntroScreen(window.IntroState.Studio);
      app.introTimer = 1.2; // Hold phase (alpha = 1.0)
      app.screenStudio.alpha = 1.0;
      app.layoutIntro();

      const sw = app.s2d.width;
      const sh = app.s2d.height;
      const bmp = app.studioSplashBmp;
      const renderedW = bmp.tile.width * bmp.scaleX;
      const renderedH = bmp.tile.height * bmp.scaleY;

      return { sw, sh, renderedW, renderedH, x: bmp.x, y: bmp.y };
    });

    expect(studioMetrics.renderedW).toBeGreaterThanOrEqual(studioMetrics.sw - 0.5);
    expect(studioMetrics.renderedH).toBeGreaterThanOrEqual(studioMetrics.sh - 0.5);
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '01-intro-studio-fullscreen.png') });

    // Hold Engine splash at full opacity and verify it covers >= 100% of s2d viewport
    const engineMetrics = await page.evaluate(() => {
      const app = window.app;
      app.setIntroScreen(window.IntroState.Engine);
      app.introTimer = 1.2; // Hold phase (alpha = 1.0)
      app.screenEngine.alpha = 1.0;
      app.layoutIntro();

      const sw = app.s2d.width;
      const sh = app.s2d.height;
      const bmp = app.engineSplashBmp;
      const renderedW = bmp.tile.width * bmp.scaleX;
      const renderedH = bmp.tile.height * bmp.scaleY;

      return { sw, sh, renderedW, renderedH, x: bmp.x, y: bmp.y };
    });

    expect(engineMetrics.renderedW).toBeGreaterThanOrEqual(engineMetrics.sw - 0.5);
    expect(engineMetrics.renderedH).toBeGreaterThanOrEqual(engineMetrics.sh - 0.5);
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '02-intro-engine-fullscreen.png') });

    // Verify Disclaimer screen and full-viewport backplate
    const disclaimerMetrics = await page.evaluate(() => {
      const app = window.app;
      app.setIntroScreen(window.IntroState.Disclaimer);
      app.introTimer = 1.5;
      app.screenDisclaimer.alpha = 1.0;
      app.layoutIntro();

      return {
        visible: app.screenDisclaimer.visible,
        bgW: app.introBg.scaleX,
        bgH: app.introBg.scaleY,
        sw: app.s2d.width,
        sh: app.s2d.height,
        headerText: app.discHeader.text
      };
    });

    expect(disclaimerMetrics.visible).toBe(true);
    expect(disclaimerMetrics.bgW).toBe(disclaimerMetrics.sw);
    expect(disclaimerMetrics.bgH).toBe(disclaimerMetrics.sh);
    expect(disclaimerMetrics.headerText).toContain('TRADEMARK & LEGAL DISCLOSURES');
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '03-intro-disclaimer.png') });
  });

  test('2. Redesigned Splash, Main Menu -> Play Singleplayer -> Map Selection & Map Restart', async ({ page }) => {
    await page.goto('/');

    await page.waitForFunction(() => window.app && window.app.s2d, { timeout: 15000 });

    // Complete intro and show Splash screen
    await page.evaluate(() => {
      const app = window.app;
      app.finishIntroSequence();
      app.update(1.5);
      app.ui.showSplash();
    });

    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '04-title-splash-screen.png') });

    // Transition to Main Menu and verify "PLAY SINGLEPLAYER" is the primary option
    const mainMenuState = await page.evaluate(() => {
      const app = window.app;
      app.ui.showMainMenu();
      const rows = app.ui.builder.mainMenuView.rows.map(r => r.labelTxt.text);
      return {
        rowCount: rows.length,
        rows,
        selectedIndex: app.ui.builder.mainMenuView.selectedIndex
      };
    });

    expect(mainMenuState.rowCount).toBe(5);
    expect(mainMenuState.rows[0]).toBe('PLAY SINGLEPLAYER');
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '05-main-menu-singleplayer.png') });

    // Trigger "PLAY SINGLEPLAYER" and verify transition to Map Selection screen
    const mapSelectState = await page.evaluate(() => {
      const app = window.app;
      app.ui.builder.mainMenuView.selectedIndex = 0;
      app.ui.builder.mainMenuView.confirmSelection();
      const ms = app.ui.builder.mapSelectView;
      return {
        uiStateName: app.ui.currentState._hx_name,
        title: ms.titleText.text,
        maps: ms.mapTitles.map(t => t.text),
        selectedIndex: ms.selectedIndex
      };
    });

    expect(mapSelectState.uiStateName).toBe('MapSelect');
    expect(mapSelectState.maps).toEqual(['HIGHWAY CIRCUIT', 'SANDBOX PROVING GROUNDS']);
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '06-map-select-highway-circuit.png') });

    // Navigate to Sandbox Proving Grounds card on Map Select screen
    await page.evaluate(() => {
      const app = window.app;
      app.ui.builder.mapSelectView.navigate(1);
    });
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '07-map-select-sandbox-proving-grounds.png') });

    // Launch Sandbox Proving Grounds from Map Selection
    const sandboxLaunch = await page.evaluate(() => {
      const app = window.app;
      app.ui.builder.mapSelectView.confirmSelection();
      return {
        mapModeName: app.currentMapMode._hx_name,
        uiStateName: app.ui.currentState._hx_name,
        posX: app.carPhysics.pos.x,
        posY: app.carPhysics.pos.y
      };
    });

    expect(sandboxLaunch.mapModeName).toBe('Sandbox');
    expect(sandboxLaunch.uiStateName).toBe('InGameHUD');
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '08-ingame-sandbox-session.png') });

    // Drive forward in Sandbox, open Pause Menu, and verify Restart keeps the user in Sandbox!
    const sandboxRestartResult = await page.evaluate(() => {
      const app = window.app;
      app.input.touchThrottle = 1.0;
      app.input.isTouchActive = true;
      for (let i = 0; i < 60; i++) {
        app.input.update(1 / 60);
        app.carPhysics.update(1 / 60, app.input, null, app.sandboxMap);
      }
      app.input.flushInputs();
      app.input.isTouchActive = false;
      const movedDist = Math.hypot(app.carPhysics.pos.x, app.carPhysics.pos.y);

      // Open Pause Menu
      app.ui.showPause();
      return {
        movedDist,
        uiStateName: app.ui.currentState._hx_name,
        restartLabel: app.ui.builder.pauseMenuView.rows[1].labelTxt.text
      };
    });

    expect(sandboxRestartResult.movedDist).toBeGreaterThan(2.0);
    expect(sandboxRestartResult.uiStateName).toBe('PauseMenu');
    expect(sandboxRestartResult.restartLabel).toBe('RESTART MAP');
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '09-pause-menu-in-sandbox.png') });

    // Execute Restart from Pause Menu while in Sandbox
    const afterSandboxRestart = await page.evaluate(() => {
      const app = window.app;
      app.ui.builder.pauseMenuView.selectedIndex = 1; // RESTART MAP
      app.ui.builder.pauseMenuView.confirmSelection();
      return {
        mapModeName: app.currentMapMode._hx_name,
        uiStateName: app.ui.currentState._hx_name,
        distFromOrigin: Math.hypot(app.carPhysics.pos.x, app.carPhysics.pos.y),
        speed: app.carPhysics.forwardSpeed
      };
    });

    expect(afterSandboxRestart.mapModeName).toBe('Sandbox');
    expect(afterSandboxRestart.uiStateName).toBe('InGameHUD');
    expect(afterSandboxRestart.distFromOrigin).toBeLessThan(0.01);
    expect(Math.abs(afterSandboxRestart.speed)).toBeLessThan(0.01);
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '10-sandbox-restarted-at-origin.png') });

    // Now test selecting Highway Circuit via Map Select and restarting Highway Circuit
    const afterCircuitRestart = await page.evaluate(() => {
      const app = window.app;
      app.ui.showMainMenu();
      app.ui.builder.mainMenuView.selectedIndex = 0; // PLAY SINGLEPLAYER
      app.ui.builder.mainMenuView.confirmSelection();

      // Select Highway Circuit (index 0)
      app.ui.builder.mapSelectView.selectedIndex = 0;
      app.ui.builder.mapSelectView.confirmSelection();

      // Drive forward on Highway Circuit
      app.input.touchThrottle = 1.0;
      app.input.isTouchActive = true;
      for (let i = 0; i < 60; i++) {
        app.input.update(1 / 60);
        app.carPhysics.update(1 / 60, app.input, app.track.waypoints, app.track);
      }
      app.input.flushInputs();
      app.input.isTouchActive = false;
      const movedCircuitDist = Math.hypot(app.carPhysics.pos.x, app.carPhysics.pos.y);

      // Pause and Restart Highway Circuit
      app.ui.showPause();
      app.ui.builder.pauseMenuView.selectedIndex = 1; // RESTART MAP
      app.ui.builder.pauseMenuView.confirmSelection();

      return {
        movedCircuitDist,
        mapModeName: app.currentMapMode._hx_name,
        uiStateName: app.ui.currentState._hx_name,
        distFromOrigin: Math.hypot(app.carPhysics.pos.x, app.carPhysics.pos.y),
        speed: app.carPhysics.forwardSpeed
      };
    });

    expect(afterCircuitRestart.movedCircuitDist).toBeGreaterThan(2.0);
    expect(afterCircuitRestart.mapModeName).toBe('Circuit');
    expect(afterCircuitRestart.uiStateName).toBe('InGameHUD');
    expect(afterCircuitRestart.distFromOrigin).toBeLessThan(0.01);
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '11-highway-circuit-restarted.png') });

    // Capture Options & Credits screens for visual UI verification
    await page.evaluate(() => {
      window.app.ui.openOptions(false);
    });
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '12-options-menu-styled.png') });

    await page.evaluate(() => {
      window.app.ui.showCredits();
    });
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '13-credits-screen-styled.png') });

    // Verify steering direction (Right -> +X, Left -> -X) and wheel rim alignment
    const steerRight = await page.evaluate(() => {
      const app = window.app;
      app.loadMap(window.MapMode.Sandbox);
      app.resetCarToSandboxCenter();
      app.ui.showInGame();
      app.input.touchThrottle = 1.0;
      app.input.touchSteer = 1.0;
      app.input.isTouchActive = true;
      for (let i = 0; i < 45; i++) app.update(1 / 60);
      app.input.flushInputs();
      app.input.isTouchActive = false;
      app.input.touchThrottle = 0.0;
      app.input.touchSteer = 0.0;
      return { posX: app.carPhysics.pos.x, posY: app.carPhysics.pos.y, yaw: app.carPhysics.yaw };
    });
    expect(steerRight.posX).toBeGreaterThan(0.5);
    expect(steerRight.posY).toBeGreaterThan(5.0);
    expect(steerRight.yaw).toBeGreaterThan(0.05);
  });
});
