const http = require('http');
const fs = require('fs');
const path = require('path');
const { attachSocketRelay } = require('./socket-relay');

const PORT = Number(process.env.PORT || 8090);
const HOST = process.env.HOST || '0.0.0.0';
const WEB_DIR = path.resolve(__dirname, '..', 'web');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
  '.webmanifest': 'application/manifest+json'
};

const server = http.createServer((req, res) => {
  let reqPath = decodeURI((req.url || '/').split('?')[0]);
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';

  const resolvedPath = path.resolve(WEB_DIR, '.' + reqPath);
  if (!resolvedPath.startsWith(WEB_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  if (!fs.existsSync(resolvedPath) || fs.statSync(resolvedPath).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found: ' + reqPath);
    return;
  }

  const ext = path.extname(resolvedPath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  res.writeHead(200, {
    'Content-Type': contentType,
    'Cache-Control': 'no-cache, no-store, must-revalidate'
  });
  fs.createReadStream(resolvedPath).pipe(res);
});

attachSocketRelay(server, '/ws');

server.listen(PORT, HOST, () => {
  console.log(`[Multiplayer Relay Server] Serving ${WEB_DIR}`);
  console.log(`[Multiplayer Relay Server] HTTP + WS Relay active at http://localhost:${PORT} (ws://<host>:${PORT}/ws)`);
});
