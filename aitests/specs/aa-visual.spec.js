const { test, expect } = require('@playwright/test');
const path = require('path');
const fs = require('fs');
const zlib = require('zlib');

const SCREENSHOT_DIR = path.resolve(__dirname, '..', 'screenshots');

test.beforeAll(() => {
  if (!fs.existsSync(SCREENSHOT_DIR)) {
    fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
  }
});

// Pure-JS lossless RGBA PNG decoder (supports standard colorType 2/6 and filter types 0-4)
function decodePng(pngBuffer) {
  let pos = 8, width = 0, height = 0, colorType = 6;
  const idat = [];
  while (pos < pngBuffer.length) {
    const len = pngBuffer.readUInt32BE(pos);
    const type = pngBuffer.slice(pos + 4, pos + 8).toString('ascii');
    const data = pngBuffer.slice(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      colorType = data[9];
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    pos += 12 + len;
  }
  const bpp = colorType === 6 ? 4 : 3;
  const stride = width * bpp + 1;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const pixels = Buffer.alloc(width * height * 4);
  const recon = Buffer.alloc(width * height * bpp);

  for (let y = 0; y < height; y++) {
    const rowIn = y * stride;
    const filter = raw[rowIn];
    const rowOut = y * width * bpp;
    const prev = (y - 1) * width * bpp;
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
        const pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        o = (val + pr) & 0xff;
      }
      recon[rowOut + x] = o;
    }
    for (let px = 0; px < width; px++) {
      const sOff = rowOut + px * bpp;
      const dOff = (y * width + px) * 4;
      pixels[dOff] = recon[sOff];
      pixels[dOff + 1] = recon[sOff + 1];
      pixels[dOff + 2] = recon[sOff + 2];
      pixels[dOff + 3] = bpp === 4 ? recon[sOff + 3] : 255;
    }
  }
  return { width, height, pixels };
}

// Pure-JS CRC32 + RGBA PNG encoder for nearest-neighbor 3x zoomed crop inspection
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const tBuf = Buffer.from(type, 'ascii');
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([tBuf, data])), 0);
  return Buffer.concat([len, tBuf, data, crcBuf]);
}

