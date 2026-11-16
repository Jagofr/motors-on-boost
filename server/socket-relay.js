const crypto = require('crypto');

const WS_MAGIC_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/**
 * Attaches a pure zero-dependency RFC 6455 WebSocket + HTTP JSON relay on `/ws` and `/relay.ashx`
 * to an HTTP server. Strictly forwards connection lifecycle events and raw JSON envelopes;
 * all game validation, capacity checks, version verification, and physics authority live on the Host client.
 *
 * @param {import('http').Server} httpServer
 * @param {string} [wsPath='/ws']
 */
function attachSocketRelay(httpServer, wsPath = '/ws') {
  /** @type {Map<string, { id: string, host: any, peers: Map<string, any> }>} */
  const rooms = new Map();
  /** @type {Map<string, any>} */
  const clients = new Map();
  const CLIENT_STALE_MS = 60000;
  const MAX_HTTP_OUTBOX = 160;
  let nextConnSeq = 1;

  function makeRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for (let i = 0; i < 6; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
    return rooms.has(code) ? makeRoomCode() : code;
  }

  function encodeFrame(opcode, payloadBuf) {
    const len = payloadBuf.length;
    let header;
    if (len < 126) {
      header = Buffer.alloc(2);
      header[0] = 0x80 | opcode;
      header[1] = len;
    } else if (len < 65536) {
      header = Buffer.alloc(4);
      header[0] = 0x80 | opcode;
      header[1] = 126;
      header.writeUInt16BE(len, 2);
    } else {
      header = Buffer.alloc(10);
      header[0] = 0x80 | opcode;
      header[1] = 127;
      header.writeBigUInt64BE(BigInt(len), 2);
    }
    return Buffer.concat([header, payloadBuf]);
  }

  function sendJson(client, obj) {
    if (!client || client.closed || !obj) return;
    if (!client.isWebSocket) {
      if (client.outbox.length >= MAX_HTTP_OUTBOX) {
        const dropIdx = client.outbox.findIndex((e) => e && e.type === 'relayed_from_host');
        if (dropIdx >= 0) client.outbox.splice(dropIdx, 1);
        else client.outbox.shift();
      }
      client.outbox.push(obj);
      return;
    }
    if (!client.socket || client.socket.destroyed) return;
    try {
      const payload = Buffer.from(JSON.stringify(obj), 'utf8');
      client.socket.write(encodeFrame(0x1, payload));
    } catch (_err) {
      // Ignore write failures on closing sockets
    }
  }

  function sweepStaleClients() {
    const now = Date.now();
    for (const [id, c] of clients.entries()) {
      if (!c.isWebSocket && !c.closed && (now - c.lastSeenMs) > CLIENT_STALE_MS) {
        c.closed = true;
        detachClientFromRoom(c);
        clients.delete(id);
      }
    }
  }

  function detachClientFromRoom(client) {
    if (!client.roomId) return;
    const room = rooms.get(client.roomId);
    const roomId = client.roomId;
    client.roomId = null;

    if (!room) {
      client.isHost = false;
      return;
    }

    if (client.isHost && room.host === client) {
      for (const peer of room.peers.values()) {
        peer.roomId = null;
        peer.isHost = false;
        sendJson(peer, { type: 'host_disconnected', roomId });
      }
      room.peers.clear();
      rooms.delete(roomId);
    } else if (room.peers.has(client.id)) {
      room.peers.delete(client.id);
      if (room.host && !room.host.closed) {
        sendJson(room.host, { type: 'peer_socket_disconnected', peerId: client.id });
      }
    }
    client.isHost = false;
  }

  function handleRelayEnvelope(client, msg) {
    if (!msg || typeof msg !== 'object') return;

    switch (msg.type) {
      case 'host_room': {
        detachClientFromRoom(client);
        let requested = typeof msg.roomId === 'string' ? msg.roomId.trim().toUpperCase().replace(/[^A-Z0-9_-]/g, '') : '';
        if (!requested || rooms.has(requested)) {
          requested = makeRoomCode();
        }
        client.roomId = requested;
        client.isHost = true;
        rooms.set(requested, { id: requested, host: client, peers: new Map() });
        sendJson(client, { type: 'room_hosted', roomId: requested, connId: client.id });
        break;
      }

      case 'join_room': {
        detachClientFromRoom(client);
        const roomId = typeof msg.roomId === 'string' ? msg.roomId.trim().toUpperCase() : '';
        const room = rooms.get(roomId);
        if (!room || !room.host || room.host.closed) {
          sendJson(client, { type: 'relay_error', message: `Room "${roomId}" was not found or host went offline.` });
          return;
        }
        client.roomId = roomId;
        client.isHost = false;
        room.peers.set(client.id, client);
        sendJson(client, { type: 'room_joined', roomId, connId: client.id });
        sendJson(room.host, { type: 'peer_socket_connected', peerId: client.id });
        break;
      }

      case 'relay_to_host': {
        if (!client.roomId || client.isHost) return;
        const room = rooms.get(client.roomId);
        if (room && room.host && !room.host.closed) {
          sendJson(room.host, {
            type: 'relayed_from_peer',
            fromId: client.id,
            payload: msg.payload
          });
        }
        break;
      }

      case 'relay_to_peer': {
        if (!client.roomId || !client.isHost) return;
        const room = rooms.get(client.roomId);
        if (!room) return;
        const peer = room.peers.get(msg.targetId);
        if (peer && !peer.closed) {
          sendJson(peer, {
            type: 'relayed_from_host',
            payload: msg.payload
          });
        }
        break;
      }

      case 'relay_broadcast': {
        if (!client.roomId || !client.isHost) return;
        const room = rooms.get(client.roomId);
        if (!room) return;
        for (const peer of room.peers.values()) {
          if (!peer.closed) {
            sendJson(peer, {
              type: 'relayed_from_host',
              payload: msg.payload
            });
          }
        }
        break;
      }

      case 'leave_room': {
        detachClientFromRoom(client);
        break;
      }

      default:
        break;
    }
  }

  function processFrames(client) {
    while (client.buffer.length >= 2) {
      const b0 = client.buffer[0];
      const b1 = client.buffer[1];
      const fin = (b0 & 0x80) !== 0;
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let payloadLen = b1 & 0x7f;
      let offset = 2;

      if (payloadLen === 126) {
        if (client.buffer.length < 4) return;
        payloadLen = client.buffer.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (client.buffer.length < 10) return;
        const bigLen = client.buffer.readBigUInt64BE(2);
        if (bigLen > BigInt(4 * 1024 * 1024)) {
          client.socket.destroy();
          return;
        }
        payloadLen = Number(bigLen);
        offset = 10;
      }

      const maskLen = masked ? 4 : 0;
      if (client.buffer.length < offset + maskLen + payloadLen) return;

      let maskKey = null;
      if (masked) {
        maskKey = client.buffer.subarray(offset, offset + 4);
        offset += 4;
      }

      const payload = Buffer.from(client.buffer.subarray(offset, offset + payloadLen));
      client.buffer = client.buffer.subarray(offset + payloadLen);

      if (masked && maskKey) {
        for (let i = 0; i < payload.length; i++) {
          payload[i] ^= maskKey[i & 3];
        }
      }

      if (opcode === 0x8) {
        // Close frame
        client.closed = true;
        try {
          client.socket.end(encodeFrame(0x8, Buffer.alloc(0)));
        } catch (_e) {}
        detachClientFromRoom(client);
        clients.delete(client.id);
        return;
      } else if (opcode === 0x9) {
        // Ping -> Pong
        try {
          client.socket.write(encodeFrame(0xA, payload));
        } catch (_e) {}
        continue;
      } else if (opcode === 0xA) {
        // Pong
        continue;
      } else if (opcode === 0x1 || opcode === 0x0) {
        if (opcode === 0x1) {
          client.fragments = [payload];
        } else {
          client.fragments.push(payload);
        }
        if (fin) {
          const full = Buffer.concat(client.fragments);
          client.fragments = [];
          try {
            const text = full.toString('utf8');
            const parsed = JSON.parse(text);
            handleRelayEnvelope(client, parsed);
          } catch (_err) {
            // Malformed JSON ignored by relay
          }
        }
      }
    }
  }

  function handleHttpRelayRequest(req, res) {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    sweepStaleClients();

    const queryStr = (req.url || '').split('?')[1] || '';
    const params = new URLSearchParams(queryStr);
    if (req.method === 'GET' && params.get('ping') === '1') {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, relay: 'node', rooms: rooms.size }));
      return;
    }

    const chunks = [];
    let bodyBytes = 0;
    req.on('data', (chunk) => {
      bodyBytes += chunk.length;
      if (bodyBytes <= 2 * 1024 * 1024) {
        chunks.push(chunk);
      }
    });
    req.on('end', () => {
      let reqObj = null;
      const bodyText = Buffer.concat(chunks).toString('utf8').trim();
      if (bodyText) {
        try {
          reqObj = JSON.parse(bodyText);
        } catch (_e) {
          reqObj = null;
        }
      }

      const connId = (reqObj && typeof reqObj.connId === 'string' && reqObj.connId)
        ? reqObj.connId
        : (params.get('connId') || '');
      let client = connId ? clients.get(connId) : null;
      if (client && client.closed) client = null;

      if (!client) {
        client = {
          id: `p_${nextConnSeq++}`,
          socket: null,
          buffer: Buffer.alloc(0),
          fragments: [],
          outbox: [],
          roomId: null,
          isHost: false,
          isWebSocket: false,
          closed: false,
          lastSeenMs: Date.now()
        };
        clients.set(client.id, client);
        sendJson(client, { type: 'welcome', connId: client.id });
      } else {
        client.lastSeenMs = Date.now();
      }

      if (reqObj && Array.isArray(reqObj.messages)) {
        for (const msg of reqObj.messages) {
          handleRelayEnvelope(client, msg);
        }
      } else if (reqObj && typeof reqObj.type === 'string') {
        handleRelayEnvelope(client, reqObj);
      }

      const events = client.outbox.splice(0, client.outbox.length);
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, connId: client.id, events }));
    });
  }

  const existingRequestListeners = httpServer.listeners('request').slice();
  httpServer.removeAllListeners('request');
  httpServer.on('request', (req, res) => {
    const reqUrl = (req.url || '/').split('?')[0];
    if (reqUrl === '/relay.ashx' || reqUrl === '/ws/poll') {
      handleHttpRelayRequest(req, res);
      return;
    }
    for (const listener of existingRequestListeners) {
      listener.call(httpServer, req, res);
    }
  });

  httpServer.on('upgrade', (req, socket) => {
    const reqUrl = (req.url || '/').split('?')[0];
    if (reqUrl !== wsPath && reqUrl !== '/relay.ashx') {
      socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    const key = req.headers['sec-websocket-key'];
    if (!key) {
      socket.write('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }

    const accept = crypto
      .createHash('sha1')
      .update(key + WS_MAGIC_GUID)
      .digest('base64');

    const headers = [
      'HTTP/1.1 101 Switching Protocols',
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Accept: ${accept}`
    ];
    socket.write(headers.join('\r\n') + '\r\n\r\n');

    const client = {
      id: `p_${nextConnSeq++}`,
      socket,
      buffer: Buffer.alloc(0),
      fragments: [],
      outbox: [],
      roomId: null,
      isHost: false,
      isWebSocket: true,
      closed: false,
      lastSeenMs: Date.now()
    };
    clients.set(client.id, client);

    sendJson(client, { type: 'welcome', connId: client.id });

    socket.on('data', (chunk) => {
      client.lastSeenMs = Date.now();
      client.buffer = Buffer.concat([client.buffer, chunk]);
      processFrames(client);
    });

    socket.on('close', () => {
      client.closed = true;
      detachClientFromRoom(client);
      clients.delete(client.id);
    });

    socket.on('error', () => {
      client.closed = true;
      detachClientFromRoom(client);
      clients.delete(client.id);
    });
  });

  return {
    getRoomCount: () => rooms.size
  };
}

module.exports = { attachSocketRelay };
