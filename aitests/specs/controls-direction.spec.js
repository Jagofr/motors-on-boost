const { test, expect } = require('@playwright/test');

async function triggerBtn(locator, useTap) {
  if (useTap) {
    await locator.tap();
  } else {
    await locator.click();
  }
}

async function installGamepadMock(page) {
  await page.addInitScript(() => {
    window.__mockPad = null;
    navigator.getGamepads = () => {
      const m = window.__mockPad;
      if (!m || !m.connected) return [null, null, null, null];
      const buttons = [];
      for (let i = 0; i < 17; i++) {
        let pressed = false;
        let value = 0;
        if (i === 7 && m.rt) {
          pressed = m.rt > 0.1;
          value = m.rt;
        } else if (i === 14 && m.dpadLeft) {
          pressed = true;
          value = 1;
        } else if (i === 15 && m.dpadRight) {
          pressed = true;
          value = 1;
        }
        buttons.push({ pressed, touched: pressed, value });
      }
      return [{
        id: 'Playwright Mock Xbox Controller',
        index: 0,
        connected: true,
        mapping: 'standard',
        axes: m.axes || [0, 0, 0, 0],
        buttons,
        timestamp: performance.now()
      }, null, null, null];
    };
  });
}

async function bootSandbox(page, useTap = false) {
  await page.goto('/');
  for (let i = 0; i < 65; i++) {
    const s = await page.evaluate(() => ({
      app: window.app?.appState,
      intro: window.app?.introState,
      ui: window.app?.ui?.currentState
    }));
    if (s.app === 'InGameUI' && s.ui === 'Splash') break;
    if (s.app === 'IntroSequence' && (s.intro === 'Studio' || s.intro === 'Engine')) {
      await page.evaluate(() => { const il = document.getElementById('intro-layer'); if (il) il.click(); });
    }
    await page.waitForTimeout(220);
  }
  await page.waitForSelector('#splash-layer', { timeout: 15000 });
  await triggerBtn(page.locator('#btn-splash-enter'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'MainMenu', { timeout: 5000 });
  await triggerBtn(page.locator('[data-action="OpenMapSelect"]'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'MapSelect', { timeout: 5000 });
  await triggerBtn(page.locator('#card-map-sandbox'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'CarSelect', { timeout: 5000 });
  await triggerBtn(page.locator('#btn-car-launch'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'InGameHUD' && window.app?.currentMapMode === 'Sandbox', { timeout: 10000 });
  await page.waitForTimeout(450);
}

async function restartSandbox(page, useTap = false) {
  await triggerBtn(page.locator('#btn-hud-pause'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });
  await triggerBtn(page.locator('[data-action="RestartRace"]'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'InGameHUD', { timeout: 5000 });
  await page.waitForFunction(() => {
    const p = window.app?.carPhysics?.pos;
    return p && Math.abs(p.x) < 0.2 && Math.abs(p.y) < 0.2;
  }, { timeout: 5000 });
  await page.waitForTimeout(150);
}

test.describe('Core Controls Anti-Inversion Contract (All Input Methods)', () => {
  test.setTimeout(90000);

  test('Desktop: Keyboard (WASD + Arrows), Gamepad Analog Stick, and Gamepad D-Pad never invert Left/Right', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));
    await installGamepadMock(page);
    await bootSandbox(page, false);

    // 1. Keyboard WASD: W + A => Left (-X), W + D => Right (+X)
    await page.keyboard.down('KeyW');
    await page.keyboard.down('KeyA');
    await page.waitForTimeout(1050);
    const wasdLeft = await page.evaluate(() => window.app.carPhysics.pos);
    await page.keyboard.up('KeyA');
    await page.keyboard.up('KeyW');
    console.log('[Anti-Inversion WASD Left]', wasdLeft);
    expect(wasdLeft.y).toBeGreaterThan(2.0);
    expect(wasdLeft.x).toBeLessThan(-1.0);

    await restartSandbox(page, false);
    await page.keyboard.down('KeyW');
    await page.keyboard.down('KeyD');
    await page.waitForTimeout(1050);
    const wasdRight = await page.evaluate(() => window.app.carPhysics.pos);
    await page.keyboard.up('KeyD');
    await page.keyboard.up('KeyW');
    console.log('[Anti-Inversion WASD Right]', wasdRight);
    expect(wasdRight.y).toBeGreaterThan(2.0);
    expect(wasdRight.x).toBeGreaterThan(1.0);

    // 2. Keyboard Arrow Keys: ArrowUp + ArrowLeft => Left (-X), ArrowUp + ArrowRight => Right (+X)
    await restartSandbox(page, false);
    await page.keyboard.down('ArrowUp');
    await page.keyboard.down('ArrowLeft');
    await page.waitForTimeout(1050);
    const arrowLeft = await page.evaluate(() => window.app.carPhysics.pos);
    await page.keyboard.up('ArrowLeft');
    await page.keyboard.up('ArrowUp');
    console.log('[Anti-Inversion Arrow Left]', arrowLeft);
    expect(arrowLeft.y).toBeGreaterThan(2.0);
    expect(arrowLeft.x).toBeLessThan(-1.0);

    await restartSandbox(page, false);
    await page.keyboard.down('ArrowUp');
    await page.keyboard.down('ArrowRight');
    await page.waitForTimeout(1050);
    const arrowRight = await page.evaluate(() => window.app.carPhysics.pos);
    await page.keyboard.up('ArrowRight');
    await page.keyboard.up('ArrowUp');
    console.log('[Anti-Inversion Arrow Right]', arrowRight);
    expect(arrowRight.y).toBeGreaterThan(2.0);
    expect(arrowRight.x).toBeGreaterThan(1.0);

    // 3. Gamepad Analog Stick + RT: axes[0] < 0 => Left (-X), axes[0] > 0 => Right (+X)
    await restartSandbox(page, false);
    await page.evaluate(() => { window.__mockPad = { connected: true, axes: [-0.85, 0, 0, 0], rt: 1.0 }; });
    await page.waitForTimeout(1050);
    const padAnalogLeft = await page.evaluate(() => window.app.carPhysics.pos);
    await page.evaluate(() => { window.__mockPad = { connected: true, axes: [0, 0, 0, 0], rt: 0 }; });
    console.log('[Anti-Inversion Gamepad Analog Left]', padAnalogLeft);
    expect(padAnalogLeft.y).toBeGreaterThan(2.0);
    expect(padAnalogLeft.x).toBeLessThan(-1.0);

    await restartSandbox(page, false);
    await page.evaluate(() => { window.__mockPad = { connected: true, axes: [0.85, 0, 0, 0], rt: 1.0 }; });
    await page.waitForTimeout(1050);
    const padAnalogRight = await page.evaluate(() => window.app.carPhysics.pos);
    await page.evaluate(() => { window.__mockPad = { connected: true, axes: [0, 0, 0, 0], rt: 0 }; });
    console.log('[Anti-Inversion Gamepad Analog Right]', padAnalogRight);
    expect(padAnalogRight.y).toBeGreaterThan(2.0);
    expect(padAnalogRight.x).toBeGreaterThan(1.0);

    // 4. Gamepad D-Pad + RT: buttons[14] => Left (-X), buttons[15] => Right (+X)
    await restartSandbox(page, false);
    await page.evaluate(() => { window.__mockPad = { connected: true, axes: [0, 0, 0, 0], dpadLeft: true, rt: 1.0 }; });
    await page.waitForTimeout(1050);
    const padDpadLeft = await page.evaluate(() => window.app.carPhysics.pos);
    await page.evaluate(() => { window.__mockPad = null; });
    console.log('[Anti-Inversion Gamepad D-Pad Left]', padDpadLeft);
    expect(padDpadLeft.y).toBeGreaterThan(2.0);
    expect(padDpadLeft.x).toBeLessThan(-1.0);

    await restartSandbox(page, false);
    await page.evaluate(() => { window.__mockPad = { connected: true, axes: [0, 0, 0, 0], dpadRight: true, rt: 1.0 }; });
    await page.waitForTimeout(1050);
    const padDpadRight = await page.evaluate(() => window.app.carPhysics.pos);
    await page.evaluate(() => { window.__mockPad = null; });
    console.log('[Anti-Inversion Gamepad D-Pad Right]', padDpadRight);
    expect(padDpadRight.y).toBeGreaterThan(2.0);
    expect(padDpadRight.x).toBeGreaterThan(1.0);

    expect(errors).toEqual([]);
  });

  test('Mobile Virtual Analog Stick: Partial & Full Analog Deflection, Visual Knob Movement, and Multi-Touch Gas never invert Left/Right', async ({ browser }) => {
    const context = await browser.newContext({
      viewport: { width: 844, height: 390 },
      hasTouch: true,
      isMobile: true
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(e.message));

    await bootSandbox(page, true);
    await page.waitForSelector('#touch-stick-zone', { state: 'visible', timeout: 5000 });
    await page.waitForSelector('#touch-stick-knob', { state: 'visible', timeout: 5000 });
    await page.waitForSelector('#touch-btn-gas', { state: 'visible', timeout: 5000 });

    const cdp = await context.newCDPSession(page);

    async function driveVirtualAnalogStick(fracX) {
      const pts = await page.evaluate((fx) => {
        const stick = document.getElementById('touch-stick-zone');
        const gas = document.getElementById('touch-btn-gas');
        const sRect = stick.getBoundingClientRect();
        const gRect = gas.getBoundingClientRect();
        const maxR = Math.max(24, sRect.width * 0.38);
        return {
          sx: sRect.left + sRect.width / 2,
          sy: sRect.top + sRect.height / 2,
          tx: sRect.left + sRect.width / 2 + fx * maxR,
          gx: gRect.left + gRect.width / 2,
          gy: gRect.top + gRect.height / 2
        };
      }, fracX);

      // Multi-touch finger 1 on Gas pedal + finger 2 on Virtual Analog Stick
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchStart',
        touchPoints: [
          { x: pts.gx, y: pts.gy, id: 1 },
          { x: pts.sx, y: pts.sy, id: 2 }
        ]
      });
      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [
          { x: pts.gx, y: pts.gy, id: 1 },
          { x: pts.tx, y: pts.sy, id: 2 }
        ]
      });

      const knobWhileHeld = await page.evaluate(() => {
        const knob = document.getElementById('touch-stick-knob');
        const tf = knob ? knob.style.transform : '';
        const m = tf.match(/translateX\((-?[\d.]+)px\)/);
        return m ? parseFloat(m[1]) : 0;
      });

      await page.waitForTimeout(1050);
      const knobAtEnd = await page.evaluate(() => {
        const knob = document.getElementById('touch-stick-knob');
        const tf = knob ? knob.style.transform : '';
        const m = tf.match(/translateX\((-?[\d.]+)px\)/);
        return m ? parseFloat(m[1]) : 0;
      });
      const pos = await page.evaluate(() => window.app.carPhysics.pos);

      await cdp.send('Input.dispatchTouchEvent', {
        type: 'touchEnd',
        touchPoints: []
      });

      const knobAfterRelease = await page.evaluate(() => {
        const knob = document.getElementById('touch-stick-knob');
        const tf = knob ? knob.style.transform : '';
        const m = tf.match(/translateX\((-?[\d.]+)px\)/);
        return m ? parseFloat(m[1]) : NaN;
      });

      return { pos, knobWhileHeld, knobAtEnd, knobAfterRelease };
    }

    // 1. Partial Virtual Analog Stick Left (-45%)
    const touchPartialLeft = await driveVirtualAnalogStick(-0.45);
    console.log('[Anti-Inversion Virtual Stick Partial Left -45%]', touchPartialLeft);
    expect(touchPartialLeft.knobWhileHeld).toBeLessThan(-5);
    expect(touchPartialLeft.knobAtEnd).toBeLessThan(-5);
    expect(touchPartialLeft.knobAfterRelease).toBe(0);
    expect(touchPartialLeft.pos.y).toBeGreaterThan(2.0);
    expect(touchPartialLeft.pos.x).toBeLessThan(-0.35);

    // 2. Partial Virtual Analog Stick Right (+45%)
    await restartSandbox(page, true);
    const touchPartialRight = await driveVirtualAnalogStick(0.45);
    console.log('[Anti-Inversion Virtual Stick Partial Right +45%]', touchPartialRight);
    expect(touchPartialRight.knobWhileHeld).toBeGreaterThan(5);
    expect(touchPartialRight.knobAtEnd).toBeGreaterThan(5);
    expect(touchPartialRight.knobAfterRelease).toBe(0);
    expect(touchPartialRight.pos.y).toBeGreaterThan(2.0);
    expect(touchPartialRight.pos.x).toBeGreaterThan(0.35);

    // 3. Full Virtual Analog Stick Left (-100%) > Partial Left turn magnitude
    await restartSandbox(page, true);
    const touchFullLeft = await driveVirtualAnalogStick(-1.0);
    console.log('[Anti-Inversion Virtual Stick Full Left -100%]', touchFullLeft);
    expect(touchFullLeft.knobWhileHeld).toBeLessThan(touchPartialLeft.knobWhileHeld);
    expect(touchFullLeft.knobAtEnd).toBeLessThan(touchPartialLeft.knobWhileHeld);
    expect(touchFullLeft.pos.y).toBeGreaterThan(2.0);
    expect(touchFullLeft.pos.x).toBeLessThan(-1.2);
    expect(Math.abs(touchFullLeft.pos.x)).toBeGreaterThan(Math.abs(touchPartialLeft.pos.x));

    // 4. Full Virtual Analog Stick Right (+100%) > Partial Right turn magnitude
    await restartSandbox(page, true);
    const touchFullRight = await driveVirtualAnalogStick(1.0);
    console.log('[Anti-Inversion Virtual Stick Full Right +100%]', touchFullRight);
    expect(touchFullRight.knobWhileHeld).toBeGreaterThan(touchPartialRight.knobWhileHeld);
    expect(touchFullRight.knobAtEnd).toBeGreaterThan(touchPartialRight.knobWhileHeld);
    expect(touchFullRight.pos.y).toBeGreaterThan(2.0);
    expect(touchFullRight.pos.x).toBeGreaterThan(1.2);
    expect(Math.abs(touchFullRight.pos.x)).toBeGreaterThan(Math.abs(touchPartialRight.pos.x));

    // 5. Continuous Left -> Right thumb slide WITHOUT lifting must reverse angular turn & keep knob intact
    await restartSandbox(page, true);
    const slidePts = await page.evaluate(() => {
      const stick = document.getElementById('touch-stick-zone').getBoundingClientRect();
      const gas = document.getElementById('touch-btn-gas').getBoundingClientRect();
      const maxR = Math.max(24, stick.width * 0.38);
      return {
        sx: stick.left + stick.width / 2,
        sy: stick.top + stick.height / 2,
        txL: stick.left + stick.width / 2 - maxR,
        txR: stick.left + stick.width / 2 + maxR,
        gx: gas.left + gas.width / 2,
        gy: gas.top + gas.height / 2
      };
    });
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [{ x: slidePts.gx, y: slidePts.gy, id: 1 }, { x: slidePts.sx, y: slidePts.sy, id: 2 }]
    });
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [{ x: slidePts.gx, y: slidePts.gy, id: 1 }, { x: slidePts.txL, y: slidePts.sy, id: 2 }]
    });
    await page.waitForTimeout(700);
    const yawMidLeft = await page.evaluate(() => window.app.carPhysics.yaw);
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [{ x: slidePts.gx, y: slidePts.gy, id: 1 }, { x: slidePts.txR, y: slidePts.sy, id: 2 }]
    });
    await page.waitForTimeout(2000);
    const slideEnd = await page.evaluate(() => {
      const knob = document.getElementById('touch-stick-knob');
      const m = (knob ? knob.style.transform : '').match(/translateX\((-?[\d.]+)px\)/);
      return { yaw: window.app.carPhysics.yaw, knobX: m ? parseFloat(m[1]) : 0 };
    });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    console.log('[Anti-Inversion Virtual Stick Continuous Slide L->R]', { yawMidLeft, slideEnd });
    expect(yawMidLeft).toBeLessThan(-0.15);
    expect(slideEnd.yaw).toBeGreaterThan(0.05);
    expect(slideEnd.knobX).toBeGreaterThan(15);

    expect(errors).toEqual([]);
    await context.close();
  });
});