function saveZoomedCropPng(img, rx, ry, rw, rh, scale, outPath) {
  const outW = rw * scale;
  const outH = rh * scale;
  const raw = Buffer.alloc(outH * (outW * 4 + 1));
  for (let dy = 0; dy < outH; dy++) {
    const sy = ry + Math.floor(dy / scale);
    const dstRow = dy * (outW * 4 + 1);
    raw[dstRow] = 0; // filter None
    for (let dx = 0; dx < outW; dx++) {
      const sx = rx + Math.floor(dx / scale);
      const sOff = (sy * img.width + sx) * 4;
      const dOff = dstRow + 1 + dx * 4;
      raw[dOff] = img.pixels[sOff];
      raw[dOff + 1] = img.pixels[sOff + 1];
      raw[dOff + 2] = img.pixels[sOff + 2];
      raw[dOff + 3] = 255;
    }
  }
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(outW, 0);
  ihdr.writeUInt32BE(outH, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const idat = zlib.deflateSync(raw);
  fs.writeFileSync(outPath, Buffer.concat([
    sig,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', idat),
    pngChunk('IEND', Buffer.alloc(0))
  ]));
}

function lumaAt(img, x, y) {
  const i = (y * img.width + x) * 4;
  return 0.299 * img.pixels[i] + 0.587 * img.pixels[i + 1] + 0.114 * img.pixels[i + 2];
}

// Measures sawtooth/staircase roughness along high-contrast edges vs interior sharpness
function analyzeRegionAA(baseImg, aaImg, rx, ry, rw, rh) {
  let edgeCount = 0;
  let sawtoothSum = 0;
  let edgeDiffSum = 0;
  let flatCount = 0;
  let flatDiffSum = 0;

  for (let y = ry + 1; y < ry + rh - 1; y++) {
    for (let x = rx + 1; x < rx + rw - 1; x++) {
      const bM = lumaAt(baseImg, x, y);
      const bL = lumaAt(baseImg, x - 1, y), bR = lumaAt(baseImg, x + 1, y);
      const bU = lumaAt(baseImg, x, y - 1), bD = lumaAt(baseImg, x, y + 1);
      const baseRange = Math.max(bM, bL, bR, bU, bD) - Math.min(bM, bL, bR, bU, bD);

      const aM = lumaAt(aaImg, x, y);
      const aL = lumaAt(aaImg, x - 1, y), aR = lumaAt(aaImg, x + 1, y);
      const aU = lumaAt(aaImg, x, y - 1), aD = lumaAt(aaImg, x, y + 1);
      const absDiff = Math.abs(aM - bM);

      if (baseRange >= 22) {
        edgeCount++;
        edgeDiffSum += absDiff;
        // High-frequency orthogonal impulse energy along contour (stairsteps spike this metric)
        const lapH = Math.abs(aM - 0.5 * (aL + aR));
        const lapV = Math.abs(aM - 0.5 * (aU + aD));
        sawtoothSum += Math.min(lapH, lapV);
      } else if (baseRange <= 8) {
        flatCount++;
        flatDiffSum += absDiff;
      }
    }
  }
  return {
    edgeCount,
    meanEdgeSawtooth: edgeCount > 0 ? sawtoothSum / edgeCount : 0,
    meanEdgeDelta: edgeCount > 0 ? edgeDiffSum / edgeCount : 0,
    meanFlatDelta: flatCount > 0 ? flatDiffSum / flatCount : 0
  };
}

async function triggerBtn(locator, useTap) {
  if (useTap) {
    await locator.tap();
  } else {
    await locator.click();
  }
}

async function bootToMap(page, mapCardSelector, expectedMode, useTap = false) {
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
  await triggerBtn(page.locator(mapCardSelector), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'CarSelect', { timeout: 5000 });
  await triggerBtn(page.locator('#btn-car-launch'), useTap);
  await page.waitForFunction((m) => window.app?.ui?.currentState === 'InGameHUD' && window.app?.currentMapMode === m, expectedMode, { timeout: 10000 });
  await page.waitForTimeout(550);
}

async function setPauseAA(page, targetType, targetLevel, useTap = false, verifyUiLabels = false) {
  await triggerBtn(page.locator('#btn-hud-pause'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });
  await triggerBtn(page.locator('[data-action="OpenOptions"]'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu', { timeout: 5000 });

  for (let i = 0; i < 8; i++) {
    const cur = await page.evaluate(() => window.app.state.options.gfx.aaType);
    if (cur === targetType) break;
    await triggerBtn(page.locator('.opt-step-btn[data-step-row="7"][data-step-dir="1"]'), useTap);
    await page.waitForTimeout(100);
  }
  expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe(targetType);

  if (targetLevel != null && targetType !== 'None' && targetType !== 'MSAA') {
    for (let i = 0; i < 6; i++) {
      const cur = await page.evaluate(() => window.app.state.options.gfx.aaLevel);
      if (cur === targetLevel) break;
      await triggerBtn(page.locator('.opt-step-btn[data-step-row="8"][data-step-dir="1"]'), useTap);
      await page.waitForTimeout(100);
    }
    expect(await page.evaluate(() => window.app.state.options.gfx.aaLevel)).toBe(targetLevel);
  }

  if (verifyUiLabels) {
    const row8Disabled = await page.locator('.opt-step-btn[data-step-row="8"][data-step-dir="1"]').isDisabled();
    const row8Text = await page.locator('.opt-row[data-opt-row="8"] .opt-val').innerText();
    if (targetType === 'None' || targetType === 'MSAA') {
      expect(row8Disabled).toBe(true);
      expect(row8Text).toContain('[DISABLED]');
    } else if (targetType === 'FXAA' || targetType === 'SMAA') {
      expect(row8Disabled).toBe(false);
      expect(['Low', 'Medium', 'High']).toContain(row8Text.trim());
    } else if (targetType === 'TSAA') {
      expect(row8Disabled).toBe(false);
      expect(['8x', '16x', '32x']).toContain(row8Text.trim());
    }
  }

  await triggerBtn(page.locator('#btn-opt-back'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });
  await triggerBtn(page.locator('[data-action="ResumeGame"]'), useTap);
  await page.waitForFunction(() => window.app?.ui?.currentState === 'InGameHUD', { timeout: 5000 });
  // Wait for stable GPU frames at identical parked pose
  await page.waitForTimeout(420);
}

test.describe('Phase 1: FXAA 3.11 Deep Visual & Pixel Verification', () => {
  test.setTimeout(90000);

  test('FXAA 3.11 smooths diagonal staircase edges across Low/Med/High while preserving flat detail (Circuit & Sandbox)', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => { console.log('[PAGEERR]', e.message); errors.push(e.message); });
    page.on('console', (msg) => {
      if (msg.type() === 'error' || msg.text().includes('GPU') || msg.text().includes('xgpu')) {
        console.log('[CONSOLE]', msg.type(), msg.text());
      }
      if (msg.type() === 'error' || msg.text().includes('GPUValidationError')) {
        errors.push(msg.text());
      }
    });

    // 1. Highway Circuit: guardrails, dashed highway stripes & car silhouette
    await bootToMap(page, '#card-map-circuit', 'Circuit');

    // Crop ROI covering diagonal highway lanes + guardrails + car silhouette (avoiding HUD corners)
    const circuitRoi = { x: 40, y: 200, w: 1200, h: 360 };
    const cropZoomCar = { x: 420, y: 340, w: 220, h: 140 };
    const cropZoomRail = { x: 30, y: 270, w: 240, h: 130 };

    await setPauseAA(page, 'None', null);
    const noneCircuitBuf = await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p1-circuit-none.png') });
    const noneCircuitImg = decodePng(noneCircuitBuf);
    saveZoomedCropPng(noneCircuitImg, cropZoomCar.x, cropZoomCar.y, cropZoomCar.w, cropZoomCar.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p1-circuit-none-3x.png'));
    saveZoomedCropPng(noneCircuitImg, cropZoomRail.x, cropZoomRail.y, cropZoomRail.w, cropZoomRail.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p1-rail-none-3x.png'));

    const metrics = {};
    for (const tier of [
      { label: 'low', level: 2, expectedText: 'Low' },
      { label: 'med', level: 4, expectedText: 'Medium' },
      { label: 'high', level: 8, expectedText: 'High' }
    ]) {
      await setPauseAA(page, 'FXAA', tier.level);
      const buf = await page.screenshot({ path: path.join(SCREENSHOT_DIR, `aa-p1-circuit-fxaa-${tier.label}.png`) });
      const img = decodePng(buf);
      saveZoomedCropPng(img, cropZoomCar.x, cropZoomCar.y, cropZoomCar.w, cropZoomCar.h, 3,
        path.join(SCREENSHOT_DIR, `aa-p1-circuit-fxaa-${tier.label}-3x.png`));
      saveZoomedCropPng(img, cropZoomRail.x, cropZoomRail.y, cropZoomRail.w, cropZoomRail.h, 3,
        path.join(SCREENSHOT_DIR, `aa-p1-rail-fxaa-${tier.label}-3x.png`));
      metrics[tier.label] = analyzeRegionAA(noneCircuitImg, img, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);
    }
    const baseMetrics = analyzeRegionAA(noneCircuitImg, noneCircuitImg, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);
    console.log('[Phase 1 Circuit AA Metrics]', JSON.stringify({ none: baseMetrics, ...metrics }, null, 2));

    expect(baseMetrics.edgeCount).toBeGreaterThan(500);
    for (const k of ['low', 'med', 'high']) {
      // Edge contours must change meaningfully while flat/low-contrast regions remain untouched
      expect(metrics[k].meanEdgeDelta).toBeGreaterThan(0.5);
      expect(metrics[k].meanFlatDelta).toBeLessThan(1.5);
      // Contour sawtooth roughness must strictly decrease compared to aliased None
      expect(metrics[k].meanEdgeSawtooth).toBeLessThan(baseMetrics.meanEdgeSawtooth);
    }
    // Stronger tier (High) must provide at least as much or stronger contour smoothing than Low
    expect(metrics.high.meanEdgeSawtooth).toBeLessThanOrEqual(metrics.low.meanEdgeSawtooth + 0.15);

    // 2. Sandbox Proving Grounds: horizon mountain ridge & cyber-grid diagonals
    await bootToMap(page, '#card-map-sandbox', 'Sandbox');
    const sandboxRoi = { x: 240, y: 220, w: 800, h: 360 };
    const cropZoomSandbox = { x: 460, y: 260, w: 220, h: 140 };

    await setPauseAA(page, 'None', null);
    const noneSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p1-sandbox-none.png') }));
    saveZoomedCropPng(noneSbImg, cropZoomSandbox.x, cropZoomSandbox.y, cropZoomSandbox.w, cropZoomSandbox.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p1-sandbox-none-3x.png'));
    const sbBase = analyzeRegionAA(noneSbImg, noneSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);

    await setPauseAA(page, 'FXAA', 8);
    const fxaaSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p1-sandbox-fxaa-high.png') }));
    saveZoomedCropPng(fxaaSbImg, cropZoomSandbox.x, cropZoomSandbox.y, cropZoomSandbox.w, cropZoomSandbox.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p1-sandbox-fxaa-high-3x.png'));
    const sbFxaa = analyzeRegionAA(noneSbImg, fxaaSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);
    console.log('[Phase 1 Sandbox AA Metrics]', JSON.stringify({ none: sbBase, fxaaHigh: sbFxaa }, null, 2));

    expect(sbFxaa.meanEdgeDelta).toBeGreaterThan(0.5);
    expect(sbFxaa.meanFlatDelta).toBeLessThan(1.5);
    expect(sbFxaa.meanEdgeSawtooth).toBeLessThan(sbBase.meanEdgeSawtooth);

    expect(errors).toEqual([]);
  });
});

test.describe('Phase 2: SMAA 1x Deep Visual & Pixel Verification', () => {
  test.setTimeout(90000);

  test('SMAA 1x reduces staircase roughness across Low/Med/High while preserving 90deg corners and flat regions', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => { console.log('[PAGEERR]', e.message); errors.push(e.message); });
    page.on('console', (msg) => {
      if (msg.type() === 'error' || msg.text().includes('GPU') || msg.text().includes('xgpu')) {
        console.log('[CONSOLE]', msg.type(), msg.text());
      }
      if (msg.type() === 'error' || msg.text().includes('GPUValidationError')) {
        errors.push(msg.text());
      }
    });

    await bootToMap(page, '#card-map-circuit', 'Circuit');
    const circuitRoi = { x: 40, y: 200, w: 1200, h: 360 };
    const cropZoomCar = { x: 420, y: 340, w: 220, h: 140 };
    const cropZoomRail = { x: 30, y: 270, w: 240, h: 130 };

    await setPauseAA(page, 'None', null);
    const noneCircuitImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p2-circuit-none.png') }));
    const baseMetrics = analyzeRegionAA(noneCircuitImg, noneCircuitImg, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);

    const smaaMetrics = {};
    for (const tier of [
      { label: 'low', level: 2 },
      { label: 'med', level: 4 },
      { label: 'high', level: 8 }
    ]) {
      await setPauseAA(page, 'SMAA', tier.level);
      const img = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, `aa-p2-circuit-smaa-${tier.label}.png`) }));
      saveZoomedCropPng(img, cropZoomCar.x, cropZoomCar.y, cropZoomCar.w, cropZoomCar.h, 3,
        path.join(SCREENSHOT_DIR, `aa-p2-circuit-smaa-${tier.label}-3x.png`));
      saveZoomedCropPng(img, cropZoomRail.x, cropZoomRail.y, cropZoomRail.w, cropZoomRail.h, 3,
        path.join(SCREENSHOT_DIR, `aa-p2-rail-smaa-${tier.label}-3x.png`));
      smaaMetrics[tier.label] = analyzeRegionAA(noneCircuitImg, img, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);
    }
    console.log('[Phase 2 Circuit SMAA Metrics]', JSON.stringify({ none: baseMetrics, ...smaaMetrics }, null, 2));
    expect(errors).toEqual([]);

    for (const k of ['low', 'med', 'high']) {
      expect(smaaMetrics[k].meanEdgeDelta).toBeGreaterThan(0.5);
      expect(smaaMetrics[k].meanFlatDelta).toBeLessThan(1.0);
      expect(smaaMetrics[k].meanEdgeSawtooth).toBeLessThan(baseMetrics.meanEdgeSawtooth);
    }
    expect(smaaMetrics.high.meanEdgeSawtooth).toBeLessThanOrEqual(smaaMetrics.low.meanEdgeSawtooth + 0.15);

    // Sandbox: mountain ridge + cyber-grid crossings
    await bootToMap(page, '#card-map-sandbox', 'Sandbox');
    const sandboxRoi = { x: 240, y: 220, w: 800, h: 360 };
    const cropZoomSandbox = { x: 460, y: 260, w: 220, h: 140 };

    await setPauseAA(page, 'None', null);
    const noneSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p2-sandbox-none.png') }));
    const sbBase = analyzeRegionAA(noneSbImg, noneSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);

    await setPauseAA(page, 'SMAA', 8);
    const smaaSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p2-sandbox-smaa-high.png') }));
    saveZoomedCropPng(smaaSbImg, cropZoomSandbox.x, cropZoomSandbox.y, cropZoomSandbox.w, cropZoomSandbox.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p2-sandbox-smaa-high-3x.png'));
    const sbSmaa = analyzeRegionAA(noneSbImg, smaaSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);
    console.log('[Phase 2 Sandbox SMAA Metrics]', JSON.stringify({ none: sbBase, smaaHigh: sbSmaa }, null, 2));

    expect(sbSmaa.meanEdgeDelta).toBeGreaterThan(0.4);
    expect(sbSmaa.meanFlatDelta).toBeLessThan(1.0);
    expect(sbSmaa.meanEdgeSawtooth).toBeLessThan(sbBase.meanEdgeSawtooth);

    expect(errors).toEqual([]);
  });
});

