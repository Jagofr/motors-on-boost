/* M.O.B. // Motors on Boost - HTML5/CSS3 WebGPU DOM Overlay, WebBridge IPC, Audio & Relay */
(function () {
  "use strict";

  const MAGIC = [0x4d4f4232, 0x57475055, 0x53484d31, 0x32303236];
  const MAILBOX_SIZE = 131072;

  const OFF_STATE_SEQ = 16;
  const OFF_PORTRAIT_BLOCKED = 24;
  const OFF_VIEWPORT_W = 28;
  const OFF_VIEWPORT_H = 32;
  const OFF_TOUCH_ACTIVE = 36;
  const OFF_TOUCH_HANDBRAKE = 40;
  const OFF_TOUCH_BOOST = 44;
  const OFF_TOUCH_PAUSE = 48;
  const OFF_STORAGE_READY = 52;
  const OFF_GPU_READY = 56;
  const OFF_IN_MENU = 60;

  const OFF_SPEED_KMH = 64;
  const OFF_RPM_NORM = 68;
  const OFF_GEAR = 72;
  const OFF_BOOST_PCT = 76;
  const OFF_CAR_X = 92;
  const OFF_CAR_Y = 96;
  const OFF_CAR_YAW = 100;
  const OFF_TOUCH_STEER = 104;
  const OFF_TOUCH_THROTTLE = 108;
  const OFF_TOUCH_BRAKE = 112;
  const OFF_FPS = 120;

  const OFF_QUERY_LEN = 124;
  const OFF_QUERY_DATA = 128;
  const MAX_QUERY_BYTES = 128;

  const OFF_STATE_LEN = 256;
  const OFF_STATE_DATA = 260;

  const OFF_OUT_WRITE = 32768;
  const OFF_OUT_READ = 32772;
  const OFF_OUT_BUF = 32776;
  const OUT_RING_CAP = 32760;

  const OFF_IN_WRITE = 65536;
  const OFF_IN_READ = 65540;
  const OFF_IN_BUF = 65544;
  const IN_RING_CAP = 65528;

  const STORAGE_KEYS = [
    "mob_motors_on_boost_save_v4",
    "mob_motors_on_boost_save_v3",
    "mob_motors_on_boost_save_v2",
    "mob_motors_on_boost_save_v1",
    "burnout_overdrive_save_v1"
  ];

  const decoder = new TextDecoder("utf-8");
  const encoder = new TextEncoder();

  function decodeSharedUtf8(buf, offset, len) {
    if (len <= 0) return "";
    const tmp = new Uint8Array(len);
    tmp.set(new Uint8Array(buf, offset, len));
    return decoder.decode(tmp);
  }

  function encodeSharedUtf8(str) {
    return encoder.encode(String(str));
  }

  // Enum shims matching window.IntroState & window.MapMode for E2E checks
  window.IntroState = window.IntroState || {
    None: "None",
    Studio: "Studio",
    Engine: "Engine",
    Disclaimer: "Disclaimer"
  };
  window.MapMode = window.MapMode || {
    Circuit: "Circuit",
    Sandbox: "Sandbox"
  };

  // --- SharedMemory Mailbox Client ---
  let wasmMemory = null;
  let mailboxOffset = -1;
  let lastStateSeq = -1;
  let hydratedSent = false;
  let latestState = {
    version: "v0.8.0 (Build 0016)",
    appState: "IntroSequence",
    introState: "Studio",
    introAlpha: 1.0,
    introShowcaseFading: false,
    showcaseAlpha: 0.0,
    uiState: "Splash",
    mapMode: "Circuit",
    pausedByOrientation: Boolean(window.__mobPortraitBlocked),
    hasSavedRun: false,
    isOpenedFromPause: false,
    touchEnabled: false,
    touchSettings: null,
    mainMenuIdx: 0,
    mapIdx: 0,
    pauseIdx: 0,
    mp: null,
    options: null,
    minimap: null
  };
  let telemetry = {
    speedKmh: 0,
    rpmNorm: 0,
    gear: 1,
    boostPct: 1,
    carX: 0,
    carY: 0,
    carYaw: 0,
    fps: 60,
    inMenu: true
  };
  let cachedWaypoints = null;

  function findMailboxOffset(buf) {
    if (!buf || buf.byteLength < MAILBOX_SIZE) return -1;
    // Scan 4-byte aligned offsets first, then byte-by-byte fallback in case Bytes header isn't 4B-aligned
    const i32 = new Int32Array(buf);
    const limit = i32.length - (MAILBOX_SIZE >> 2);
    for (let i = 0; i <= limit; i++) {
      if (
        i32[i] === MAGIC[0] &&
        i32[i + 1] === MAGIC[1] &&
        i32[i + 2] === MAGIC[2] &&
        i32[i + 3] === MAGIC[3]
      ) {
        return i * 4;
      }
    }
    const u8 = new Uint8Array(buf);
    for (let b = 0; b <= buf.byteLength - MAILBOX_SIZE; b++) {
      if (
        u8[b] === 0x32 && u8[b + 1] === 0x42 && u8[b + 2] === 0x4f && u8[b + 3] === 0x4d &&
        u8[b + 4] === 0x55 && u8[b + 5] === 0x50 && u8[b + 6] === 0x47 && u8[b + 7] === 0x57
      ) {
        const dv = new DataView(buf, b, 16);
        if (dv.getInt32(8, true) === MAGIC[2] && dv.getInt32(12, true) === MAGIC[3]) {
          console.log("[WebBridge] Attached unaligned mailbox at", b);
          return b;
        }
      }
    }
    return -1;
  }

  function ensureMailbox() {
    if (!wasmMemory) return null;
    const buf = wasmMemory.buffer;
    if (mailboxOffset >= 0 && mailboxOffset + MAILBOX_SIZE <= buf.byteLength) {
      const dv = new DataView(buf, mailboxOffset, MAILBOX_SIZE);
      if (
        dv.getInt32(0, true) === MAGIC[0] &&
        dv.getInt32(4, true) === MAGIC[1] &&
        dv.getInt32(8, true) === MAGIC[2] &&
        dv.getInt32(12, true) === MAGIC[3]
      ) {
        return dv;
      }
    }
    mailboxOffset = findMailboxOffset(buf);
    if (mailboxOffset < 0) return null;
    return new DataView(buf, mailboxOffset, MAILBOX_SIZE);
  }

  const pendingInbound = [];

  function writeInboundRing(dv, text) {
    const payload = encodeSharedUtf8(text);
    const len = payload.length;
    const padded = (4 + len + 3) & ~3;
    if (padded >= IN_RING_CAP) return false;

    let w = dv.getInt32(OFF_IN_WRITE, true);
    const r = dv.getInt32(OFF_IN_READ, true);
    const used = w >= r ? w - r : IN_RING_CAP - r + w;
    const free = IN_RING_CAP - used - 4;
    if (padded > free) return false;

    if (w + padded > IN_RING_CAP) {
      if (r > w || r <= padded) return false;
      dv.setInt32(OFF_IN_BUF + w, -1, true);
      w = 0;
    }

    dv.setInt32(OFF_IN_BUF + w, len, true);
    new Uint8Array(wasmMemory.buffer, mailboxOffset + OFF_IN_BUF + w + 4, len).set(payload);
    let nextW = w + padded;
    if (nextW >= IN_RING_CAP) nextW = 0;
    dv.setInt32(OFF_IN_WRITE, nextW, true);
    return true;
  }

  function pushInbound(objOrStr) {
    const text = typeof objOrStr === "string" ? objOrStr : JSON.stringify(objOrStr);
    const dv = ensureMailbox();
    if (!dv) {
      if (pendingInbound.length < 256) pendingInbound.push(text);
      return false;
    }
    while (pendingInbound.length > 0) {
      if (!writeInboundRing(dv, pendingInbound[0])) break;
      pendingInbound.shift();
    }
    return writeInboundRing(dv, text);
  }

  function drainOutboundRing(dv) {
    const results = [];
    for (let guard = 0; guard < 128; guard++) {
      const w = dv.getInt32(OFF_OUT_WRITE, true);
      let r = dv.getInt32(OFF_OUT_READ, true);
      if (w === r) break;

      let len = dv.getInt32(OFF_OUT_BUF + r, true);
      if (len < 0) {
        r = 0;
        dv.setInt32(OFF_OUT_READ, 0, true);
        if (w === 0) break;
        len = dv.getInt32(OFF_OUT_BUF, true);
      }
      if (len < 0 || len > OUT_RING_CAP - 4) {
        dv.setInt32(OFF_OUT_READ, w, true);
        break;
      }

      const str = decodeSharedUtf8(wasmMemory.buffer, mailboxOffset + OFF_OUT_BUF + r + 4, len);
      const padded = (4 + len + 3) & ~3;
      let nextR = r + padded;
      if (nextR >= OUT_RING_CAP) nextR = 0;
      dv.setInt32(OFF_OUT_READ, nextR, true);
      results.push(str);
    }
    return results;
  }

  function hydrateStorageAndEnv(dv) {
    if (hydratedSent) return;
    hydratedSent = true;

    const search = window.location.search || "";
    const qBytes = encodeSharedUtf8(search);
    const qLen = Math.min(qBytes.length, MAX_QUERY_BYTES);
    dv.setInt32(OFF_QUERY_LEN, qLen, true);
    if (qLen > 0) {
      new Uint8Array(wasmMemory.buffer, mailboxOffset + OFF_QUERY_DATA, qLen).set(qBytes.subarray(0, qLen));
    }

    for (let i = 0; i < STORAGE_KEYS.length; i++) {
      const key = STORAGE_KEYS[i];
      let val = null;
      try {
        val = window.localStorage ? window.localStorage.getItem(key) : null;
      } catch (_) {}
      pushInbound({
        type: "save_load",
        key: key,
        value: val,
        done: i === STORAGE_KEYS.length - 1
      });
    }

    const baseUrl =
      window.location.origin && window.location.origin !== "null"
        ? window.location.origin + window.location.pathname
        : "";
    const roomParam = new URLSearchParams(search).get("room") || "";
    pushInbound({
      type: "browser_env",
      baseUrl: baseUrl,
      room: roomParam
    });
    dv.setInt32(OFF_STORAGE_READY, 1, true);
  }

  // --- WebAudio Synth (Menu Beeps & Unlock) ---
  let audioCtx = null;
  let audioMaster = 0.8;
  let audioSfx = 0.9;
  let audioSuspended = false;

  // Preload critical intro visuals early so Studio frame 1 renders without pop-in
  try {
    ["./intro/jagofr-rvl-splash.webp", "./intro/icons/logo_haxe.webp", "./intro/icons/logo_hlwgpu.svg", "./intro/icons/logo_webgpu.svg"]
      .forEach(function (src) { const pre = new Image(); pre.src = src; });
  } catch (_) {}

  let hasRealGesture = false;
  window.addEventListener("pointerdown", function () { hasRealGesture = true; }, { passive: true, capture: true });
  window.addEventListener("keydown", function () { hasRealGesture = true; }, { passive: true, capture: true });

  function ensureAudioCtx() {
    if (!hasRealGesture && (!navigator.userActivation || !navigator.userActivation.hasBeenActive)) {
      return null;
    }
    if (!audioCtx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) audioCtx = new AC();
    }
    if (audioCtx && audioCtx.state === "suspended" && !audioSuspended) {
      audioCtx.resume().catch(function () {});
    }
    return audioCtx;
  }

  function playBeep(freq, dur, gainVal) {
    if (audioSuspended) return;
    const ctx = ensureAudioCtx();
    if (!ctx) return;
    try {
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq || 440, now);
      const peak = Math.max(0.01, Math.min(0.4, (gainVal || audioMaster * audioSfx) * 0.25));
      gain.gain.setValueAtTime(peak, now);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + Math.max(0.02, dur || 0.06));
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + Math.max(0.03, (dur || 0.06) + 0.01));
    } catch (_) {}
  }

  // --- 3-Tier Relay Client (WebSocket -> HTTP POST Poll -> BroadcastChannel) ---
  const relayClients = new Map();

  function createRelayClient(id) {
    const state = {
      id: id,
      ws: null,
      httpUrl: "",
      pollTimer: null,
      fallbackTimer: null,
      bc: null,
      bcTimer: null,
      connId: "",
      roomId: "",
      isHost: false,
      welcomeReceived: false,
      useHttp: false,
      useBc: false,
      pollInFlight: false,
      pendingSends: []
    };

    function emitToHaxe(op, extra) {
      pushInbound(Object.assign({ type: "net_ev", id: id, op: op }, extra || {}));
    }

    function stopTimers() {
      if (state.fallbackTimer) { clearTimeout(state.fallbackTimer); state.fallbackTimer = null; }
      if (state.pollTimer) { clearInterval(state.pollTimer); state.pollTimer = null; }
      if (state.bcTimer) { clearTimeout(state.bcTimer); state.bcTimer = null; }
    }

    function resolveRelayBase() {
      const env = window.__MOB_ENV__ || {};
      const host = window.location && window.location.hostname ? window.location.hostname : "";
      if (env.relayMode === "broadcast") {
        return { mode: "broadcast", origin: "" };
      }
      if (
        env.target === "gh-pages" &&
        Array.isArray(env.staticOfflineHosts) &&
        env.staticOfflineHosts.indexOf(host) >= 0
      ) {
        return { mode: "broadcast", origin: "" };
      }
      if (env.relayMode === "remote" && env.relayOrigin) {
        return { mode: "remote", origin: String(env.relayOrigin).replace(/\/+$/, "") };
      }
      return { mode: "same-origin", origin: "" };
    }

    function resolveWsUrl(explicit) {
      if (explicit) return explicit;
      const cfg = resolveRelayBase();
      if (cfg.mode === "remote" && cfg.origin) {
        if (cfg.origin.startsWith("https://")) return "wss://" + cfg.origin.slice(8) + "/relay.ashx";
        if (cfg.origin.startsWith("http://")) return "ws://" + cfg.origin.slice(7) + "/relay.ashx";
      }
      const loc = window.location;
      if (loc.protocol === "http:" || loc.protocol === "https:") {
        const proto = loc.protocol === "https:" ? "wss:" : "ws:";
        return proto + "//" + loc.host + "/relay.ashx";
      }
      return "ws://127.0.0.1:8090/relay.ashx";
    }

    function resolveHttpUrl(explicit) {
      if (explicit) {
        if (explicit.startsWith("wss://")) return "https://" + explicit.slice(6);
        if (explicit.startsWith("ws://")) return "http://" + explicit.slice(5);
      }
      const cfg = resolveRelayBase();
      if (cfg.mode === "remote" && cfg.origin) {
        return cfg.origin + "/relay.ashx";
      }
      const loc = window.location;
      if (loc.protocol === "http:" || loc.protocol === "https:") {
        return loc.protocol + "//" + loc.host + "/relay.ashx";
      }
      return "";
    }

    function flushPending() {
      if (!state.pendingSends || state.pendingSends.length === 0) return;
      const queue = state.pendingSends.splice(0, state.pendingSends.length);
      for (const obj of queue) {
        sendRaw(obj);
      }
    }

    function handleRelayPacket(msg) {
      if (!msg || !msg.type) return;
      switch (msg.type) {
        case "welcome":
          state.welcomeReceived = true;
          if (msg.connId) state.connId = String(msg.connId);
          stopTimers();
          emitToHaxe("open", { connId: state.connId });
          flushPending();
          break;
        case "room_hosted":
          state.roomId = String(msg.roomId || "");
          state.isHost = true;
          emitToHaxe("hosted", { roomId: state.roomId, connId: state.connId });
          break;
        case "room_joined":
          state.roomId = String(msg.roomId || "");
          state.isHost = false;
          emitToHaxe("joined", { roomId: state.roomId, connId: state.connId });
          break;
        case "peer_joined":
          emitToHaxe("peer_join", { peerId: String(msg.peerId || "") });
          break;
        case "peer_left":
          emitToHaxe("peer_leave", { peerId: String(msg.peerId || "") });
          break;
        case "relay_from_peer":
          emitToHaxe("from_peer", { fromId: String(msg.fromId || ""), payload: msg.payload });
          break;
        case "relay_from_host":
          emitToHaxe("from_host", { payload: msg.payload });
          break;
        case "host_disconnected":
          state.roomId = "";
          state.isHost = false;
          emitToHaxe("host_lost", {});
          break;
        case "error":
          emitToHaxe("error", { error: String(msg.message || "Relay error") });
          break;
      }
    }

    function startBroadcastFallback() {
      state.useBc = true;
      state.useHttp = false;
      stopTimers();
      try {
        if (typeof BroadcastChannel !== "undefined") {
          state.connId = state.connId || ("bc_" + id + "_" + Math.floor(Math.random() * 1e6));
          state.welcomeReceived = true;
          state.bc = new BroadcastChannel("mob_p2p_relay_v1");
          state.bc.onmessage = function (ev) {
            const d = ev.data;
            if (!d || d.roomId !== state.roomId || d.fromId === state.connId) return;
            if (d.kind === "join" && state.isHost) emitToHaxe("peer_join", { peerId: d.fromId });
            else if (d.kind === "leave" && state.isHost) emitToHaxe("peer_leave", { peerId: d.fromId });
            else if (d.kind === "to_host" && state.isHost) emitToHaxe("from_peer", { fromId: d.fromId, payload: d.payload });
            else if (d.kind === "to_peer" && !state.isHost && d.targetId === state.connId) emitToHaxe("from_host", { payload: d.payload });
            else if (d.kind === "broadcast" && !state.isHost) emitToHaxe("from_host", { payload: d.payload });
          };
          emitToHaxe("open", { connId: state.connId });
          flushPending();
        }
      } catch (e) {
        emitToHaxe("error", { error: String(e) });
      }
    }

    function applyHttpRelayResponse(res) {
      if (!res) return;
      if (res.connId) state.connId = String(res.connId);
      if (Array.isArray(res.events)) {
        for (const ev of res.events) handleRelayPacket(ev);
      }
    }

    function httpCall(bodyObj, cb) {
      if (!state.httpUrl) { startBroadcastFallback(); return; }
      fetch(state.httpUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(bodyObj || {})
      })
        .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
        .then(function (data) {
          applyHttpRelayResponse(data);
          if (cb) cb(data);
        })
        .catch(function () { if (!state.useBc) startBroadcastFallback(); });
    }

    function startHttpFallback() {
      if (!state.httpUrl) { startBroadcastFallback(); return; }
      if (state.useHttp) return;
      state.useHttp = true;
      httpCall({ connId: state.connId }, function () {
        if (!state.pollTimer) {
          state.pollTimer = setInterval(function () {
            if (state.pollInFlight || !state.useHttp || !state.connId) return;
            state.pollInFlight = true;
            fetch(state.httpUrl, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ connId: state.connId })
            })
              .then(function (r) { return r.json(); })
              .then(applyHttpRelayResponse)
              .catch(function () {})
              .finally(function () { state.pollInFlight = false; });
          }, 60);
        }
      });
    }

    function sendRaw(obj) {
      if (state.ws && state.ws.readyState === WebSocket.OPEN && state.welcomeReceived) {
        state.ws.send(JSON.stringify(obj));
        return;
      }
      if (state.useHttp && state.welcomeReceived) {
        httpCall(Object.assign({ connId: state.connId }, obj));
        return;
      }
      if (state.useBc && state.bc && state.welcomeReceived) {
        const msg = obj;
        if (msg.type === "host_room") {
          state.roomId = msg.roomId || ("M" + Math.floor(10000 + Math.random() * 89999));
          state.isHost = true;
          emitToHaxe("hosted", { roomId: state.roomId, connId: state.connId });
        } else if (msg.type === "join_room") {
          state.roomId = msg.roomId;
          state.isHost = false;
          emitToHaxe("joined", { roomId: state.roomId, connId: state.connId });
          state.bc.postMessage({ kind: "join", roomId: state.roomId, fromId: state.connId });
        } else if (msg.type === "relay_to_host") {
          state.bc.postMessage({ kind: "to_host", roomId: state.roomId, fromId: state.connId, payload: msg.payload });
        } else if (msg.type === "relay_to_peer") {
          state.bc.postMessage({ kind: "to_peer", roomId: state.roomId, fromId: state.connId, targetId: msg.targetId, payload: msg.payload });
        } else if (msg.type === "relay_broadcast") {
          state.bc.postMessage({ kind: "broadcast", roomId: state.roomId, fromId: state.connId, payload: msg.payload });
        }
        return;
      }
      state.pendingSends.push(obj);
    }

    return {
      handle: function (ev) {
        switch (ev.op) {
          case "connect": {
            const relayCfg = resolveRelayBase();
            if (!ev.url && relayCfg.mode === "broadcast") {
              startBroadcastFallback();
              break;
            }
            state.httpUrl = resolveHttpUrl(ev.url);
            try {
              const wsUrl = resolveWsUrl(ev.url);
              const sock = new WebSocket(wsUrl);
              state.ws = sock;
              sock.onmessage = function (m) {
                try { handleRelayPacket(JSON.parse(m.data)); } catch (_) {}
              };
              sock.onerror = function () {
                if (!state.welcomeReceived) {
                  try { sock.close(); } catch (_) {}
                  startHttpFallback();
                }
              };
              sock.onclose = function (c) {
                if (!state.welcomeReceived && !state.useHttp && !state.useBc) {
                  startHttpFallback();
                } else if (state.welcomeReceived && !state.useHttp && !state.useBc) {
                  emitToHaxe("close", { reason: c.reason || "closed" });
                }
              };
              state.fallbackTimer = setTimeout(function () {
                if (!state.welcomeReceived && !state.useHttp && !state.useBc) {
                  try { sock.close(); } catch (_) {}
                  startHttpFallback();
                }
              }, 500);
            } catch (_) {
              startHttpFallback();
            }
            break;
          }
          case "disconnect":
            stopTimers();
            if (state.ws) { try { state.ws.close(); } catch (_) {} state.ws = null; }
            if (state.bc) { try { state.bc.close(); } catch (_) {} state.bc = null; }
            relayClients.delete(id);
            break;
          case "host_room":
            sendRaw({ type: "host_room", roomId: ev.roomId || "" });
            break;
          case "join_room":
            sendRaw({ type: "join_room", roomId: ev.roomId || "" });
            break;
          case "send_to_host":
            sendRaw({ type: "relay_to_host", payload: ev.payload });
            break;
          case "send_to_peer":
            sendRaw({ type: "relay_to_peer", targetId: ev.targetId, payload: ev.payload });
            break;
          case "broadcast":
            sendRaw({ type: "relay_broadcast", payload: ev.payload });
            break;
          case "leave_room":
            sendRaw({ type: "leave_room" });
            break;
        }
      }
    };
  }

  function processOutboundEvents(dv) {
    const events = drainOutboundRing(dv);
    for (const raw of events) {
      let ev = null;
      try { ev = JSON.parse(raw); } catch (_) { continue; }
      if (!ev || !ev.type) continue;
      switch (ev.type) {
        case "audio_init":
          audioMaster = ev.master != null ? ev.master : 0.8;
          audioSfx = ev.sfx != null ? ev.sfx : 0.9;
          break;
        case "audio_beep":
          playBeep(ev.freq, ev.duration, ev.gain);
          break;
        case "audio_suspend":
          audioSuspended = true;
          if (audioCtx && audioCtx.state === "running") audioCtx.suspend().catch(function () {});
          break;
        case "audio_resume":
          audioSuspended = false;
          if (audioCtx && audioCtx.state === "suspended") audioCtx.resume().catch(function () {});
          break;
        case "save_set":
          try {
            if (window.localStorage && ev.key) window.localStorage.setItem(ev.key, ev.value);
          } catch (_) {}
          break;
        case "clipboard_copy":
          if (ev.text && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(ev.text).catch(function () {});
          }
          break;
        case "net_cmd":
          if (!relayClients.has(ev.id)) relayClients.set(ev.id, createRelayClient(ev.id));
          relayClients.get(ev.id).handle(ev);
          break;
      }
    }
  }

  // --- DOM Overlay Construction & Diff Rendering ---
  const UI_RES_TARGETS = {
    "720p (HD)": { w: 1280, h: 720, native: false },
    "1080p (FHD)": { w: 1920, h: 1080, native: false },
    "1440p (2K)": { w: 2560, h: 1440, native: false },
    "2160p (4K)": { w: 3840, h: 2160, native: false },
    "Native / Match Window": { w: 0, h: 0, native: true }
  };
  let uiRoot = null;
  let touchRoot = null;
  let currentUiScale = 1.0;
  let lastAppliedUiScaleKey = "";
  let lastRenderedSignature = "";
  let lastTouchLayerSig = "";

  function computeUiScale(st) {
    if (!st || st.appState === "IntroSequence") return 1.0;
    const resName = (st.options && st.options.gfx && st.options.gfx.uiResolution) ? st.options.gfx.uiResolution : "720p (HD)";
    const target = UI_RES_TARGETS[resName];
    if (!target || target.native) return 1.0;

    const vw = window.innerWidth || 1280;
    const vh = window.innerHeight || 720;
    const isCoarseMobile = vh < 540 || (window.matchMedia && window.matchMedia("(pointer: coarse)").matches && vh < 600);
    const rawScale = isCoarseMobile ? (720 / target.h) : Math.min(vw / target.w, vh / target.h);
    return Math.round(Math.max(0.42, Math.min(2.25, rawScale)) * 10000) / 10000;
  }

  function applyUiResolutionScale(st) {
    if (!uiRoot) uiRoot = document.getElementById("ui-root");
    if (!uiRoot) return;

    const resName = (st && st.appState !== "IntroSequence" && st.options && st.options.gfx && st.options.gfx.uiResolution)
      ? st.options.gfx.uiResolution : "Native / Match Window";
    const s = computeUiScale(st);
    const vw = window.innerWidth || 1280;
    const vh = window.innerHeight || 720;
    const key = resName + "|" + s + "|" + vw + "x" + vh;
    if (key === lastAppliedUiScaleKey) return;
    lastAppliedUiScaleKey = key;

    currentUiScale = s;
    uiRoot.setAttribute("data-ui-res", resName);
    uiRoot.style.setProperty("--ui-scale", String(s));

    if (Math.abs(s - 1.0) < 0.002) {
      uiRoot.style.width = "";
      uiRoot.style.height = "";
      uiRoot.style.transform = "";
    } else {
      uiRoot.style.width = (vw / s).toFixed(2) + "px";
      uiRoot.style.height = (vh / s).toFixed(2) + "px";
      uiRoot.style.transform = "scale(" + s + ")";
    }
  }
  let touchState = {
    active: false,
    steer: 0,
    throttle: 0,
    brake: 0,
    handbrake: false,
    boost: false,
    stickTouchId: null,
    btnTouchIds: {}
  };

  function sendUiCmd(cmdObj) {
    ensureAudioCtx();
    pushInbound(Object.assign({ type: "ui_cmd" }, cmdObj));
  }

  function ensureTouchRoot() {
    if (!touchRoot) {
      touchRoot = document.getElementById("touch-root");
      if (!touchRoot && document.body) {
        touchRoot = document.createElement("div");
        touchRoot.id = "touch-root";
        touchRoot.style.cssText = "position:fixed;inset:0;z-index:2;pointer-events:none;touch-action:none;";
        document.body.appendChild(touchRoot);
      }
    }
    return touchRoot;
  }

  function renderTouchLayer(st) {
    const tr = ensureTouchRoot();
    if (!tr) return;
    const active = Boolean(st && st.appState !== "IntroSequence" && st.uiState === "InGameHUD" && st.touchEnabled);
    const sig = active ? JSON.stringify(st.touchSettings || null) : "off";
    if (sig === lastTouchLayerSig) return;
    lastTouchLayerSig = sig;
    if (!active) {
      touchState.stickTouchId = null;
      touchState.steer = 0;
      touchState.throttle = false;
      touchState.brake = false;
      touchState.handbrake = false;
      touchState.boost = false;
      tr.innerHTML = "";
      return;
    }
    tr.innerHTML = buildTouchHtml(st.touchSettings);
    bindTouchLayerEvents();
  }

  function renderDomFromState(st) {
    if (!uiRoot) uiRoot = document.getElementById("ui-root");
    if (!uiRoot) return;
    applyUiResolutionScale(st);
    renderTouchLayer(st);

    const sig = JSON.stringify({
      appState: st.appState,
      introState: st.introState,
      introShowcaseFading: Boolean(st.introShowcaseFading),
      uiState: st.uiState,
      mapMode: st.mapMode,
      hasSavedRun: st.hasSavedRun,
      isOpenedFromPause: st.isOpenedFromPause,
      pausedByOrientation: st.pausedByOrientation,
      touchEnabled: st.touchEnabled,
      touchSettings: st.touchSettings,
      mainMenuIdx: st.mainMenuIdx,
      mapIdx: st.mapIdx,
      pauseIdx: st.pauseIdx,
      carSelect: st.carSelect,
      mp: st.mp,
      options: st.options
    });
    if (sig === lastRenderedSignature) {
      if (st.appState === "IntroSequence") {
        const stage = uiRoot.querySelector("#intro-layer .intro-stage");
        if (stage && st.introAlpha != null) {
          stage.style.opacity = String(Math.max(0.0, Math.min(1.0, st.introAlpha)));
        }
      } else if (st.uiState === "Splash") {
        const curtain = document.getElementById("intro-curtain");
        if (curtain) {
          const ca = st.introShowcaseFading && st.showcaseAlpha != null ? Math.max(0.0, Math.min(1.0, st.showcaseAlpha)) : 0.0;
          curtain.style.opacity = String(ca);
          if (ca <= 0.01) curtain.style.display = "none";
        }
      }
      return;
    }
    const activeInput = document.activeElement;
    if (activeInput && activeInput.id === "mp-code-input" && st.uiState === "MultiplayerMenu") {
      lastRenderedSignature = sig;
      return;
    }
    const prevOptScroll = uiRoot.querySelector(".opt-scroll");
    const savedScrollTop = prevOptScroll ? prevOptScroll.scrollTop : 0;
    const prevTab = uiRoot.getAttribute("data-opt-tab") || "";
    lastRenderedSignature = sig;

    if (st.minimap && st.minimap.length > 2) cachedWaypoints = st.minimap;

    // 1. Intro Sequence (Opaque #000 backdrop so slides always fade cleanly through solid black)
    if (st.appState === "IntroSequence" && st.introState !== "None") {
      const alpha = st.introAlpha != null ? Math.max(0.0, Math.min(1.0, st.introAlpha)) : 1.0;
      if (st.introState === "Studio") {
        uiRoot.innerHTML =
          '<div id="intro-layer">' +
          '<div class="intro-stage intro-studio" style="opacity:' + alpha + '">' +
          '<img class="intro-studio-img" src="./intro/jagofr-rvl-splash.webp" alt="Jagofr // RvL ROGUE" />' +
          "</div></div>";
      } else if (st.introState === "Engine") {
        uiRoot.innerHTML =
          '<div id="intro-layer">' +
          '<div class="intro-stage intro-engine" style="opacity:' + alpha + '">' +
          '<div class="engine-stack">' +
          '<div class="engine-kicker">BUILT WITH</div>' +
          '<div class="engine-hero">' +
          '<img class="engine-hero-logo" src="./intro/icons/logo_hlwgpu.svg" alt="HLWGPU" />' +
          '<img class="engine-hero-logo" src="./intro/icons/logo_webgpu.svg" alt="WebGPU" />' +
          "</div>" +
          '<div class="engine-subline">WEBGPU COMPUTE &amp; WGSL PIPELINE</div>' +
          '<div class="engine-haxe-row">' +
          '<img src="./intro/icons/logo_haxe.webp" alt="Haxe" />' +
          '<div class="engine-haxe-text"><div class="title">HAXE // ASH WASM</div><div class="sub">POWERED BY ZERO-OVERHEAD FIBERS</div></div>' +
          "</div>" +
          "</div>" +
          "</div></div>";
      } else {
        uiRoot.innerHTML =
          '<div id="intro-layer">' +
          '<div class="intro-stage intro-disclaimer" style="opacity:' + alpha + '">' +
          '<div class="disc-frame">' +
          '<span class="corner-bracket tl"></span><span class="corner-bracket tr"></span>' +
          '<span class="corner-bracket bl"></span><span class="corner-bracket br"></span>' +
          "<h2>TRADEMARK &amp; LEGAL DISCLOSURES</h2>" +
          '<div class="disc-copy">' +
          '<p>M.O.B. (Motors on Boost) is an original racing simulation prototype.<br/>' +
          'Created and developed by <strong style="color:#f4f7fb;">Gerard &quot;Jamie&quot; (Jagofr) Francis</strong>. Published by <strong style="color:#e5c07b;">RvL // ROGUE</strong>.<br/>' +
          'All custom codebases, vehicles, handling physics, tracks, and original visual assets<br/>' +
          'are the intellectual property of their respective creators. All rights reserved.</p>' +
          '<p>Haxe, hlwgpu, and Ash are open-source technologies of their respective owners.<br/>' +
          'WebGPU is a standard of the W3C GPU for the Web Community Group. Typography licensed under SIL OFL &amp; Apache 2.0.<br/>' +
          'Any vehicular likenesses or architectural references are used strictly for artistic illustration.</p>' +
          '<p>HEALTH &amp; SAFETY ADVISORY: Photosensitivity and seizure precautions apply.<br/>' +
          'Please play in a well-lit environment and take a 15-minute break for every hour of play.</p>' +
          "</div>" +
          '<div class="disc-logos">' +
          '<img src="./intro/icons/logo_haxe.webp" alt="Haxe" />' +
          '<img src="./intro/icons/logo_hlwgpu.svg" alt="hlwgpu" />' +
          '<img src="./intro/icons/logo_webgpu.svg" alt="WebGPU" />' +
          "</div>" +
          '<div class="disc-version">' + escapeHtml(st.version || "v0.8.0") + "</div>" +
          "</div>" +
          "</div></div>";
      }
      const il = document.getElementById("intro-layer");
      if (il && (st.introState === "Studio" || st.introState === "Engine")) {
        il.onclick = function () { sendUiCmd({ cmd: "skip_intro" }); };
      }
      return;
    }

    // 2. Splash Screen (smooth black-curtain reveal into 3D rotating showcase car)
    if (st.uiState === "Splash") {
      const ca = st.introShowcaseFading && st.showcaseAlpha != null ? Math.max(0.0, Math.min(1.0, st.showcaseAlpha)) : 0.0;
      const curtainHtml = ca > 0.01 ? '<div id="intro-curtain" style="opacity:' + ca + '"></div>' : "";
      uiRoot.innerHTML =
        '<div id="splash-layer">' +
        '<div class="splash-banner">' +
        '<span class="corner-bracket tl"></span><span class="corner-bracket tr"></span>' +
        '<span class="corner-bracket bl"></span><span class="corner-bracket br"></span>' +
        "<h1>M.O.B. // MOTORS ON BOOST</h1>" +
        '<div class="tagline">HIGH-VELOCITY ARCADE RACING &amp; PHYSICS SIMULATION</div>' +
        "</div>" +
        '<div class="splash-bottom">' +
        '<button id="btn-splash-enter" class="splash-prompt interactive">PRESS ANY BUTTON OR CLICK TO ENTER</button>' +
        '<div class="splash-ver">' + escapeHtml(st.version || "v0.8.0") + "</div>" +
        "</div>" +
        "</div>" +
        curtainHtml;
      document.getElementById("splash-layer").onclick = function () {
        sendUiCmd({ cmd: "splash_continue" });
      };
      return;
    }

    // 3. In-Game HUD (virtual touch controls live separately in #touch-root so HUD state diffs never drop live touches)
    if (st.uiState === "InGameHUD") {
      uiRoot.innerHTML =
        '<div id="hud-layer" class="' + (st.touchEnabled ? "hud-with-touch" : "") + '">' +
        '<div class="hud-top-left">' +
        '<canvas id="hud-minimap" width="132" height="110"></canvas>' +
        "</div>" +
        '<div class="hud-top-right">' +
        '<div class="hud-fps-pill" id="hud-map-fps">' + escapeHtml(st.mapMode) + " | " + Math.round(telemetry.fps) + " FPS</div>" +
        '<button id="btn-hud-pause" aria-label="Pause">&#10074;&#10074;</button>' +
        "</div>" +
        '<div class="hud-tach-cluster">' +
        '<div class="tach-row">' +
        '<div><span class="hud-speed" id="hud-speed-val">0</span> <span class="hud-unit">KM/H</span></div>' +
        '<div class="hud-gear" id="hud-gear-val">1</div>' +
        "</div>" +
        '<div class="hud-bar-track"><div class="hud-bar-fill-rpm" id="hud-rpm-fill"></div></div>' +
        '<div class="hud-bar-track"><div class="hud-bar-fill-nitro" id="hud-nitro-fill"></div></div>' +
        "</div>" +
        "</div>";

      document.getElementById("btn-hud-pause").onclick = function () {
        sendUiCmd({ cmd: "action", action: "PauseGame" });
      };
      drawMinimap();
      updateLiveHudNodes();
      return;
    }

    // 4. Glassmorphic Menu Cards
    let cardInner = "";
    if (st.uiState === "MainMenu") {
      const items = [
        { label: st.hasSavedRun ? "NEW GAME / SELECT MAP" : "PLAY SINGLEPLAYER", action: "OpenMapSelect", primary: !st.hasSavedRun, disabled: false },
        { label: st.hasSavedRun ? "CONTINUE RUN" : "RESUME SAVED RACE", action: "ResumeGame", primary: Boolean(st.hasSavedRun), disabled: !st.hasSavedRun },
        { label: "MULTIPLAYER LOBBY", action: "OpenMultiplayer", primary: false, disabled: false },
        { label: "OPTIONS", action: "OpenOptions", primary: false, disabled: false },
        { label: "CREDITS", action: "OpenCredits", primary: false, disabled: false },
        { label: "EXIT TO SPLASH", action: "QuitToTitle", primary: false, disabled: false }
      ];

      cardInner =
        '<div class="menu-header"><h2>MAIN MENU</h2><span class="sub">' + escapeHtml(st.version || "v0.8.0") + "</span></div>" +
        '<div class="menu-list">' +
        items.map(function (it, idx) {
          const cls = "mob-btn" + (idx === st.mainMenuIdx ? " selected" : "") + (it.primary ? " mob-btn-primary" : "") + (it.disabled ? " disabled" : "");
          return '<button class="' + cls + '" data-menu-idx="' + idx + '" data-action="' + it.action + '"' + (it.disabled ? ' disabled aria-disabled="true"' : "") + '><span>' + it.label + '</span><span>&rsaquo;</span></button>';
        }).join("") +
        "</div>";
    } else if (st.uiState === "MapSelect") {
      cardInner =
        '<div class="menu-header"><h2>SINGLEPLAYER // SELECT MAP</h2><span class="sub">CHOOSE DRIVING ENVIRONMENT</span></div>' +
        '<div class="card-grid">' +
        '<div class="map-card' + (st.mapIdx === 0 ? " selected" : "") + '" id="card-map-circuit" tabindex="0">' +
        '<div class="tag">CIRCUIT RACE | TRAFFIC AI | 3 LAPS</div><h3>HIGHWAY CIRCUIT</h3>' +
        "<p>High-speed 4-lane highway loop with street lights, guardrails, and two-way traffic.</p></div>" +
        '<div class="map-card' + (st.mapIdx === 1 ? " selected" : "") + '" id="card-map-sandbox" tabindex="0">' +
        '<div class="tag">FREE ROAM | 400m x 400m | STUNT TERRAIN</div><h3>SANDBOX PROVING GROUNDS</h3>' +
        "<p>Open proving grounds with cyber-grid hills, 12.5m mountain pass, and stunt ramps.</p></div>" +
        "</div>" +
        '<div class="menu-footer">' +
        '<button class="mob-btn-secondary" id="btn-map-back">BACK</button>' +
        "</div>";
    } else if (st.uiState === "CarSelect") {
      const cs = st.carSelect || {};
      const cars = cs.cars || [];
      const colors = cs.colors || [];
      const curColor = colors[cs.colorIdx] || { name: "Apex Orange", cssHex: "#E64A19" };
      const targetLabel = cs.mapMode === "Sandbox" ? "SANDBOX PROVING GROUNDS" : "HIGHWAY CIRCUIT";
      cardInner =
        '<header class="menu-header"><h2>GARAGE // SELECT VEHICLE</h2><span class="sub">' + escapeHtml(targetLabel) + "</span></header>" +
        '<div class="car-grid" role="radiogroup" aria-label="Vehicle Archetype">' +
        cars.map(function (c, i) {
          const isSel = (i === cs.carIdx);
          return (
            '<article class="car-card-wrap' + (isSel ? " selected" : "") + (isSel && cs.focusRow === 0 ? " key-focus" : "") + '">' +
            '<button type="button" class="car-card" id="card-car-' + escapeHtml(c.id) + '" data-car-idx="' + i + '" role="radio" aria-checked="' + (isSel ? "true" : "false") + '">' +
            '<span class="car-swatch-bar" style="background:' + (isSel ? escapeHtml(curColor.cssHex) : "rgba(0,229,255,0.28)") + '"></span>' +
            '<span class="car-top-row"><span class="tag">' + escapeHtml(c.drivetrain) + '</span><span class="car-turn-badge">TURN ' + c.turnRadiusM + "m</span></span>" +
            "<h3>" + escapeHtml(c.name) + "</h3>" +
            '<p class="car-desc">' + escapeHtml(c.desc) + "</p>" +
            '<span class="car-specs"><span>TOP ' + c.topSpeedKmh + " KM/H</span><span>" + c.weightKg + " KG</span></span>" +
            "</button></article>"
          );
        }).join("") +
        "</div>" +
        '<div class="car-paint-row' + (cs.focusRow === 1 ? " key-focus" : "") + '" role="radiogroup" aria-label="Vehicle Paint Color">' +
        '<span class="car-paint-label">PAINT: <strong>' + escapeHtml(curColor.name) + "</strong></span>" +
        '<div class="car-swatches">' +
        colors.map(function (sw, i) {
          const isSel = (i === cs.colorIdx);
          return (
            '<button type="button" class="paint-swatch' + (isSel ? " selected" : "") + '" data-color-idx="' + i + '" ' +
            'role="radio" aria-checked="' + (isSel ? "true" : "false") + '" aria-label="Paint ' + escapeHtml(sw.name) + '" ' +
            'style="background:' + escapeHtml(sw.cssHex) + ';"></button>'
          );
        }).join("") +
        "</div></div>" +
        '<footer class="menu-footer car-footer">' +
        '<button type="button" class="mob-btn-secondary" id="btn-car-back">&lt; BACK TO MAPS</button>' +
        '<button type="button" class="mob-btn-primary car-launch-btn" id="btn-car-launch">DRIVE ' + escapeHtml(cs.mapMode === "Sandbox" ? "SANDBOX" : "CIRCUIT") + " &rsaquo;</button>" +
        "</footer>";
    } else if (st.uiState === "PauseMenu") {
      const pItems = [
        { label: "RESUME SESSION", action: "ResumeGame" },
        { label: "RESTART MAP", action: "RestartRace" },
        { label: "OPTIONS", action: "OpenOptions" },
        { label: "MAIN MENU", action: "QuitToTitle" }
      ];
      cardInner =
        '<div class="menu-header"><h2>PAUSED</h2><span class="sub">' + escapeHtml(st.mapMode) + "</span></div>" +
        '<div class="menu-list">' +
        pItems.map(function (it, idx) {
          const cls = "mob-btn" + (idx === st.pauseIdx ? " selected" : "");
          return '<button class="' + cls + '" data-action="' + it.action + '"><span>' + it.label + '</span><span>&rsaquo;</span></button>';
        }).join("") +
        "</div>";
    } else if (st.uiState === "MultiplayerMenu") {
      const mpObj = st.mp || {};
      const code = mpObj.enteredCode ? mpObj.enteredCode : "";
      const mIdx = mpObj.menuIdx != null ? mpObj.menuIdx : 0;
      cardInner =
        '<div class="menu-header"><h2>MULTIPLAYER // HOST OR JOIN</h2><span class="sub">PEER-TO-PEER LOBBY</span></div>' +
        '<div class="card-grid">' +
        '<div class="map-card' + (mIdx === 0 ? " selected" : "") + '" id="card-mp-host">' +
        '<div class="tag">CREATE MATCH</div><h3>HOST A MATCH</h3>' +
        "<p>Run authoritative host validation for Highway Circuit or Sandbox Proving Grounds and share a 6-character invite link.</p>" +
        '<div style="display:flex;gap:8px;margin-top:12px;">' +
        '<button class="mob-btn-secondary" id="btn-mp-host-circuit">HOST CIRCUIT</button>' +
        '<button class="mob-btn-secondary" id="btn-mp-host-sandbox">HOST SANDBOX</button>' +
        "</div></div>" +
        '<div class="map-card' + (mIdx === 1 ? " selected" : "") + '" id="card-mp-join">' +
        '<div class="tag">ENTER CODE</div><h3>JOIN BY INVITE CODE</h3>' +
        "<p>Enter a 6-character room code or paste a ?room= invite URL from your host.</p>" +
        '<div class="mp-input-row">' +
        '<input id="mp-code-input" class="mp-input" maxlength="16" placeholder="ABC123" value="' + escapeHtml(code) + '" />' +
        '<button class="mob-btn-secondary" id="btn-mp-join">JOIN</button>' +
        "</div></div>" +
        "</div>" +
        '<div class="menu-footer"><button class="mob-btn-secondary" id="btn-mp-back">BACK</button></div>';
    } else if (st.uiState === "MultiplayerLobby") {
      const mp = st.mp || {};
      const peers = mp.peers || [];
      const isHost = mp.role === "Host";
      const curMap = mp.selectedMap || "Circuit";
      cardInner =
        '<div class="menu-header"><h2>MULTIPLAYER LOBBY</h2><span class="sub">' + escapeHtml(mp.status || "Connecting") + "</span></div>" +
        '<div class="mp-room-banner">' +
        '<div><div style="font-size:11px;color:var(--text-dim);">ROOM INVITE CODE | MAP: <strong style="color:var(--gold);">' + escapeHtml(curMap.toUpperCase()) + '</strong></div><div class="mp-room-code">' + escapeHtml(mp.roomId || "...") + "</div></div>" +
        '<button class="mob-btn-secondary" id="btn-mp-copy">COPY INVITE LINK</button>' +
        "</div>" +
        '<div class="peer-list">' +
        (peers.length === 0
          ? '<div class="peer-row"><span>Waiting for players to connect...</span></div>'
          : peers.map(function (p) {
              return '<div class="peer-row"><span>Slot ' + (p.slot + 1) + ": " + escapeHtml(p.name) + (p.isHost ? " [HOST]" : "") + '</span><span style="color:var(--cyan);">' + (p.ready ? "READY" : "WAIT") + "</span></div>";
            }).join("")) +
        "</div>" +
        '<div class="menu-footer">' +
        '<button class="mob-btn-secondary" id="btn-mp-leave">LEAVE ROOM</button>' +
        (isHost
          ? '<div style="display:flex;gap:8px;">' +
            '<button class="mob-btn-secondary" id="btn-mp-map-toggle">MAP: ' + escapeHtml(curMap) + "</button>" +
            '<button class="mob-btn-secondary" style="border-color:var(--cyan);" id="btn-mp-start">START MATCH</button></div>'
          : '<span style="color:var(--text-dim);font-size:13px;">Waiting for host to launch (' + escapeHtml(curMap) + ')...</span>') +
        "</div>";
    } else if (st.uiState === "OptionsMenu") {
      cardInner = buildOptionsHtml(st);
    } else if (st.uiState === "CreditsScreen") {
      cardInner =
        '<div class="menu-header"><h2>M.O.B. // MOTORS ON BOOST</h2><span class="sub">CREDITS</span></div>' +
        '<div class="credits-body">' +
        '<div class="credits-section-label">LEAD ARCHITECT &amp; TECHNICAL DESIGNER</div>' +
        '<div class="credits-value-cyan">Gerard &quot;Jamie&quot; (Jagofr) Francis</div>' +
        '<div class="credits-section-label">PUBLISHED &amp; DEVELOPED IN-HOUSE BY</div>' +
        '<div class="credits-value-gold">RvL // ROGUE</div>' +
        '<div class="credits-section-label">AI ENGINEERING COLLABORATION</div>' +
        '<div class="credits-value-green">Google Gemini</div>' +
        '<div class="credits-tech">' +
        "Built with Haxe, <code>hlwgpu</code> (Hardware-Accelerated WebGPU &amp; Compute Shaders) &amp; OimoPhysics<br/>" +
        "Typography: Stack Sans Headline &amp; Material Symbols Rounded<br/>" +
        "Homage &amp; Inspiration: Need for Speed: Most Wanted (2005) &amp; Burnout Revenge (2005)<br/><br/>" +
        "<strong style=\"color:#f4f7fb;\">Thank you for playing!</strong><br/>" +
        '<span style="color:#e5c07b;">' + escapeHtml(st.version || "v0.8.0") + "</span>" +
        "</div>" +
        "</div>" +
        '<div class="menu-footer"><button class="mob-btn-secondary" id="btn-cred-back">&lt; BACK TO MAIN MENU</button></div>';
    }

    uiRoot.innerHTML = '<div id="menu-shell"><div class="menu-card">' + cardInner + "</div></div>";
    if (st.uiState === "OptionsMenu" && st.options) {
      uiRoot.setAttribute("data-opt-tab", st.options.tab || "");
      const scrollBox = uiRoot.querySelector(".opt-scroll");
      if (scrollBox) {
        if (prevTab === (st.options.tab || "")) scrollBox.scrollTop = savedScrollTop;
        const sel = scrollBox.querySelector(".opt-row.selected");
        if (sel && sel.scrollIntoView) sel.scrollIntoView({ block: "nearest", inline: "nearest" });
      }
    } else {
      uiRoot.removeAttribute("data-opt-tab");
    }
    bindMenuCardEvents(st);
  }

  function buildOptionsHtml(st) {
    const opt = st.options || { tab: "Graphics" };
    const tabs = ["Graphics", "Audio", "Keyboard", "Gamepad", "Touch"];
    let rowsHtml = "";

    if (opt.tab === "Graphics" && opt.gfx) {
      const g = opt.gfx;
      const gDisabled = opt.gfxDisabled || [];
      const gLocked = opt.gfxLocked || [];
      const gRows = [
        ["Texture Fidelity", g.textures],
        ["Shadow Quality", g.shadowLevel],
        ["Shadow Buffer", g.shadowRes + " px"],
        ["Lighting Pipeline", g.lightingLevel],
        ["Light Buffer", g.lightingRes + " px"],
        ["Mipmapping Filters", g.mipmapping ? "Enabled" : "Disabled"],
        ["Anisotropy Sampling", g.anisotropic + "x"],
        ["Anti-Aliasing Pass", g.aaType],
        ["AA Quality", formatAAQualityLabel(g.aaType, g.aaLevel)],
        ["Model Geometry LOD", g.modelGeometry],
        ["Screen Reflections", g.modelReflections ? "Active" : "Disabled"],
        ["Reflection Updates", g.reflectionLevel],
        ["3D Render Resolution", g.renderScale + "x (" + Math.round(g.renderScale * 100) + "%)"],
        ["UI Interface Target", g.uiResolution]
      ];
      rowsHtml = gRows.map(function (r, i) {
        return buildStepperRow(i, r[0], r[1], i === opt.gfxIdx, Boolean(gDisabled[i]), Boolean(gLocked[i]));
      }).join("");
    } else if (opt.tab === "Audio" && opt.audio) {
      const a = opt.audio;
      const aRows = [
        ["Master Volume", Math.round(a.master * 100) + "%"],
        ["Music Volume", Math.round(a.music * 100) + "%"],
        ["SFX Volume", Math.round(a.sfx * 100) + "%"]
      ];
      rowsHtml = aRows.map(function (r, i) {
        return buildStepperRow(i, r[0], r[1], i === opt.audioIdx, false, false);
      }).join("");
    } else if (opt.tab === "Touch") {
      const ts = st.touchSettings || {};
      const sensPct = Math.round((opt.steerSens != null ? opt.steerSens : 0.8) * 100);
      const tRows = [
        ["Joystick X Offset", fmtSignedPx(ts.stickOffsetX)],
        ["Joystick Y Offset", fmtSignedPx(ts.stickOffsetY)],
        ["Nitro Btn X Offset", fmtSignedPx(ts.nitroOffsetX)],
        ["Nitro Btn Y Offset", fmtSignedPx(ts.nitroOffsetY)],
        ["Gas Pedal X Offset", fmtSignedPx(ts.gasOffsetX)],
        ["Gas Pedal Y Offset", fmtSignedPx(ts.gasOffsetY)],
        ["Brake Disc X Offset", fmtSignedPx(ts.brakeOffsetX)],
        ["Brake Disc Y Offset", fmtSignedPx(ts.brakeOffsetY)],
        ["Handbrake X Offset", fmtSignedPx(ts.driftOffsetX)],
        ["Handbrake Y Offset", fmtSignedPx(ts.driftOffsetY)],
        ["Touch HUD Scale", Math.round((ts.scale || 1) * 100) + "%"]
      ];
      rowsHtml =
        '<div class="touch-toolbar">' +
        '<button class="mob-btn-secondary" id="btn-touch-custom">MODE: ' + escapeHtml(ts.mode || "Default") + "</button>" +
        '<button class="mob-btn-secondary" id="btn-touch-reset">RESET TOUCH DEFAULTS</button>' +
        "</div>" +
        buildTouchPreviewPadHtml(ts, opt.ctrlIdx) +
        buildSensitivityRowHtml(sensPct) +
        tRows.map(function (r, i) { return buildStepperRow(i, r[0], r[1], i === opt.ctrlIdx, false, false); }).join("");
    } else {
      const isGamepad = opt.tab === "Gamepad";
      const b = opt.bindings || {};
      const sensPct = Math.round((opt.steerSens != null ? opt.steerSens : 0.8) * 100);
      const isListening = Boolean(opt.listening);
      const actNames = ["Throttle", "Brake", "SteerLeft", "SteerRight", "Handbrake", "Boost"];
      const cRows = isGamepad ? [
        { label: "Throttle (Gas)", val: b.padThrottle || "RT", canRemap: true },
        { label: "Brake / Reverse", val: b.padBrake || "LT", canRemap: true },
        { label: "Steer Left", val: "Left Analog / D-Pad", canRemap: false },
        { label: "Steer Right", val: "Left Analog / D-Pad", canRemap: false },
        { label: "Handbrake (Drift)", val: b.padHandbrake || "B (Right)", canRemap: true },
        { label: "Nitro Boost", val: b.padBoost || "LB", canRemap: true }
      ] : [
        { label: "Throttle (Gas)", val: b.throttle || "W", canRemap: true },
        { label: "Brake / Reverse", val: b.brake || "S", canRemap: true },
        { label: "Steer Left", val: b.steerLeft || "A", canRemap: true },
        { label: "Steer Right", val: b.steerRight || "D", canRemap: true },
        { label: "Handbrake (Drift)", val: b.handbrake || "SPACE", canRemap: true },
        { label: "Nitro Boost", val: b.boost || "L-SHIFT", canRemap: true }
      ];

      rowsHtml =
        '<div class="touch-toolbar">' +
        '<button class="mob-btn-secondary" id="btn-dev-toggle">INPUT MODE: ' + escapeHtml(opt.device || "Both") + "</button>" +
        (isGamepad
          ? '<span style="font-size:12px;color:' + (opt.gamepadConnected ? "#00e676" : "var(--text-dim)") + ';">' + (opt.gamepadConnected ? "CONTROLLER CONNECTED" : "NO CONTROLLER DETECTED") + "</span>"
          : "") +
        '<button class="mob-btn-secondary" data-remap-row="6">RESET TO DEFAULTS</button>' +
        "</div>" +
        (isListening
          ? '<div class="remap-listen-banner">PRESS ANY ' + (isGamepad ? "CONTROLLER BUTTON" : "KEY") + " TO BIND " + escapeHtml(opt.listeningAction || "ACTION") + " (ESC / START TO CANCEL)</div>"
          : "") +
        buildSensitivityRowHtml(sensPct) +
        cRows.map(function (r, i) {
          const isThisListening = isListening && opt.listeningAction === actNames[i];
          const isSel = opt.ctrlViewMode === "Custom" && i === opt.ctrlIdx;
          return (
            '<div class="opt-row' + (isSel ? " selected" : "") + '">' +
            '<span class="label">' + escapeHtml(r.label) + "</span>" +
            '<div class="opt-controls">' +
            '<span class="opt-val">' + escapeHtml(isThisListening ? "WAITING..." : r.val) + "</span>" +
            (r.canRemap
              ? '<button class="opt-remap-btn' + (isThisListening ? " listening" : "") + '" data-remap-row="' + i + '">' + (isThisListening ? "LISTENING" : "REMAP") + "</button>"
              : '<button class="opt-remap-btn" disabled>FIXED AXIS</button>') +
            "</div></div>"
          );
        }).join("");
    }

    return (
      '<div class="menu-header"><h2>OPTIONS</h2><span class="sub">' + escapeHtml(opt.tab) + "</span></div>" +
      '<div class="opt-tabs" role="tablist" aria-label="Options Categories">' +
      tabs.map(function (t) {
        const isAct = opt.tab === t;
        return '<button class="opt-tab' + (isAct ? " active" : "") + '" role="tab" aria-selected="' + (isAct ? "true" : "false") + '" data-tab="' + t + '">' + t.toUpperCase() + "</button>";
      }).join("") +
      "</div>" +
      '<div class="opt-scroll">' + rowsHtml + "</div>" +
      '<div class="menu-footer"><button class="mob-btn-secondary" id="btn-opt-back">BACK</button></div>'
    );
  }

  function formatAAQualityLabel(aaType, aaLevel) {
    if (aaType === "MSAA") return "4x (Fixed)";
    if (aaType === "FXAA" || aaType === "SMAA") {
      return aaLevel === 2 ? "Low" : (aaLevel === 8 ? "High" : "Medium");
    }
    if (aaType === "TSAA") {
      return aaLevel === 2 ? "8x" : (aaLevel === 8 ? "32x" : "16x");
    }
    return String(aaLevel) + "x";
  }

  function fmtSignedPx(v) {
    const n = Math.round(v || 0);
    return (n > 0 ? "+" : "") + n + " px";
  }

  function buildSensitivityRowHtml(sensPct) {
    return (
      '<div class="opt-row">' +
      '<span class="label">Steering Sensitivity</span>' +
      '<div class="opt-controls">' +
      '<button class="opt-step-btn" data-sens-dir="-1" aria-label="Decrease Steering Sensitivity">&minus;</button>' +
      '<span class="opt-val">' + sensPct + "%</span>" +
      '<button class="opt-step-btn" data-sens-dir="1" aria-label="Increase Steering Sensitivity">+</button>' +
      "</div>" +
      "</div>"
    );
  }

  function buildTouchPreviewPadHtml(ts, ctrlIdx) {
    const s = Math.max(0.5, Math.min(1.5, ts.scale || 1.0));
    const scaleRatio = 0.22;
    const nodes = [
      { id: "stick", label: "STICK", baseX: 20, baseY: 72, ox: ts.stickOffsetX || 0, oy: ts.stickOffsetY || 0, active: ctrlIdx === 0 || ctrlIdx === 1 },
      { id: "nitro", label: "NOS", baseX: 82, baseY: 38, ox: ts.nitroOffsetX || 0, oy: ts.nitroOffsetY || 0, active: ctrlIdx === 2 || ctrlIdx === 3 },
      { id: "gas", label: "GAS", baseX: 84, baseY: 74, ox: ts.gasOffsetX || 0, oy: ts.gasOffsetY || 0, active: ctrlIdx === 4 || ctrlIdx === 5 },
      { id: "brake", label: "BRK", baseX: 68, baseY: 74, ox: ts.brakeOffsetX || 0, oy: ts.brakeOffsetY || 0, active: ctrlIdx === 6 || ctrlIdx === 7 },
      { id: "drift", label: "DRF", baseX: 68, baseY: 38, ox: ts.driftOffsetX || 0, oy: ts.driftOffsetY || 0, active: ctrlIdx === 8 || ctrlIdx === 9 }
    ];
    return (
      '<div class="touch-preview-pad" id="touch-preview-pad">' +
      '<div class="touch-preview-hint">DRAG OR USE STEPPERS BELOW TO REPOSITION VIRTUAL CONTROLS</div>' +
      nodes.map(function (n) {
        const dx = Math.round(n.ox * scaleRatio);
        const dy = Math.round(n.oy * scaleRatio);
        return (
          '<div class="touch-preview-node' + (n.active ? " active-part" : "") + '" data-touch-part="' + n.id + '"' +
          ' data-ox="' + Math.round(n.ox) + '" data-oy="' + Math.round(n.oy) + '"' +
          ' style="left:calc(' + n.baseX + "% + " + dx + 'px);top:calc(' + n.baseY + "% + " + dy + 'px);transform:scale(' + (0.7 + s * 0.3) + ');">' +
          n.label + "</div>"
        );
      }).join("") +
      "</div>"
    );
  }

  function buildStepperRow(idx, label, value, selected, disabled, locked) {
    const disAttr = (disabled || locked) ? ' disabled aria-disabled="true"' : "";
    const lockTag = locked ? '<span class="opt-badge-lock">MENU ONLY</span>' : "";
    const valDisplay = disabled ? "[DISABLED]" : String(value);
    return (
      '<div class="opt-row' + (selected ? " selected" : "") + (disabled ? " disabled" : "") + (locked ? " locked" : "") + '" data-opt-row="' + idx + '">' +
      '<span class="label">' + escapeHtml(label) + lockTag + "</span>" +
      '<div class="opt-controls">' +
      '<button class="opt-step-btn" data-step-row="' + idx + '" data-step-dir="-1"' + disAttr + ' aria-label="Decrease ' + escapeHtml(label) + '">&minus;</button>' +
      '<span class="opt-val">' + escapeHtml(valDisplay) + "</span>" +
      '<button class="opt-step-btn" data-step-row="' + idx + '" data-step-dir="1"' + disAttr + ' aria-label="Increase ' + escapeHtml(label) + '">+</button>' +
      "</div>" +
      "</div>"
    );
  }

  function bindMenuCardEvents(st) {
    uiRoot.querySelectorAll("[data-action]").forEach(function (el) {
      el.onclick = function () {
        if (el.disabled) return;
        sendUiCmd({ cmd: "action", action: el.getAttribute("data-action") });
      };
    });
    const circuit = document.getElementById("card-map-circuit");
    if (circuit) circuit.onclick = function () { sendUiCmd({ cmd: "action", action: "StartGame" }); };
    const sandbox = document.getElementById("card-map-sandbox");
    if (sandbox) sandbox.onclick = function () { sendUiCmd({ cmd: "action", action: "StartSandbox" }); };

    ["btn-map-back", "btn-car-back", "btn-mp-back", "btn-opt-back", "btn-cred-back"].forEach(function (id) {
      const b = document.getElementById(id);
      if (b) {
        b.onclick = function () {
          sendUiCmd({ cmd: "ui_back" });
        };
      }
    });

    uiRoot.querySelectorAll("[data-car-idx]").forEach(function (el) {
      const idx = parseInt(el.getAttribute("data-car-idx"), 10);
      el.onclick = function () { sendUiCmd({ cmd: "car_select_pick", idx: idx }); };
      el.ondblclick = function () { sendUiCmd({ cmd: "car_select_pick", idx: idx, launch: true }); };
    });
    uiRoot.querySelectorAll("[data-color-idx]").forEach(function (el) {
      el.onclick = function () {
        sendUiCmd({ cmd: "car_select_color", idx: parseInt(el.getAttribute("data-color-idx"), 10) });
      };
    });
    const carLaunch = document.getElementById("btn-car-launch");
    if (carLaunch) carLaunch.onclick = function () { sendUiCmd({ cmd: "car_select_launch" }); };

    const hc = document.getElementById("btn-mp-host-circuit");
    if (hc) hc.onclick = function () { sendUiCmd({ cmd: "mp_host", mapIndex: 0 }); };
    const hs = document.getElementById("btn-mp-host-sandbox");
    if (hs) hs.onclick = function () { sendUiCmd({ cmd: "mp_host", mapIndex: 1 }); };
    const codeIn = document.getElementById("mp-code-input");
    if (codeIn) {
      codeIn.oninput = function () { sendUiCmd({ cmd: "mp_set_code", code: codeIn.value }); };
    }
    const jb = document.getElementById("btn-mp-join");
    if (jb) jb.onclick = function () { sendUiCmd({ cmd: "mp_join", code: codeIn ? codeIn.value : "" }); };
    const cp = document.getElementById("btn-mp-copy");
    if (cp) cp.onclick = function () { sendUiCmd({ cmd: "mp_copy_invite" }); };
    const lv = document.getElementById("btn-mp-leave");
    if (lv) lv.onclick = function () { sendUiCmd({ cmd: "mp_leave" }); };
    const mt = document.getElementById("btn-mp-map-toggle");
    if (mt) {
      mt.onclick = function () {
        const nextMap = st.mp && st.mp.selectedMap === "Circuit" ? "Sandbox" : "Circuit";
        sendUiCmd({ cmd: "mp_select_map", map: nextMap });
      };
    }
    const ms = document.getElementById("btn-mp-start");
    if (ms) ms.onclick = function () { sendUiCmd({ cmd: "mp_start_match" }); };

    uiRoot.querySelectorAll("[data-tab]").forEach(function (el) {
      el.onclick = function () { sendUiCmd({ cmd: "options_tab", tab: el.getAttribute("data-tab") }); };
    });
    uiRoot.querySelectorAll("[data-step-row]").forEach(function (el) {
      el.onclick = function () {
        if (el.disabled) return;
        sendUiCmd({
          cmd: "options_step",
          row: parseInt(el.getAttribute("data-step-row"), 10),
          dir: parseInt(el.getAttribute("data-step-dir"), 10)
        });
      };
    });
    uiRoot.querySelectorAll("[data-sens-dir]").forEach(function (el) {
      el.onclick = function () {
        sendUiCmd({ cmd: "controls_sensitivity", dir: parseInt(el.getAttribute("data-sens-dir"), 10) });
      };
    });
    uiRoot.querySelectorAll("[data-remap-row]").forEach(function (el) {
      el.onclick = function () {
        if (el.disabled) return;
        sendUiCmd({ cmd: "controls_remap", row: parseInt(el.getAttribute("data-remap-row"), 10) });
      };
    });
    const tc = document.getElementById("btn-touch-custom");
    if (tc) tc.onclick = function () { sendUiCmd({ cmd: "touch_toggle_custom" }); };
    const tr = document.getElementById("btn-touch-reset");
    if (tr) tr.onclick = function () { sendUiCmd({ cmd: "touch_reset_defaults" }); };
    const dtBtn = document.getElementById("btn-dev-toggle");
    if (dtBtn) dtBtn.onclick = function () { sendUiCmd({ cmd: "controls_toggle_device" }); };

    // Interactive Touch/Pointer drag & nudge on preview pad
    uiRoot.querySelectorAll(".touch-preview-node").forEach(function (node) {
      let startX = 0, startY = 0, baseOx = 0, baseOy = 0, dragging = false;
      node.onpointerdown = function (e) {
        dragging = true;
        startX = e.clientX;
        startY = e.clientY;
        baseOx = parseFloat(node.getAttribute("data-ox")) || 0;
        baseOy = parseFloat(node.getAttribute("data-oy")) || 0;
        if (node.setPointerCapture) node.setPointerCapture(e.pointerId);
      };
      node.onpointermove = function (e) {
        if (!dragging) return;
        const dragScale = 0.22 * (currentUiScale || 1.0);
        const dx = Math.round((e.clientX - startX) / dragScale);
        const dy = Math.round((e.clientY - startY) / dragScale);
        const nx = Math.max(-100, Math.min(100, Math.round((baseOx + dx) / 10) * 10));
        const ny = Math.max(-100, Math.min(100, Math.round((baseOy + dy) / 10) * 10));
        sendUiCmd({ cmd: "touch_set_offset", part: node.getAttribute("data-touch-part"), x: nx, y: ny });
      };
      const endDrag = function () { dragging = false; };
      node.onpointerup = endDrag;
      node.onpointercancel = endDrag;
    });
  }

  function buildTouchHtml(ts) {
    const s = (ts && ts.scale) || 1.0;
    const isCustom = ts && ts.mode === "Custom";
    const ox = function (v) { return isCustom ? v || 0 : 0; };
    const oy = function (v) { return isCustom ? v || 0 : 0; };

    return (
      '<div id="touch-layer">' +
      '<div class="touch-stick-base" id="touch-stick-zone" style="transform:scale(' + s + ") translate(" + ox(ts && ts.stickOffsetX) + "px," + oy(ts && ts.stickOffsetY) + 'px)"><div class="touch-stick-knob" id="touch-stick-knob"></div></div>' +
      '<div class="touch-action-btn" id="touch-btn-gas" style="transform:scale(' + s + ") translate(" + ox(ts && ts.gasOffsetX) + "px," + oy(ts && ts.gasOffsetY) + 'px)"><img src="./icons/gas-pedal.png" alt="" /><span>GAS</span></div>' +
      '<div class="touch-action-btn" id="touch-btn-brake" style="transform:scale(' + s + ") translate(" + ox(ts && ts.brakeOffsetX) + "px," + oy(ts && ts.brakeOffsetY) + 'px)"><img src="./icons/brake.png" alt="" /><span>BRK</span></div>' +
      '<div class="touch-action-btn" id="touch-btn-drift" style="transform:scale(' + s + ") translate(" + ox(ts && ts.driftOffsetX) + "px," + oy(ts && ts.driftOffsetY) + 'px)"><img src="./icons/hand-brake.png" alt="" /><span>DRIFT</span></div>' +
      '<div class="touch-action-btn" id="touch-btn-nitro" style="transform:scale(' + s + ") translate(" + ox(ts && ts.nitroOffsetX) + "px," + oy(ts && ts.nitroOffsetY) + 'px)"><img src="./icons/burn.png" alt="" /><span>NOS</span></div>' +
      "</div>"
    );
  }

  function bindTouchLayerEvents() {
    const stickZone = document.getElementById("touch-stick-zone");
    const stickKnob = document.getElementById("touch-stick-knob");
    if (stickZone) {
      const updateStick = function (clientX) {
        const rect = stickZone.getBoundingClientRect();
        const cx = rect.left + rect.width * 0.5;
        const maxR = Math.max(24, rect.width * 0.38);
        const norm = Math.max(-1, Math.min(1, (clientX - cx) / maxR));
        const localR = Math.max(24, (stickZone.offsetWidth || 128) * 0.38);
        touchState.active = true;
        touchState.steer = norm;
        if (stickKnob) stickKnob.style.transform = "translateX(" + (norm * localR * 0.75) + "px)";
      };
      stickZone.onpointerdown = function (e) {
        try { stickZone.setPointerCapture(e.pointerId); } catch (_) {}
        touchState.stickTouchId = e.pointerId;
        updateStick(e.clientX);
      };
      stickZone.onpointermove = function (e) {
        if (touchState.stickTouchId === e.pointerId) updateStick(e.clientX);
      };
      const releaseStick = function (e) {
        if (touchState.stickTouchId === e.pointerId) {
          touchState.stickTouchId = null;
          touchState.steer = 0;
          if (stickKnob) stickKnob.style.transform = "translateX(0px)";
        }
      };
      stickZone.onpointerup = releaseStick;
      stickZone.onpointercancel = releaseStick;
      const blockScroll = function (e) { e.preventDefault(); };
      stickZone.addEventListener("touchstart", blockScroll, { passive: false });
      stickZone.addEventListener("touchmove", blockScroll, { passive: false });
    }

    const bindHoldBtn = function (id, flagName) {
      const el = document.getElementById(id);
      if (!el) return;
      el.onpointerdown = function (e) {
        try { el.setPointerCapture(e.pointerId); } catch (_) {}
        touchState.active = true;
        touchState[flagName] = true;
        el.classList.add("active");
      };
      const up = function () {
        touchState[flagName] = false;
        el.classList.remove("active");
      };
      el.onpointerup = up;
      el.onpointercancel = up;
      const blockBtnScroll = function (e) { e.preventDefault(); };
      el.addEventListener("touchstart", blockBtnScroll, { passive: false });
      el.addEventListener("touchmove", blockBtnScroll, { passive: false });
    };
    bindHoldBtn("touch-btn-gas", "throttle");
    bindHoldBtn("touch-btn-brake", "brake");
    bindHoldBtn("touch-btn-drift", "handbrake");
    bindHoldBtn("touch-btn-nitro", "boost");
  }

  function updateLiveHudNodes() {
    const sp = document.getElementById("hud-speed-val");
    if (sp) sp.textContent = String(Math.round(telemetry.speedKmh));
    const gr = document.getElementById("hud-gear-val");
    if (gr) gr.textContent = telemetry.gear <= 0 ? "R" : String(Math.round(telemetry.gear));
    const rpm = document.getElementById("hud-rpm-fill");
    if (rpm) rpm.style.width = Math.round(Math.max(0, Math.min(1, telemetry.rpmNorm)) * 100) + "%";
    const nos = document.getElementById("hud-nitro-fill");
    if (nos) nos.style.width = Math.round(Math.max(0, Math.min(1, telemetry.boostPct)) * 100) + "%";
    const fp = document.getElementById("hud-map-fps");
    if (fp) fp.textContent = latestState.mapMode + " | " + Math.round(telemetry.fps) + " FPS";
    drawMinimap();
  }

  function drawMinimap() {
    const canvas = document.getElementById("hud-minimap");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    if (cachedWaypoints && cachedWaypoints.length > 2 && latestState.mapMode === "Circuit") {
      let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
      for (const p of cachedWaypoints) {
        if (p[0] < minX) minX = p[0];
        if (p[0] > maxX) maxX = p[0];
        if (p[1] < minY) minY = p[1];
        if (p[1] > maxY) maxY = p[1];
      }
      const span = Math.max(maxX - minX, maxY - minY, 1);
      const scale = Math.min(w - 20, h - 20) / span;
      const toX = function (x) { return (w - (maxX - minX) * scale) * 0.5 + (x - minX) * scale; };
      const toY = function (y) { return h - ((h - (maxY - minY) * scale) * 0.5 + (y - minY) * scale); };

      ctx.strokeStyle = "rgba(0, 229, 255, 0.72)";
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      cachedWaypoints.forEach(function (p, i) {
        if (i === 0) ctx.moveTo(toX(p[0]), toY(p[1]));
        else ctx.lineTo(toX(p[0]), toY(p[1]));
      });
      ctx.closePath();
      ctx.stroke();

      ctx.fillStyle = "#ff2e63";
      ctx.beginPath();
      ctx.arc(toX(telemetry.carX), toY(telemetry.carY), 4, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.strokeStyle = "rgba(0, 229, 255, 0.55)";
      ctx.strokeRect(16, 12, w - 32, h - 24);
      const nx = (telemetry.carX + 200) / 400;
      const ny = 1 - (telemetry.carY + 200) / 400;
      ctx.fillStyle = "#ff2e63";
      ctx.beginPath();
      ctx.arc(16 + nx * (w - 32), 12 + ny * (h - 24), 4, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Forward keyboard/pointer to Haxe cleanly while preventing double-activation on focused buttons
  window.addEventListener("keydown", function (e) {
    const activeEl = document.activeElement;
    if (activeEl && activeEl.id === "mp-code-input") {
      if (e.key === "Enter") {
        e.preventDefault();
        sendUiCmd({ cmd: "mp_join", code: activeEl.value });
      }
      return;
    }
    ensureAudioCtx();
    const isListeningRemap = Boolean(latestState.options && latestState.options.listening);
    const inMenuUi = latestState.appState !== "IntroSequence" && latestState.uiState !== "Splash" && latestState.uiState !== "InGameHUD";

    if (inMenuUi && !isListeningRemap) {
      if (e.key === "ArrowUp" || e.key === "ArrowDown" || e.key === "ArrowLeft" || e.key === "ArrowRight" ||
          e.key === "w" || e.key === "W" || e.key === "s" || e.key === "S" || e.key === "a" || e.key === "A" || e.key === "d" || e.key === "D") {
        if (e.key.startsWith("Arrow")) e.preventDefault();
        if (activeEl && activeEl.tagName === "BUTTON") activeEl.blur();
      } else if ((e.key === "Enter" || e.key === " ") && activeEl && activeEl.closest && activeEl.closest("#menu-shell")) {
        if (activeEl.tagName === "BUTTON" || activeEl.classList.contains("map-card")) {
          e.preventDefault();
          activeEl.click();
          return;
        }
      }
    }

    pushInbound({ type: "key_state", code: e.keyCode || e.which || 0, down: true });
    if (latestState.uiState === "Splash" && latestState.appState !== "IntroSequence") {
      sendUiCmd({ cmd: "splash_continue" });
    }
  }, true);

  let lastPadSig = "";
  function sampleHostGamepadToBridge() {
    if (!navigator.getGamepads) return;
    let pads;
    try { pads = navigator.getGamepads(); } catch (_) { return; }
    let activePad = null;
    if (pads) {
      for (let i = 0; i < pads.length; i++) {
        if (pads[i] && pads[i].connected) { activePad = pads[i]; break; }
      }
    }
    const payload = activePad ? {
      type: "pad_state",
      connected: true,
      axes: Array.from(activePad.axes || []).slice(0, 4).map(function (v) { return Math.round((v || 0) * 100) / 100; }),
      buttons: Array.from(activePad.buttons || []).slice(0, 17).map(function (b) { return Boolean(b && b.pressed); }),
      values: Array.from(activePad.buttons || []).slice(0, 17).map(function (b) { return Math.round(((b && b.value) || 0) * 100) / 100; })
    } : { type: "pad_state", connected: false, axes: [], buttons: [], values: [] };
    const sig = JSON.stringify(payload);
    if (sig !== lastPadSig) {
      lastPadSig = sig;
      pushInbound(payload);
    }
  }

  let coarseAutoSent = false;
  function activateTouchControls() {
    if (!touchState.active) {
      touchState.active = true;
      pushInbound({ type: "e2e_cmd", cmd: "set_touch_enabled", enabled: true });
    }
  }

  window.addEventListener("touchstart", activateTouchControls, { passive: true, capture: true });
  window.addEventListener("pointerdown", function (e) {
    ensureAudioCtx();
    if (e && e.pointerType === "touch") activateTouchControls();
  }, true);

  window.addEventListener("keyup", function (e) {
    if (document.activeElement && document.activeElement.id === "mp-code-input") return;
    pushInbound({ type: "key_state", code: e.keyCode || e.which || 0, down: false });
  }, true);

  // Sync loop reading Haxe state/telemetry and writing touch/orientation flags
  function tickBridge() {
    const dv = ensureMailbox();
    if (dv) {
      hydrateStorageAndEnv(dv);
      dv.setInt32(OFF_PORTRAIT_BLOCKED, window.__mobPortraitBlocked ? 1 : 0, true);
      dv.setInt32(OFF_TOUCH_ACTIVE, touchState.active ? 1 : 0, true);
      dv.setFloat32(OFF_TOUCH_STEER, touchState.steer, true);
      dv.setFloat32(OFF_TOUCH_THROTTLE, touchState.throttle ? 1.0 : 0.0, true);
      dv.setFloat32(OFF_TOUCH_BRAKE, touchState.brake ? 1.0 : 0.0, true);
      dv.setInt32(OFF_TOUCH_HANDBRAKE, touchState.handbrake ? 1 : 0, true);
      dv.setInt32(OFF_TOUCH_BOOST, touchState.boost ? 1 : 0, true);

      telemetry.speedKmh = dv.getFloat32(OFF_SPEED_KMH, true);
      telemetry.rpmNorm = dv.getFloat32(OFF_RPM_NORM, true);
      telemetry.gear = dv.getFloat32(OFF_GEAR, true);
      telemetry.boostPct = dv.getFloat32(OFF_BOOST_PCT, true);
      telemetry.carX = dv.getFloat32(OFF_CAR_X, true);
      telemetry.carY = dv.getFloat32(OFF_CAR_Y, true);
      telemetry.carYaw = dv.getFloat32(OFF_CAR_YAW, true);
      telemetry.fps = dv.getFloat32(OFF_FPS, true);
      telemetry.inMenu = dv.getInt32(OFF_IN_MENU, true) !== 0;

      const seq = dv.getInt32(OFF_STATE_SEQ, true);
      if (seq !== lastStateSeq) {
        const slen = dv.getInt32(OFF_STATE_LEN, true);
        if (slen > 0 && slen <= 32508) {
          try {
            const json = decodeSharedUtf8(wasmMemory.buffer, mailboxOffset + OFF_STATE_DATA, slen);
            latestState = JSON.parse(json);
            lastStateSeq = seq;
            renderDomFromState(latestState);
          } catch (_) {}
        }
      } else if (latestState.uiState === "InGameHUD") {
        updateLiveHudNodes();
      }

      processOutboundEvents(dv);
      sampleHostGamepadToBridge();
      if (!coarseAutoSent && lastStateSeq > 0 && window.matchMedia && window.matchMedia("(pointer: coarse)").matches) {
        coarseAutoSent = true;
        activateTouchControls();
      }
    }
    requestAnimationFrame(tickBridge);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { renderDomFromState(latestState); }, { once: true });
  } else {
    renderDomFromState(latestState);
  }
  window.addEventListener("resize", function () { applyUiResolutionScale(latestState); }, { passive: true });
  requestAnimationFrame(tickBridge);

  // Public WebBridge + window.app JS Facade for MOBOrientationGate & Playwright E2E
  window.MOBWebBridge = {
    attachMemory: function (memory) {
      if (memory && !wasmMemory) {
        wasmMemory = memory;
      }
    },
    debug: function () {
      return {
        hasMemory: Boolean(wasmMemory),
        bufferBytes: wasmMemory ? wasmMemory.buffer.byteLength : 0,
        mailboxOffset: mailboxOffset,
        lastStateSeq: lastStateSeq,
        hydratedSent: hydratedSent
      };
    }
  };

  window.app = {
    get state() { return latestState; },
    get uiScale() { return currentUiScale; },
    get appState() { return latestState.appState; },
    get introState() { return latestState.introState; },
    get currentMapMode() { return latestState.mapMode; },
    get pausedByOrientation() { return Boolean(latestState.pausedByOrientation); },
    setOrientationPaused: function (blocked) {
      window.__mobPortraitBlocked = Boolean(blocked);
      const dv = ensureMailbox();
      if (dv) dv.setInt32(OFF_PORTRAIT_BLOCKED, blocked ? 1 : 0, true);
    },
    pauseActiveGame: function () {
      pushInbound({ type: "e2e_cmd", cmd: "pause_game" });
    },
    loadMap: function (mode) {
      pushInbound({ type: "e2e_cmd", cmd: "load_map", map: String(mode) });
    },
    handleMenuAction: function (act) {
      sendUiCmd({ cmd: "action", action: String(act) });
    },
    setTouchControlsEnabled: function (on) {
      touchState.active = Boolean(on);
      pushInbound({ type: "e2e_cmd", cmd: "set_touch_enabled", enabled: Boolean(on) });
    },
    carPhysics: {
      get pos() { return { x: telemetry.carX, y: telemetry.carY, z: 0 }; },
      get yaw() { return telemetry.carYaw; },
      get forwardSpeed() { return telemetry.speedKmh / 3.6; },
      get boostFuel() { return telemetry.boostPct; },
      get currentGear() { return telemetry.gear; }
    },
    ui: {
      get currentState() { return latestState.uiState; },
      get touchControlsHUD() {
        return {
          get visible() { return Boolean(latestState.touchEnabled && latestState.uiState === "InGameHUD"); }
        };
      }
    },
    input: {
      get isTouchActive() { return Boolean(latestState.touchEnabled || touchState.active); },
      set isTouchActive(v) {
        touchState.active = Boolean(v);
        pushInbound({ type: "e2e_cmd", cmd: "set_touch_enabled", enabled: Boolean(v) });
      }
    },
    get multiplayer() { return latestState.mp; }
  };
})();
