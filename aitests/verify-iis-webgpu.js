const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const EDGE_EXE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const PORT = 9333;
const TARGET_URL = 'https://mob.24-7.ro/';
const PROFILE_DIR = path.join(process.env.LOCALAPPDATA || 'C:\\Users\\Public', 'mob-edge-verify');
const SHOT_DIR = path.join(__dirname, 'screenshots');

function measureCenterPngBrightness(pngBuffer) {
  let pos = 8;
  let width = 0, height = 0, colorType = 6;
  const idatChunks = [];
  while (pos < pngBuffer.length) {
    const len = pngBuffer.readUInt32BE(pos);
    const type = pngBuffer.slice(pos + 4, pos + 8).toString('ascii');
    const data = pngBuffer.slice(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      colorType = data[9];
    } else if (type === 'IDAT') {
      idatChunks.push(data);
    } else if (type === 'IEND') {
      break;
    }
    pos += 12 + len;
  }
  const bpp = colorType === 6 ? 4 : 3;
  const stride = width * bpp + 1;
  const raw = zlib.inflateSync(Buffer.concat(idatChunks));
  const recon = Buffer.alloc(height * width * bpp);

  for (let y = 0; y < height; y++) {
    const rowIn = y * stride;
    const filter = raw[rowIn];
    const rowOut = y * width * bpp;
    const prevRow = (y - 1) * width * bpp;
    for (let x = 0; x < width * bpp; x++) {
      const val = raw[rowIn + 1 + x];
      const a = x >= bpp ? recon[rowOut + x - bpp] : 0;
      const b = y > 0 ? recon[prevRow + x] : 0;
      const c = (x >= bpp && y > 0) ? recon[prevRow + x - bpp] : 0;
      let outVal = val;
      if (filter === 1) outVal = (val + a) & 0xff;
      else if (filter === 2) outVal = (val + b) & 0xff;
      else if (filter === 3) outVal = (val + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
        const pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        outVal = (val + pr) & 0xff;
      }
      recon[rowOut + x] = outVal;
    }
  }

  let samples = 0, litPixels = 0, lumaSum = 0;
  let rMin = 255, rMax = 0, gMin = 255, gMax = 0, bMin = 255, bMax = 0;
  const y0 = Math.floor(height * 0.25), y1 = Math.floor(height * 0.75);
  const x0 = Math.floor(width * 0.25), x1 = Math.floor(width * 0.75);
  for (let y = y0; y < y1; y += 6) {
    for (let x = x0; x < x1; x += 6) {
      const idx = (y * width + x) * bpp;
      const r = recon[idx], g = recon[idx + 1], b = recon[idx + 2];
      const luma = r + g + b;
      lumaSum += luma;
      if (luma > 30) litPixels++;
      if (r < rMin) rMin = r; if (r > rMax) rMax = r;
      if (g < gMin) gMin = g; if (g > gMax) gMax = g;
      if (b < bMin) bMin = b; if (b > bMax) bMax = b;
      samples++;
    }
  }
  return {
    width, height, samples, litPixels,
    avgLuma: Math.round((lumaSum / Math.max(1, samples)) * 10) / 10,
    channelSpread: (rMax - rMin) + (gMax - gMin) + (bMax - bMin)
  };
}

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

class CdpClient {
  constructor(wsUrl) {
    this.ws = new WebSocket(wsUrl);
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
  }
  async connect() {
    await new Promise((resolve, reject) => {
      this.ws.addEventListener('open', resolve, { once: true });
      this.ws.addEventListener('error', reject, { once: true });
    });
    this.ws.addEventListener('message', (msg) => {
      const data = JSON.parse(msg.data);
      if (data.id && this.pending.has(data.id)) {
        const p = this.pending.get(data.id);
        this.pending.delete(data.id);
        if (data.error) p.reject(new Error(data.error.message));
        else p.resolve(data.result);
      } else if (data.method) {
        this.events.push(data);
      }
    });
  }
  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async evalJs(expression) {
    const res = await this.send('Runtime.evaluate', {
      expression,
      returnByValue: true,
      awaitPromise: true
    });
    if (res.exceptionDetails) {
      throw new Error('JS Exception: ' + JSON.stringify(res.exceptionDetails));
    }
    return res.result ? res.result.value : undefined;
  }
  close() { try { this.ws.close(); } catch (_) {} }
}