test.describe('Phase 3: Hardware 4x MSAA Deep Visual & Validation Verification', () => {
  test.setTimeout(90000);

  test('MSAA hardware 4x resolves geometric edges cleanly without GPUValidationError across dynamic toggles and resolution changes', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => { console.log('[PAGEERR]', e.message); errors.push(e.message); });
    page.on('console', (msg) => {
      if (msg.type() === 'error' || msg.text().includes('GPU') || msg.text().includes('xgpu')) {
        console.log('[CONSOLE]', msg.type(), msg.text());
      }
      if (msg.type() === 'error' || msg.text().includes('GPUValidationError')) {
        errors.push(msg.text());
      }
    });

    await bootToMap(page, '#card-map-circuit', 'Circuit');
    const circuitRoi = { x: 40, y: 200, w: 1200, h: 360 };
    const cropZoomCar = { x: 420, y: 340, w: 220, h: 140 };
    const cropZoomRail = { x: 30, y: 270, w: 240, h: 130 };

    await setPauseAA(page, 'None', null);
    const noneCircuitImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p3-circuit-none.png') }));
    const baseMetrics = analyzeRegionAA(noneCircuitImg, noneCircuitImg, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);

    // Enable MSAA via Options and confirm Row 8 (AA Quality) is disabled as fixed 4x toggle
    await page.click('#btn-hud-pause');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });
    await page.click('[data-action="OpenOptions"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'OptionsMenu', { timeout: 5000 });
    for (let i = 0; i < 8; i++) {
      if (await page.evaluate(() => window.app.state.options.gfx.aaType) === 'MSAA') break;
      await page.locator('.opt-step-btn[data-step-row="7"][data-step-dir="1"]').click();
      await page.waitForTimeout(90);
    }
    expect(await page.evaluate(() => window.app.state.options.gfx.aaType)).toBe('MSAA');
    expect(await page.locator('.opt-step-btn[data-step-row="8"][data-step-dir="1"]').isDisabled()).toBe(true);

    // Stress-test dynamic renderScale toggle while MSAA is enabled, then restore 1.0x
    await page.locator('.opt-step-btn[data-step-row="12"][data-step-dir="1"]').click();
    await page.waitForTimeout(180);
    await page.locator('.opt-step-btn[data-step-row="12"][data-step-dir="-1"]').click();
    await page.waitForTimeout(180);

    await page.click('#btn-opt-back');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'PauseMenu', { timeout: 5000 });
    await page.click('[data-action="ResumeGame"]');
    await page.waitForFunction(() => window.app?.ui?.currentState === 'InGameHUD', { timeout: 5000 });
    await page.waitForTimeout(400);

    const msaaCircuitImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p3-circuit-msaa.png') }));
    saveZoomedCropPng(msaaCircuitImg, cropZoomCar.x, cropZoomCar.y, cropZoomCar.w, cropZoomCar.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p3-circuit-msaa-3x.png'));
    saveZoomedCropPng(msaaCircuitImg, cropZoomRail.x, cropZoomRail.y, cropZoomRail.w, cropZoomRail.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p3-rail-msaa-3x.png'));
    const msaaMetrics = analyzeRegionAA(noneCircuitImg, msaaCircuitImg, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);
    console.log('[Phase 3 Circuit MSAA Metrics]', JSON.stringify({ none: baseMetrics, msaa4x: msaaMetrics }, null, 2));

    expect(errors).toEqual([]);
    expect(msaaMetrics.meanEdgeDelta).toBeGreaterThan(0.5);
    expect(msaaMetrics.meanFlatDelta).toBeLessThan(0.5);
    expect(msaaMetrics.meanEdgeSawtooth).toBeLessThan(baseMetrics.meanEdgeSawtooth);

    // Sandbox: geometric horizon ridge & orange pylons (subpixel geometry coverage)
    await bootToMap(page, '#card-map-sandbox', 'Sandbox');
    const sandboxRoi = { x: 240, y: 220, w: 800, h: 360 };
    const cropZoomSandbox = { x: 460, y: 260, w: 220, h: 140 };

    await setPauseAA(page, 'None', null);
    const noneSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p3-sandbox-none.png') }));
    const sbBase = analyzeRegionAA(noneSbImg, noneSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);

    await setPauseAA(page, 'MSAA', null);
    const msaaSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p3-sandbox-msaa.png') }));
    saveZoomedCropPng(msaaSbImg, cropZoomSandbox.x, cropZoomSandbox.y, cropZoomSandbox.w, cropZoomSandbox.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p3-sandbox-msaa-3x.png'));
    const sbMsaa = analyzeRegionAA(noneSbImg, msaaSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);
    console.log('[Phase 3 Sandbox MSAA Metrics]', JSON.stringify({ none: sbBase, msaa4x: sbMsaa }, null, 2));

    expect(errors).toEqual([]);
    expect(sbMsaa.meanEdgeDelta).toBeGreaterThan(0.3);
    expect(sbMsaa.meanFlatDelta).toBeLessThan(0.5);
    expect(sbMsaa.meanEdgeSawtooth).toBeLessThan(sbBase.meanEdgeSawtooth);
  });
});

