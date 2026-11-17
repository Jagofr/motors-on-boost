const http = require('http');
const fs = require('fs');
const path = require('path');
const { attachSocketRelay } = require('../server/socket-relay');

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const eq = a.indexOf('=');
      if (eq >= 0) {
        out[a.slice(2, eq)] = a.slice(eq + 1);
      } else {
        out[a.slice(2)] = argv[i + 1] || 'true';
        i++;
      }
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const MODE = (args.mode || process.env.MOB_HOST_MODE || 'iis').toLowerCase();
const PORT = parseInt(args.port || process.env.MOB_TEST_PORT || (MODE === 'gh-pages' ? '7726' : '7725'), 10);
const RAW_BASE = args['base-path'] || process.env.MOB_BASE_PATH || (MODE === 'gh-pages' ? '/motors-on-boost' : '');
const BASE_PATH = RAW_BASE ? ('/' + RAW_BASE.replace(/^\/+|\/+$/g, '')) : '';

const WEB_ROOT = MODE === 'gh-pages'
  ? path.resolve(__dirname, '..', 'dist', 'gh-pages')
  : path.resolve(__dirname, '..', 'web');

if (!fs.existsSync(WEB_ROOT)) {
  console.error(`[server] Missing ${MODE} build directory: ${WEB_ROOT}. Run .vscode/build-deploy.ps1 or node scripts/prepare-gh-pages.js first.`);
  process.exit(1);
}

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

  if (BASE_PATH && reqPath === BASE_PATH) {
    res.writeHead(301, { Location: `${BASE_PATH}/` });
    res.end();
    return;
  }

  let subPath = reqPath;
  if (BASE_PATH) {
    if (!reqPath.startsWith(`${BASE_PATH}/`)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }
    subPath = reqPath.slice(BASE_PATH.length);
  }

  const relPath = subPath === '/' || subPath === '' ? 'index.html' : subPath.replace(/^\/+/, '');
  const filePath = path.resolve(WEB_ROOT, relPath);

  if (!filePath.startsWith(WEB_ROOT) || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';
  const headers = {
    'Content-Type': contentType,
    'Cache-Control': 'no-cache, no-store, must-revalidate'
  };

  if (MODE !== 'gh-pages') {
    // IIS target provides native COOP/COEP/CORP headers.
    // gh-pages target intentionally omits them so sw.js header injection is exercised end-to-end.
    headers['Cross-Origin-Opener-Policy'] = 'same-origin';
    headers['Cross-Origin-Embedder-Policy'] = 'require-corp';
    headers['Cross-Origin-Resource-Policy'] = 'same-origin';
  }

  res.writeHead(200, headers);
  fs.createReadStream(filePath).pipe(res);
});

if (MODE !== 'gh-pages') {
  attachSocketRelay(server, '/relay.ashx');
}

server.listen(PORT, '127.0.0.1', () => {
  console.log(`[${MODE}] Static test server${MODE !== 'gh-pages' ? ' + relay' : ' (no COOP/COEP headers)'} listening on http://127.0.0.1:${PORT}${BASE_PATH || '/'} -> ${WEB_ROOT}`);
});