async function main() {
  fs.mkdirSync(PROFILE_DIR, { recursive: true });
  const args = [
    '--headless=new',
    '--disable-gpu-sandbox',
    '--use-gl=angle',
    '--enable-unsafe-webgpu',
    '--ignore-certificate-errors',
    '--host-resolver-rules=MAP mob.24-7.ro 192.168.0.111',
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFILE_DIR}`,
    '--window-size=1280,720',
    'about:blank'
  ];

  console.log('[E2E] Spawning headless Edge against live IIS:', TARGET_URL);
  const edge = spawn(EDGE_EXE, args, { stdio: 'ignore' });
  let cdp = null;

  try {
    let wsUrl = null;
    for (let i = 0; i < 40; i++) {
      try {
        const r = await fetch(`http://127.0.0.1:${PORT}/json/list`);
        const pages = await r.json();
        const page = pages.find((p) => p.type === 'page');
        if (page && page.webSocketDebuggerUrl) { wsUrl = page.webSocketDebuggerUrl; break; }
      } catch (_) {}
      await sleep(250);
    }
    if (!wsUrl) throw new Error('Edge CDP endpoint did not start on port ' + PORT);

    cdp = new CdpClient(wsUrl);
    await cdp.connect();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    await cdp.send('Network.enable');
    await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
    cdp.ws.addEventListener('message', (raw) => {
      try {
        const d = JSON.parse(raw.data);
        if (d.method === 'Runtime.consoleAPICalled') {
          console.log('[BROWSER:' + d.params.type + ']', d.params.args.map((a) => a.value ?? a.description ?? '').join(' '));
        } else if (d.method === 'Runtime.exceptionThrown') {
          console.error('[BROWSER EXCEPTION]', JSON.stringify(d.params.exceptionDetails));
        } else if (d.method === 'Log.entryAdded') {
          console.log('[LOG:' + d.params.entry.level + ']', d.params.entry.text, d.params.entry.url || '');
        } else if (d.method === 'Network.loadingFailed') {
          console.error('[NET FAIL]', JSON.stringify(d.params));
        }
      } catch (_) {}
    });

    console.log('[E2E] Navigating to live IIS site...');
    fs.mkdirSync(SHOT_DIR, { recursive: true });
    await cdp.send('Page.navigate', { url: TARGET_URL });

    // Poll until Wasm boots WebBridge and captures Studio -> Engine -> Disclaimer -> Splash
    let state = null;
    const seenIntro = new Set();
    let sawBranding = false;
    let sawStudioImg = false;
    let disclaimerOverflow = null;
    for (let i = 0; i < 65; i++) {
      await sleep(300);
      state = await cdp.evalJs(`(() => {
        const fatal = document.getElementById('mob-fatal-banner');
        const ui = document.getElementById('ui-root');
        const img = ui ? ui.querySelector('img.intro-studio-img') : null;
        const df = ui ? ui.querySelector('.disc-frame') : null;
        return {
          coi: window.crossOriginIsolated,
          hasGpu: Boolean(navigator.gpu),
          fatalText: fatal && fatal.style.display !== 'none' ? fatal.innerText : null,
          appState: window.app ? window.app.appState : null,
          introState: window.app ? window.app.introState : null,
          uiState: window.app && window.app.ui ? window.app.ui.currentState : null,
          mapMode: window.app ? window.app.currentMapMode : null,
          bridge: window.MOBWebBridge && window.MOBWebBridge.debug ? window.MOBWebBridge.debug() : null,
          uiText: ui ? ui.innerText.slice(0, 300) : '',
          studioImgOk: Boolean(img && img.complete && img.naturalWidth > 0),
          discOverflow: df ? { sw: df.scrollWidth, cw: df.clientWidth, sh: df.scrollHeight, ch: df.clientHeight } : null,
          canvasW: document.getElementById('screen') ? document.getElementById('screen').width : 0
        };
      })()`);
      if (state.fatalText) {
        throw new Error('Fatal banner displayed: ' + state.fatalText);
      }
      if (state.bridge && state.bridge.lastStateSeq > 0 && state.appState === 'IntroSequence' && state.introState && !seenIntro.has(state.introState)) {
        seenIntro.add(state.introState);
        const ilStyle = await cdp.evalJs(`(() => {
          const il = document.getElementById('intro-layer');
          return il ? { opacity: getComputedStyle(il).opacity, bg: getComputedStyle(il).backgroundColor } : null;
        })()`);
        if (ilStyle && (ilStyle.opacity !== '1' || ilStyle.bg !== 'rgb(0, 0, 0)')) {
          throw new Error('Intro backdrop is not solid opaque black during fade transition: ' + JSON.stringify(ilStyle));
        }
        await sleep(state.introState === 'Studio' ? 650 : 500);
        const postSnap = await cdp.evalJs(`(() => {
          const ui = document.getElementById('ui-root');
          const img = ui ? ui.querySelector('img.intro-studio-img') : null;
          const df = ui ? ui.querySelector('.disc-frame') : null;
          return {
            introNow: window.app ? window.app.introState : null,
            studioImgOk: Boolean(img && img.complete && img.naturalWidth > 0),
            imgInfo: img ? { complete: img.complete, nw: img.naturalWidth, nh: img.naturalHeight, curSrc: img.currentSrc } : null,
            uiHtml: ui ? ui.innerHTML.slice(0, 260) : '',
            discOverflow: df ? { sw: df.scrollWidth, cw: df.clientWidth, sh: df.scrollHeight, ch: df.clientHeight } : null,
            uiText: ui ? ui.innerText : ''
          };
        })()`);
        const shotBuf = Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
        fs.writeFileSync(path.join(SHOT_DIR, `live-intro-${state.introState.toLowerCase()}.png`), shotBuf);
        if (state.introState === 'Studio') {
          sawStudioImg = Boolean(postSnap.studioImgOk);
          const studioStats = measureCenterPngBrightness(shotBuf);
          console.log('[E2E] Studio splash stats:', JSON.stringify(studioStats), 'postSnap:', JSON.stringify(postSnap));
          if (!sawStudioImg || studioStats.litPixels < 20) {
            throw new Error('Studio splash jagofr-rvl-splash.webp did not render visibly! ' + JSON.stringify({ sawStudioImg, studioStats }));
          }
        }
        if (state.introState === 'Disclaimer') {
          disclaimerOverflow = postSnap.discOverflow;
          console.log('[E2E] Disclaimer overflow metrics:', JSON.stringify(disclaimerOverflow));
          if (disclaimerOverflow && (disclaimerOverflow.sw > disclaimerOverflow.cw + 2 || disclaimerOverflow.sh > disclaimerOverflow.ch + 2)) {
            throw new Error('Disclaimer frame has unexpected scrollbars: ' + JSON.stringify(disclaimerOverflow));
          }
        }
        if (postSnap.uiText.includes('M.O.B. STUDIOS') || postSnap.uiText.includes('Heaps.io') || postSnap.uiText.includes('WebGL')) {
          throw new Error('Disallowed branding leaked into intro: ' + postSnap.uiText);
        }
        if (postSnap.uiText.includes('RvL // ROGUE')) sawBranding = true;
      }
      if (state.appState === 'InGameUI') break;
    }

    console.log('[E2E] Boot state:', JSON.stringify(state));
    if (!state.coi) throw new Error('crossOriginIsolated is false on IIS!');
    if (!state.hasGpu) throw new Error('navigator.gpu missing!');
    if (!sawBranding) throw new Error('Authentic RvL // ROGUE branding not observed in Disclaimer!');
    if (state.bridge && state.bridge.bufferBytes > 220 * 1024 * 1024) {
      throw new Error('Wasm SharedArrayBuffer exceeded mobile-safe 220 MiB budget: ' + state.bridge.bufferBytes);
    }

    const consoleErrors = cdp.events
      .filter((e) => (e.method === 'Runtime.exceptionThrown' || (e.method === 'Runtime.consoleAPICalled' && e.params.type === 'error'))
        && !JSON.stringify(e.params).includes('chrome-extension://'))
      .map((e) => JSON.stringify(e.params));
    if (consoleErrors.length > 0) {
      throw new Error('App console/runtime errors observed: ' + consoleErrors.slice(0, 3).join(' | '));
    }

    if (state.appState !== 'InGameUI') {
      throw new Error('Timed out waiting for IntroSequence -> InGameUI; last state=' + JSON.stringify(state));
    }

    await sleep(600);
    const splashPng = Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
    fs.writeFileSync(path.join(SHOT_DIR, 'live-splash.png'), splashPng);
    const splashStats = measureCenterPngBrightness(splashPng);
    console.log('[E2E] Splash center 3D pixel stats:', JSON.stringify(splashStats));
    if (splashStats.litPixels < 20 || splashStats.channelSpread < 30) {
      throw new Error('3D WebGPU showcase is blank/black on Splash! ' + JSON.stringify(splashStats));
    }

    // Enter Main Menu from Splash
    await cdp.evalJs(`(() => {
      const btn = document.getElementById('btn-splash-enter');
      if (btn) btn.click();
    })()`);
    await sleep(600);
    let menuCheck = await cdp.evalJs(`({ uiState: window.app.ui.currentState, text: document.getElementById('ui-root').innerText })`);
    console.log('[E2E] MainMenu check:', JSON.stringify(menuCheck));
    if (menuCheck.uiState !== 'MainMenu' || !menuCheck.text.includes('v0.8.0')) {
      throw new Error('MainMenu v0.8.0 missing: ' + JSON.stringify(menuCheck));
    }

    // Verify Credits restore Gerard "Jamie" (Jagofr) Francis & RvL // ROGUE without Heaps
    await cdp.evalJs(`document.querySelector('[data-action="OpenCredits"]').click()`);
    await sleep(350);
    const credText = await cdp.evalJs(`document.getElementById('ui-root').innerText`);
    if (!credText.includes('Gerard') || !credText.includes('RvL // ROGUE') || credText.includes('Heaps.io')) {
      throw new Error('Credits mismatch: ' + credText);
    }
    await cdp.evalJs(`document.getElementById('btn-cred-back').click()`);
    await sleep(350);

    // Verify Options -> Graphics 14 rows & Anti-Aliasing cycling (FXAA -> TSAA -> FXAA)
    await cdp.evalJs(`document.querySelector('[data-action="OpenOptions"]').click()`);
    await sleep(350);
    await cdp.evalJs(`document.querySelector('.opt-step-btn[data-step-row="7"][data-step-dir="1"]').click()`);
    await sleep(250);
    const aaCheck = await cdp.evalJs(`window.app.state?.options?.gfx?.aaType`);
    if (aaCheck !== 'TSAA') {
      throw new Error('Anti-Aliasing cycling failed on live IIS: ' + aaCheck);
    }
    await cdp.evalJs(`document.querySelector('.opt-step-btn[data-step-row="7"][data-step-dir="-1"]').click()`);
    await sleep(200);
    await cdp.evalJs(`document.getElementById('btn-opt-back').click()`);
    await sleep(350);

    // Open MapSelect -> CarSelect -> Start Highway Circuit
    await cdp.evalJs(`document.querySelector('[data-action="OpenMapSelect"]').click()`);
    await sleep(400);
    await cdp.evalJs(`document.getElementById('card-map-circuit').click()`);
    await sleep(400);
    await cdp.evalJs(`(() => { const b = document.getElementById('btn-car-launch'); if (b) b.click(); })()`);
    await sleep(1000);

    let driveCheck = await cdp.evalJs(`({ uiState: window.app.ui.currentState, mapMode: window.app.currentMapMode, speed0: window.app.carPhysics.forwardSpeed })`);
    console.log('[E2E] Circuit started:', JSON.stringify(driveCheck));
    if (driveCheck.uiState !== 'InGameHUD' || driveCheck.mapMode !== 'Circuit') {
      throw new Error('Failed to start Circuit: ' + JSON.stringify(driveCheck));
    }

    // Accelerate with W key for 1.5s to verify 240Hz physics + input bridge
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', windowsVirtualKeyCode: 87, key: 'w', code: 'KeyW' });
    await sleep(1500);
    await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', windowsVirtualKeyCode: 87, key: 'w', code: 'KeyW' });
    let accelCheck = await cdp.evalJs(`({ speedMs: window.app.carPhysics.forwardSpeed, gear: window.app.carPhysics.currentGear, pos: window.app.carPhysics.pos })`);
    console.log('[E2E] After throttle:', JSON.stringify(accelCheck));
    if (accelCheck.speedMs <= 1.0) {
      throw new Error('Vehicle failed to accelerate on Circuit: ' + JSON.stringify(accelCheck));
    }

    const circuitPng = Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
    fs.writeFileSync(path.join(SHOT_DIR, 'live-circuit.png'), circuitPng);
    const circuitStats = measureCenterPngBrightness(circuitPng);
    console.log('[E2E] Circuit 3D center pixel stats:', JSON.stringify(circuitStats));
    if (circuitStats.litPixels < 20 || circuitStats.channelSpread < 30) {
      throw new Error('Circuit WebGPU 3D view is blank/black! ' + JSON.stringify(circuitStats));
    }

    // Switch to Sandbox map & verify 3D cyber-grid rendering
    await cdp.evalJs(`window.app.loadMap('Sandbox')`);
    await sleep(800);
    let sbCheck = await cdp.evalJs(`({ mapMode: window.app.currentMapMode, pos: window.app.carPhysics.pos })`);
    console.log('[E2E] Sandbox check:', JSON.stringify(sbCheck));
    if (sbCheck.mapMode !== 'Sandbox') throw new Error('Sandbox switch failed');
    const sbPng = Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
    fs.writeFileSync(path.join(SHOT_DIR, 'live-sandbox.png'), sbPng);
    const sbStats = measureCenterPngBrightness(sbPng);
    console.log('[E2E] Sandbox 3D center pixel stats:', JSON.stringify(sbStats));
    if (sbStats.litPixels < 20 || sbStats.channelSpread < 30) {
      throw new Error('Sandbox WebGPU 3D view is blank/black! ' + JSON.stringify(sbStats));
    }

    // Pause -> Quit -> Multiplayer Host Lobby via live IIS /relay.ashx
    await cdp.evalJs(`document.getElementById('btn-hud-pause').click()`);
    await sleep(400);
    await cdp.evalJs(`document.querySelector('[data-action="QuitToTitle"]').click()`);
    await sleep(400);
    await cdp.evalJs(`document.querySelector('[data-action="OpenMultiplayer"]').click()`);
    await sleep(400);
    await cdp.evalJs(`document.getElementById('btn-mp-host-circuit').click()`);

    let mpCheck = null;
    for (let i = 0; i < 16; i++) {
      await sleep(250);
      mpCheck = await cdp.evalJs(`window.app.multiplayer`);
      if (mpCheck && mpCheck.roomId) break;
    }
    console.log('[E2E] Multiplayer Lobby via live IIS:', JSON.stringify(mpCheck));
    if (!mpCheck || !mpCheck.roomId) {
      throw new Error('Multiplayer room failed to host via IIS /relay.ashx: ' + JSON.stringify(mpCheck));
    }

    // Mobile iPhone Portrait -> Landscape + Touch Layer Check
    await cdp.send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 390, height: 844, deviceScaleFactor: 3, mobile: true,
      screenOrientation: { type: 'portraitPrimary', angle: 0 }
    });
    await sleep(350);
    const portraitVisible = await cdp.evalJs(`getComputedStyle(document.getElementById('mob-portrait-gate')).display`);
    if (portraitVisible === 'none') {
      throw new Error('Mobile portrait gate failed to appear at 390x844!');
    }
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 844, height: 390, deviceScaleFactor: 3, mobile: true,
      screenOrientation: { type: 'landscapePrimary', angle: 90 }
    });
    await sleep(400);
    const landscapeHidden = await cdp.evalJs(`getComputedStyle(document.getElementById('mob-portrait-gate')).display`);
    if (landscapeHidden !== 'none') {
      throw new Error('Mobile portrait gate remained visible in 844x390 landscape: ' + landscapeHidden);
    }
    await cdp.evalJs(`(() => {
      const lv = document.getElementById('btn-mp-leave');
      if (lv) lv.click();
    })()`);
    await sleep(300);
    await cdp.evalJs(`(() => {
      const back = document.getElementById('btn-mp-back');
      if (back) back.click();
    })()`);
    await sleep(300);
    await cdp.evalJs(`(() => {
      const ms = document.querySelector('[data-action="OpenMapSelect"]');
      if (ms) ms.click();
    })()`);
    await sleep(350);
    await cdp.evalJs(`(() => {
      const cc = document.getElementById('card-map-circuit');
      if (cc) cc.click();
    })()`);
    await sleep(350);
    await cdp.evalJs(`(() => {
      const cl = document.getElementById('btn-car-launch');
      if (cl) cl.click();
    })()`);
    await sleep(700);
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [{ x: 420, y: 200, id: 1 }]
    });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await sleep(450);
    const touchUi = await cdp.evalJs(`({ uiState: window.app.ui.currentState, active: window.app.isTouchActive, hasLayer: Boolean(document.getElementById('touch-layer')), hasGas: Boolean(document.getElementById('touch-btn-gas')) })`);
    console.log('[E2E] Mobile iPhone landscape + touch check:', JSON.stringify(touchUi));
    if (!touchUi.hasLayer || !touchUi.hasGas) {
      throw new Error('Touch layer did not appear after mobile touch on Circuit: ' + JSON.stringify(touchUi));
    }
    const mobilePng = Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
    fs.writeFileSync(path.join(SHOT_DIR, 'live-mobile-landscape.png'), mobilePng);

    // Emulated iPhone Safari path: Main-thread WebGPU + 4096-page SharedArrayBuffer cap + 96MB GC heap
    await cdp.send('Emulation.setUserAgentOverride', {
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1'
    });
    await cdp.send('Page.navigate', { url: TARGET_URL });
    let iosState = null;
    for (let i = 0; i < 65; i++) {
      await sleep(300);
      iosState = await cdp.evalJs(`(() => ({
        fatal: document.getElementById('mob-fatal-banner')?.style.display !== 'none' ? document.getElementById('mob-fatal-banner')?.innerText : null,
        appState: window.app?.appState,
        uiState: window.app?.ui?.currentState,
        touchActive: window.app?.isTouchActive,
        bridge: window.MOBWebBridge?.debug?.()
      }))()`);
      if (iosState.fatal) throw new Error('iOS Safari path showed fatal banner: ' + iosState.fatal);
      if (iosState.appState === 'InGameUI') break;
    }
    console.log('[E2E] Emulated iPhone Main-Thread WebGPU boot state:', JSON.stringify(iosState));
    if (iosState.appState !== 'InGameUI') {
      throw new Error('Emulated iPhone path failed to reach InGameUI: ' + JSON.stringify(iosState));
    }
    if (iosState.bridge && iosState.bridge.bufferBytes > 160 * 1024 * 1024) {
      throw new Error('Mobile Wasm memory exceeded 160 MiB target: ' + iosState.bridge.bufferBytes);
    }
    await sleep(500);
    const iosSplashPng = Buffer.from((await cdp.send('Page.captureScreenshot', { format: 'png' })).data, 'base64');
    const iosStats = measureCenterPngBrightness(iosSplashPng);
    console.log('[E2E] Emulated iPhone Main-Thread WebGPU Splash stats:', JSON.stringify(iosStats));
    if (iosStats.litPixels < 20 || iosStats.channelSpread < 30) {
      throw new Error('Emulated iPhone Main-Thread WebGPU rendered blank/black: ' + JSON.stringify(iosStats));
    }

    console.log('[E2E] ALL LIVE IIS + WEBGPU + WASM + MOBILE + IPHONE VERIFICATIONS PASSED!');
  } finally {
    if (cdp) cdp.close();
    try { edge.kill(); } catch (_) {}
  }
}

main().catch((err) => {
  console.error('[E2E FAIL]', err);
  process.exit(1);
});