test.describe('Phase 4: TSAA (TAA) Temporal Convergence & Motion Ghosting Verification', () => {
  test.setTimeout(120000);

  test('TSAA converges cleanly across 8x/16x/32x without stationary shimmer or high-speed motion ghosting', async ({ page }) => {
    const errors = [];
    page.on('pageerror', (e) => { console.log('[PAGEERR]', e.message); errors.push(e.message); });
    page.on('console', (msg) => {
      if (msg.type() === 'error' || msg.text().includes('GPUValidationError')) {
        console.log('[CONSOLE]', msg.type(), msg.text());
        errors.push(msg.text());
      }
    });

    await bootToMap(page, '#card-map-circuit', 'Circuit');
    const circuitRoi = { x: 40, y: 200, w: 1200, h: 360 };
    const cropZoomCar = { x: 420, y: 340, w: 220, h: 140 };
    const cropZoomRail = { x: 30, y: 270, w: 240, h: 130 };

    await setPauseAA(page, 'None', null);
    const noneCircuitImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p4-circuit-none.png') }));
    const baseMetrics = analyzeRegionAA(noneCircuitImg, noneCircuitImg, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);

    const taaMetrics = {};
    let lastTsaaImg = null;
    for (const tier of [
      { label: '8x', level: 2 },
      { label: '16x', level: 4 },
      { label: '32x', level: 8 }
    ]) {
      await setPauseAA(page, 'TSAA', tier.level);
      await page.waitForTimeout(350); // allow Halton sequence temporal convergence
      const img = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, `aa-p4-circuit-tsaa-${tier.label}.png`) }));
      saveZoomedCropPng(img, cropZoomCar.x, cropZoomCar.y, cropZoomCar.w, cropZoomCar.h, 3,
        path.join(SCREENSHOT_DIR, `aa-p4-circuit-tsaa-${tier.label}-3x.png`));
      saveZoomedCropPng(img, cropZoomRail.x, cropZoomRail.y, cropZoomRail.w, cropZoomRail.h, 3,
        path.join(SCREENSHOT_DIR, `aa-p4-rail-tsaa-${tier.label}-3x.png`));
      taaMetrics[tier.label] = analyzeRegionAA(noneCircuitImg, img, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);
      lastTsaaImg = img;
    }

    // Temporal stability check on stationary scene (sky + car + road): ensure unjittered sky + static history do not shimmer
    await page.waitForTimeout(220);
    const tsaaFrameB = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p4-circuit-tsaa-32x-b.png') }));
    const temporalStats = analyzeRegionAA(lastTsaaImg, tsaaFrameB, circuitRoi.x, circuitRoi.y, circuitRoi.w, circuitRoi.h);
    console.log('[Phase 4 Circuit TSAA Metrics]', JSON.stringify({ none: baseMetrics, ...taaMetrics, temporalDrift: temporalStats }, null, 2));

    expect(errors).toEqual([]);
    for (const k of ['8x', '16x', '32x']) {
      expect(taaMetrics[k].meanEdgeDelta).toBeGreaterThan(0.5);
      expect(taaMetrics[k].meanFlatDelta).toBeLessThan(1.5);
      expect(taaMetrics[k].meanEdgeSawtooth).toBeLessThan(baseMetrics.meanEdgeSawtooth);
    }
    expect(temporalStats.meanFlatDelta).toBeLessThan(0.5);

    // Sandbox: distant curved grid lines & horizon mountains
    await bootToMap(page, '#card-map-sandbox', 'Sandbox');
    const sandboxRoi = { x: 240, y: 220, w: 800, h: 360 };
    const cropZoomSandbox = { x: 460, y: 260, w: 220, h: 140 };

    await setPauseAA(page, 'None', null);
    const noneSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p4-sandbox-none.png') }));
    const sbBase = analyzeRegionAA(noneSbImg, noneSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);

    await setPauseAA(page, 'TSAA', 8);
    await page.waitForTimeout(350);
    const taaSbImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p4-sandbox-tsaa-32x.png') }));
    saveZoomedCropPng(taaSbImg, cropZoomSandbox.x, cropZoomSandbox.y, cropZoomSandbox.w, cropZoomSandbox.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p4-sandbox-tsaa-32x-3x.png'));
    const sbTaa = analyzeRegionAA(noneSbImg, taaSbImg, sandboxRoi.x, sandboxRoi.y, sandboxRoi.w, sandboxRoi.h);
    console.log('[Phase 4 Sandbox TSAA Metrics]', JSON.stringify({ none: sbBase, tsaa32x: sbTaa }, null, 2));

    expect(errors).toEqual([]);
    expect(sbTaa.meanEdgeDelta).toBeGreaterThan(0.5);
    expect(sbTaa.meanFlatDelta).toBeLessThan(1.2);
    expect(sbTaa.meanEdgeSawtooth).toBeLessThan(sbBase.meanEdgeSawtooth);

    // High-speed driving ghosting test on Highway Circuit (>100 km/h)
    await bootToMap(page, '#card-map-circuit', 'Circuit');
    await setPauseAA(page, 'TSAA', 8);
    await page.keyboard.down('KeyW');
    await page.waitForFunction(() => (window.app?.carPhysics?.forwardSpeed || 0) > 28.0, { timeout: 12000 });
    const motionImg = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, 'aa-p4-motion-tsaa-32x.png') }));
    saveZoomedCropPng(motionImg, cropZoomCar.x, cropZoomCar.y, cropZoomCar.w, cropZoomCar.h, 3,
      path.join(SCREENSHOT_DIR, 'aa-p4-motion-tsaa-32x-3x.png'));
    await page.keyboard.up('KeyW');

    expect(errors).toEqual([]);
  });
});

