const http = require('http');
const fs = require('fs');
const path = require('path');
const { attachSocketRelay } = require('../server/socket-relay');

const WEB_ROOT = path.resolve(__dirname, '..', 'web');
const PORT = parseInt(process.env.MOB_TEST_PORT || '7725', 10);

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2'
};

const server = http.createServer((req, res) => {
  const reqPath = (req.url || '/').split('?')[0];
  let relPath = reqPath === '/' ? 'index.html' : reqPath.replace(/^\/+/, '');
  const filePath = path.resolve(WEB_ROOT, relPath);

  if (!filePath.startsWith(WEB_ROOT) || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';
  res.writeHead(200, {
    'Content-Type': contentType,
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin'
  });
  fs.createReadStream(filePath).pipe(res);
});

attachSocketRelay(server, '/relay.ashx');

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Static test server + relay listening on http://127.0.0.1:${PORT} -> ${WEB_ROOT}`);
});
