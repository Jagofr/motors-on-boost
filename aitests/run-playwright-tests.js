const http = require('http');
const fs = require('fs');
const path = require('path');

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
  '.css': 'text/css',
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
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found: ' + reqPath);
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      const contentType = MIME_TYPES[ext] || 'application/octet-stream';

      res.writeHead(200, {
        'Content-Type': contentType,
        'Cache-Control': 'no-cache, no-store, must-revalidate'
      });
      fs.createReadStream(filePath).pipe(res);
    });

    server.on('error', reject);
    server.listen(PORT, '127.0.0.1', () => {
      console.log(`[AITests] Node static server listening on http://127.0.0.1:${PORT}`);
      resolve(server);
    });
  });
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`Assertion Failed: ${message}`);
  }
  console.log(`  ✅ PASS: ${message}`);
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
    args: ['--use-gl=angle']
  });

  try {
    const context = await browser.newContext({
      viewport: { width: 1280, height: 720 }
    });
    const page = await context.newPage();

    // =========================================================================
    // TEST 1: Boot Intro Screens Fill the Entire Viewport
    // =========================================================================
    console.log('\n[Scenario 1] Verifying boot intro screens fill the entire viewport...');
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });

    await page.waitForFunction(() => {
      return window.app && window.app.s2d && window.app.studioSplashBmp && window.app.engineSplashBmp;
    }, { timeout: 15000 });

    const studioMetrics = await page.evaluate(() => {
      const app = window.app;
      app.setIntroScreen(window.IntroState.Studio);
      app.introTimer = 1.2;
      app.screenStudio.alpha = 1.0;
      app.layoutIntro();

      const sw = app.s2d.width;
      const sh = app.s2d.height;
      const bmp = app.studioSplashBmp;
      const renderedW = bmp.tile.width * bmp.scaleX;
      const renderedH = bmp.tile.height * bmp.scaleY;
      return { sw, sh, renderedW, renderedH, x: bmp.x, y: bmp.y };
    });

    assert(
      studioMetrics.renderedW >= studioMetrics.sw - 0.5 && studioMetrics.renderedH >= studioMetrics.sh - 0.5,
      `Studio splash fills entire viewport (${studioMetrics.renderedW.toFixed(1)}x${studioMetrics.renderedH.toFixed(1)} covers ${studioMetrics.sw}x${studioMetrics.sh})`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '01-intro-studio-fullscreen.png') });

    const engineMetrics = await page.evaluate(() => {
      const app = window.app;
      app.setIntroScreen(window.IntroState.Engine);
      app.introTimer = 1.2;
      app.screenEngine.alpha = 1.0;
      app.layoutIntro();

      const sw = app.s2d.width;
      const sh = app.s2d.height;
      const bmp = app.engineSplashBmp;
      const renderedW = bmp.tile.width * bmp.scaleX;
      const renderedH = bmp.tile.height * bmp.scaleY;
      return { sw, sh, renderedW, renderedH, x: bmp.x, y: bmp.y };
    });

    assert(
      engineMetrics.renderedW >= engineMetrics.sw - 0.5 && engineMetrics.renderedH >= engineMetrics.sh - 0.5,
      `Engine splash fills entire viewport (${engineMetrics.renderedW.toFixed(1)}x${engineMetrics.renderedH.toFixed(1)} covers ${engineMetrics.sw}x${engineMetrics.sh})`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '02-intro-engine-fullscreen.png') });

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

    assert(
      disclaimerMetrics.visible && disclaimerMetrics.bgW === disclaimerMetrics.sw && disclaimerMetrics.bgH === disclaimerMetrics.sh,
      `Disclaimer screen backplate and frame span full viewport (${disclaimerMetrics.sw}x${disclaimerMetrics.sh})`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '03-intro-disclaimer-framed.png') });

    // =========================================================================
    // TEST 2: Redesigned UI, Play Singleplayer -> Map Selection
    // =========================================================================
    console.log('\n[Scenario 2] Verifying redesigned Splash, Main Menu ("PLAY SINGLEPLAYER"), and Map Selection...');
    await page.evaluate(() => {
      const app = window.app;
      app.finishIntroSequence();
      // Advance update by 1.5s to complete the 1.2s showcase fade-in curtain cleanly
      app.update(1.5);
      app.ui.showSplash();
    });
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '04-title-splash-screen.png') });

    const mainMenuState = await page.evaluate(() => {
      const app = window.app;
      app.ui.showMainMenu();
      return {
        rows: app.ui.builder.mainMenuView.rows.map(r => r.labelTxt.text),
        selectedIndex: app.ui.builder.mainMenuView.selectedIndex
      };
    });

    assert(
      mainMenuState.rows.length === 5 && mainMenuState.rows[0] === 'PLAY SINGLEPLAYER',
      `Main Menu displays "PLAY SINGLEPLAYER" as primary entry (${JSON.stringify(mainMenuState.rows)})`
    );
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '05-main-menu-play-singleplayer.png') });

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

    assert(
      mapSelectState.uiStateName === 'MapSelect' && mapSelectState.maps.length === 2,
      `Confirming "PLAY SINGLEPLAYER" opens Map Selection screen with maps: ${mapSelectState.maps.join(', ')}`
    );
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '06-map-select-highway-circuit.png') });

    await page.evaluate(() => {
      window.app.ui.builder.mapSelectView.navigate(1);
    });
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '07-map-select-sandbox-proving-grounds.png') });

    // =========================================================================
    // TEST 3: Launching & Restarting User-Selected Map (Sandbox & Highway)
    // =========================================================================
    console.log('\n[Scenario 3] Verifying Map Selection launch & Pause Menu "RESTART MAP" preserves user-selected map...');

    const sandboxLaunch = await page.evaluate(() => {
      const app = window.app;
      app.ui.builder.mapSelectView.confirmSelection(); // Launches Sandbox (index 1)
      return {
        mapModeName: app.currentMapMode._hx_name,
        uiStateName: app.ui.currentState._hx_name
      };
    });

    assert(
      sandboxLaunch.mapModeName === 'Sandbox' && sandboxLaunch.uiStateName === 'InGameHUD',
      'Selecting Sandbox Proving Grounds starts singleplayer session on Sandbox map'
    );
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '08-ingame-sandbox-session.png') });

    const sandboxDriven = await page.evaluate(() => {
      const app = window.app;
      app.input.touchThrottle = 1.0;
      app.input.isTouchActive = true;
      for (let i = 0; i < 60; i++) {
        app.input.update(1 / 60);
        app.carPhysics.update(1 / 60, app.input, null, app.sandboxMap);
      }
      app.input.flushInputs();
      app.input.isTouchActive = false;
      const movedX = app.carPhysics.pos.x;
      const movedY = app.carPhysics.pos.y;
      const movedDist = Math.hypot(movedX, movedY);
      app.ui.showPause();
      return {
        movedDist,
        uiStateName: app.ui.currentState._hx_name,
        restartLabel: app.ui.builder.pauseMenuView.rows[1].labelTxt.text
      };
    });

    assert(sandboxDriven.movedDist > 2.0, `Car drove forward in Sandbox (dist = ${sandboxDriven.movedDist.toFixed(2)}m)`);
    assert(sandboxDriven.uiStateName === 'PauseMenu' && sandboxDriven.restartLabel === 'RESTART MAP', 'Pause Menu opened with "RESTART MAP" action');
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '09-pause-menu-in-sandbox.png') });

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

    assert(
      afterSandboxRestart.mapModeName === 'Sandbox' && afterSandboxRestart.uiStateName === 'InGameHUD' && afterSandboxRestart.distFromOrigin < 0.01,
      `Restart in Sandbox kept Sandbox active and reset car to Sandbox origin (dist = ${afterSandboxRestart.distFromOrigin.toFixed(2)}m)`
    );
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '10-sandbox-restarted-at-origin.png') });

    // Now test Highway Circuit selection and restart
    const afterCircuitRestart = await page.evaluate(() => {
      const app = window.app;
      app.ui.showMainMenu();
      app.ui.builder.mainMenuView.selectedIndex = 0; // PLAY SINGLEPLAYER
      app.ui.builder.mainMenuView.confirmSelection();
      app.ui.builder.mapSelectView.selectedIndex = 0; // HIGHWAY CIRCUIT
      app.ui.builder.mapSelectView.confirmSelection();

      app.input.touchThrottle = 1.0;
      app.input.isTouchActive = true;
      for (let i = 0; i < 60; i++) {
        app.input.update(1 / 60);
        app.carPhysics.update(1 / 60, app.input, app.track.waypoints, app.track);
      }
      app.input.flushInputs();
      app.input.isTouchActive = false;
      const movedDist = Math.hypot(app.carPhysics.pos.x, app.carPhysics.pos.y);

      app.ui.showPause();
      app.ui.builder.pauseMenuView.selectedIndex = 1; // RESTART MAP
      app.ui.builder.pauseMenuView.confirmSelection();

      return {
        movedDist,
        mapModeName: app.currentMapMode._hx_name,
        uiStateName: app.ui.currentState._hx_name,
        distFromOrigin: Math.hypot(app.carPhysics.pos.x, app.carPhysics.pos.y)
      };
    });

    assert(
      afterCircuitRestart.movedDist > 2.0 && afterCircuitRestart.mapModeName === 'Circuit' && afterCircuitRestart.uiStateName === 'InGameHUD' && afterCircuitRestart.distFromOrigin < 0.01,
      `Restart in Highway Circuit kept Highway Circuit active and reset car to start line (dist = ${afterCircuitRestart.distFromOrigin.toFixed(2)}m)`
    );
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '11-highway-circuit-restarted.png') });

    // Capture Options and Credits screens
    await page.evaluate(() => window.app.ui.openOptions(false));
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '12-options-modal-styled.png') });

    await page.evaluate(() => window.app.ui.showCredits());
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '13-credits-modal-styled.png') });

    // =========================================================================
    // TEST 4: Physics, Controls Direction (Left/Right), Ground & Traffic Collisions, and Wheel Rim Rendering
    // =========================================================================
    console.log('\n[Scenario 4] Verifying steering direction, ground/traffic collisions, CarMesh alignment, and wheel rim rendering...');

    // 4A. Verify steering right (+1.0) turns car right (+X) and steering left (-1.0) turns car left (-X)
    const steerRightResult = await page.evaluate(() => {
      const app = window.app;
      app.loadMap(window.MapMode.Sandbox);
      app.resetCarToSandboxCenter();
      app.ui.showInGame();

      app.input.touchThrottle = 1.0;
      app.input.touchSteer = 1.0; // Steer Right (D)
      app.input.isTouchActive = true;
      for (let i = 0; i < 45; i++) {
        app.update(1 / 60);
      }
      app.input.flushInputs();
      app.input.isTouchActive = false;
      app.input.touchThrottle = 0.0;
      app.input.touchSteer = 0.0;
      return {
        posX: app.carPhysics.pos.x,
        posY: app.carPhysics.pos.y,
        posZ: app.carPhysics.pos.z,
        yaw: app.carPhysics.yaw
      };
    });

    assert(
      steerRightResult.posX > 0.5 && steerRightResult.posY > 5.0 && steerRightResult.yaw > 0.05,
      `Steering Right (+1.0) turns car to the Right (+X = ${steerRightResult.posX.toFixed(2)}m, +Y = ${steerRightResult.posY.toFixed(2)}m, yaw = ${steerRightResult.yaw.toFixed(2)} rad)`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '14-physics-steer-right.png') });

    const steerLeftResult = await page.evaluate(() => {
      const app = window.app;
      app.resetCarToSandboxCenter();
      app.input.touchThrottle = 1.0;
      app.input.touchSteer = -1.0; // Steer Left (A)
      app.input.isTouchActive = true;
      for (let i = 0; i < 45; i++) {
        app.update(1 / 60);
      }
      app.input.flushInputs();
      app.input.isTouchActive = false;
      app.input.touchThrottle = 0.0;
      app.input.touchSteer = 0.0;
      return {
        posX: app.carPhysics.pos.x,
        posY: app.carPhysics.pos.y,
        posZ: app.carPhysics.pos.z,
        yaw: app.carPhysics.yaw
      };
    });

    assert(
      steerLeftResult.posX < -0.5 && steerLeftResult.posY > 5.0 && steerLeftResult.yaw < -0.05,
      `Steering Left (-1.0) turns car to the Left (-X = ${steerLeftResult.posX.toFixed(2)}m, +Y = ${steerLeftResult.posY.toFixed(2)}m, yaw = ${steerLeftResult.yaw.toFixed(2)} rad)`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '15-physics-steer-left.png') });

    // 4B. Verify Wheel Rim Caps (left wheels show alloy rim on left -X side, right wheels show alloy rim on right +X side)
    const wheelRimCheck = await page.evaluate(() => {
      const app = window.app;
      app.resetCarToSandboxCenter();
      app.update(1 / 60);
      // Pause chase camera updates by entering Pause state with hidden UI so we can inspect side profile
      app.ui.showPause();
      app.ui.visible = false;
      // Position camera on Left side (-X) looking at Left wheels
      app.s3d.camera.pos.x = -3.8;
      app.s3d.camera.pos.y = 0.0;
      app.s3d.camera.pos.z = 0.65;
      app.s3d.camera.target.x = 0.0;
      app.s3d.camera.target.y = 0.0;
      app.s3d.camera.target.z = 0.38;
      const pm = app.playerMesh;
      return {
        bodyY: pm.bodyMesh.y,
        flRimZ: pm.rimCaps[0].z,
        frRimZ: pm.rimCaps[1].z,
        rlRimZ: pm.rimCaps[2].z,
        rrRimZ: pm.rimCaps[3].z
      };
    });

    assert(
      wheelRimCheck.bodyY === 0 && wheelRimCheck.flRimZ < 0 && wheelRimCheck.rlRimZ < 0 && wheelRimCheck.frRimZ > 0 && wheelRimCheck.rrRimZ > 0,
      `CarMesh centered at Y=0 and outer alloy wheel rims aligned (Left Z=${wheelRimCheck.flRimZ.toFixed(2)}, Right Z=${wheelRimCheck.frRimZ.toFixed(2)})`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '16-wheels-left-side-rims.png') });

    await page.evaluate(() => {
      const app = window.app;
      // Position camera on Right side (+X) looking at Right wheels
      app.s3d.camera.pos.x = 3.8;
      app.s3d.camera.pos.y = 0.0;
      app.s3d.camera.pos.z = 0.65;
      app.s3d.camera.target.x = 0.0;
      app.s3d.camera.target.y = 0.0;
      app.s3d.camera.target.z = 0.38;
    });
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '17-wheels-right-side-rims.png') });

    // 4C. Verify Traffic Collision & Ground Contact on Highway Circuit
    const trafficCollisionCheck = await page.evaluate(() => {
      const app = window.app;
      app.ui.visible = true;
      app.ui.showMainMenu();
      app.ui.builder.mainMenuView.selectedIndex = 0; // PLAY SINGLEPLAYER
      app.ui.builder.mainMenuView.confirmSelection();
      app.ui.builder.mapSelectView.selectedIndex = 0; // HIGHWAY CIRCUIT
      app.ui.builder.mapSelectView.confirmSelection();
      app.resetCarToStartLine();

      // Place traffic vehicle #0 directly in front of player at (0, 2.2, 0.06)
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
      // Move traffic car clear after the initial impact so we can verify OimoPhysics retains the post-impact velocity on the next frame!
      tc.pos.y = 50.0;
      app.update(1 / 60);

      return {
        speedAfterHit,
        speedNextFrame: app.carPhysics.forwardSpeed,
        groundZ: app.carPhysics.pos.z,
        wheelsGrounded: app.carPhysics.wheelOnGround.every(Boolean)
      };
    });

    assert(
      trafficCollisionCheck.speedAfterHit < 28.0 && Math.abs(trafficCollisionCheck.speedAfterHit - trafficCollisionCheck.speedNextFrame) < 1.5 && trafficCollisionCheck.wheelsGrounded,
      `Traffic collision and ground suspension contact synced with OimoPhysics (speedAfterHit=${trafficCollisionCheck.speedAfterHit.toFixed(1)} m/s, speedNextFrame=${trafficCollisionCheck.speedNextFrame.toFixed(1)} m/s, grounded=${trafficCollisionCheck.wheelsGrounded})`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '18-traffic-and-ground-collision.png') });

    // 4D. Verify Highway Circuit Track Free Navigation (Zero invisible walls at Y=195 / X=195, and no terrain tunneling)
    const circuitNavigationCheck = await page.evaluate(() => {
      const app = window.app;
      app.loadMap(window.MapMode.Circuit);
      app.resetCarToStartLine();

      // Test driving through the sector that passes through Y=195 (where Sandbox wall used to block the road)
      app.carPhysics.pos.x = 45.0;
      app.carPhysics.pos.y = 185.0;
      app.carPhysics.pos.z = 2.0;
      app.carPhysics.yaw = 0.70; // heading northeast towards (90, 240)
      app.carPhysics.forwardSpeed = 35.0; // 126 km/h
      app.carPhysics.syncToOimoBody();

      // Step physics forward 40 frames (~0.66s), traversing from Y=185 to Y > 205 (crossing Y=195)
      for (let i = 0; i < 40; i++) {
        app.update(1 / 60);
      }

      const passedY195 = app.carPhysics.pos.y > 200.0;
      const speedMaintained = app.carPhysics.forwardSpeed > 30.0;
      const notFallenThrough = app.carPhysics.pos.z > 0.0;

      return {
        posX: app.carPhysics.pos.x,
        posY: app.carPhysics.pos.y,
        posZ: app.carPhysics.pos.z,
        speed: app.carPhysics.forwardSpeed,
        passedY195,
        speedMaintained,
        notFallenThrough
      };
    });

    assert(
      circuitNavigationCheck.passedY195 && circuitNavigationCheck.speedMaintained && circuitNavigationCheck.notFallenThrough,
      `Highway Circuit track navigated past Y=195 at full speed with ZERO invisible wall collisions (Y=${circuitNavigationCheck.posY.toFixed(1)}m, Z=${circuitNavigationCheck.posZ.toFixed(2)}m, speed=${circuitNavigationCheck.speed.toFixed(1)} m/s)`
    );
    await page.waitForTimeout(150);
    await page.screenshot({ path: path.join(SCREENSHOT_DIR, '19-circuit-y195-wall-free-navigation.png') });

    console.log(`\n🎉 ALL PLAYWRIGHT TESTS PASSED! 19 screenshot artifacts saved to: ${SCREENSHOT_DIR}`);
  } finally {
    await browser.close();
    if (server) server.close();
  }
}

runTests().catch((err) => {
  console.error('\n❌ PLAYWRIGHT TEST FAILURE:', err);
  process.exit(1);
});