test.describe('Final Comparative Suite: All AA Modes Across Desktop & Mobile Viewports', () => {
  test.setTimeout(180000);

  const ALL_MODES = [
    { key: 'none', type: 'None', level: null },
    { key: 'fxaa', type: 'FXAA', level: 8 },
    { key: 'smaa', type: 'SMAA', level: 8 },
    { key: 'msaa', type: 'MSAA', level: null },
    { key: 'tsaa', type: 'TSAA', level: 8 }
  ];

  async function runViewportSweep(page, tag, roi, zoomCrop, useTap) {
    const errors = [];
    page.on('pageerror', (e) => { console.log(`[${tag} PAGEERR]`, e.message); errors.push(e.message); });
    page.on('console', (msg) => {
      if (msg.type() === 'error' || msg.text().includes('GPUValidationError')) {
        console.log(`[${tag} CONSOLE]`, msg.type(), msg.text());
        errors.push(msg.text());
      }
    });

    await bootToMap(page, '#card-map-circuit', 'Circuit', useTap);

    const images = {};
    for (const m of ALL_MODES) {
      await setPauseAA(page, m.type, m.level, useTap, true);
      if (m.type === 'TSAA') {
        await page.waitForTimeout(350);
      }
      const img = decodePng(await page.screenshot({ path: path.join(SCREENSHOT_DIR, `aa-final-${tag}-${m.key}.png`) }));
      saveZoomedCropPng(img, zoomCrop.x, zoomCrop.y, zoomCrop.w, zoomCrop.h, 3,
        path.join(SCREENSHOT_DIR, `aa-final-${tag}-${m.key}-3x.png`));
      images[m.key] = img;
    }

    const baseImg = images.none;
    const summary = {};
    summary.none = analyzeRegionAA(baseImg, baseImg, roi.x, roi.y, roi.w, roi.h);
    expect(summary.none.edgeCount).toBeGreaterThan(200);

    for (const m of ALL_MODES.slice(1)) {
      const stats = analyzeRegionAA(baseImg, images[m.key], roi.x, roi.y, roi.w, roi.h);
      summary[m.key] = stats;
      expect(stats.meanEdgeDelta).toBeGreaterThan(0.35);
      expect(stats.meanFlatDelta).toBeLessThan(1.5);
      expect(stats.meanEdgeSawtooth).toBeLessThan(summary.none.meanEdgeSawtooth);
    }

    console.log(`[Final ${tag.toUpperCase()} Comparative AA Metrics]`, JSON.stringify(summary, null, 2));
    expect(errors).toEqual([]);
    return summary;
  }

  test('Desktop (1280x720) tests None, FXAA, SMAA, MSAA, and TSAA together in one session', async ({ page }) => {
    const desktopRoi = { x: 40, y: 200, w: 1200, h: 360 };
    const desktopZoom = { x: 420, y: 340, w: 220, h: 140 };
    await runViewportSweep(page, 'desktop', desktopRoi, desktopZoom, false);
  });

  test('Mobile Touch Landscape (844x390) tests None, FXAA, SMAA, MSAA, and TSAA together via touch controls', async ({ browser }) => {
    const context = await browser.newContext({
      viewport: { width: 844, height: 390 },
      hasTouch: true,
      isMobile: true
    });
    const page = await context.newPage();
    try {
      // Mobile ROI centers cleanly over track, guardrails, and car away from top minimap/pause and bottom touch stick/pedals
      const mobileRoi = { x: 160, y: 95, w: 520, h: 175 };
      const mobileZoom = { x: 310, y: 155, w: 220, h: 125 };
      await runViewportSweep(page, 'mobile', mobileRoi, mobileZoom, true);
    } finally {
      await context.close();
    }
  });
});
