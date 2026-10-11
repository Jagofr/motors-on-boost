const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const PORT = 8089;
const WEB_DIR = path.resolve(__dirname, '..', 'web');
const EDGE_PATH = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

const DEBUG_PORT = 9300 + Math.floor(Math.random() * 500);

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

// 1. Lightweight Static Server
const server = http.createServer((req, res) => {
    let reqPath = decodeURI(req.url.split('?')[0]);
    if (reqPath === '/' || reqPath === '') reqPath = '/test-suite.html';
    const filePath = path.join(WEB_DIR, reqPath);

    if (!fs.existsSync(filePath)) {
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

const os = require('os');
const tmpUserDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mob-edge-test-'));

server.listen(PORT, '127.0.0.1', async () => {
    console.log(`[BrowserRunner] Local test server listening on http://127.0.0.1:${PORT}`);
    
    // 2. Launch Microsoft Edge in Headless Mode with Isolated User Profile and Unique Port
    const edgeArgs = [
        '--headless',
        '--disable-gpu',
        `--user-data-dir=${tmpUserDataDir}`,
        `--remote-debugging-port=${DEBUG_PORT}`,
        '--no-first-run',
        '--no-default-browser-check',
        `http://127.0.0.1:${PORT}/test-suite.html`
    ];

    console.log(`[BrowserRunner] Spawning Edge Headless (CDP Port ${DEBUG_PORT}): ${EDGE_PATH}`);
    const edgeProc = spawn(EDGE_PATH, edgeArgs, { stdio: 'ignore' });

    edgeProc.on('error', (err) => {
        console.error('[BrowserRunner] Failed to spawn Edge:', err);
        server.close();
        process.exit(1);
    });

    // Helper: fetch JSON from CDP endpoint
    function fetchJson(url) {
        return new Promise((resolve, reject) => {
            http.get(url, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    try { resolve(JSON.parse(data)); } catch (e) { reject(e); }
                });
            }).on('error', reject);
        });
    }

    // Wait for CDP to be available
    let wsUrl = null;
    for (let i = 0; i < 40; i++) {
        await new Promise(r => setTimeout(r, 300));
        try {
            const list = await fetchJson(`http://127.0.0.1:${DEBUG_PORT}/json`);
            const target = list.find(t => t.type === 'page' && t.url.includes('test-suite.html'));
            if (target && target.webSocketDebuggerUrl) {
                wsUrl = target.webSocketDebuggerUrl;
                break;
            }
        } catch (e) {}
    }

    if (!wsUrl) {
        console.error('[BrowserRunner] Failed to locate test-suite.html in CDP targets.');
        edgeProc.kill();
        server.close();
        process.exit(1);
    }

    console.log(`[BrowserRunner] Connected to CDP Target: ${wsUrl}`);
    const ws = new WebSocket(wsUrl);

    let nextId = 1;
    const pending = new Map();

    function sendCommand(method, params = {}) {
        return new Promise((resolve, reject) => {
            const id = nextId++;
            pending.set(id, { resolve, reject });
            try {
                ws.send(JSON.stringify({ id, method, params }));
            } catch (err) {
                reject(err);
            }
        });
    }

    ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.id && pending.has(msg.id)) {
            const { resolve, reject } = pending.get(msg.id);
            pending.delete(msg.id);
            if (msg.error) reject(new Error(msg.error.message));
            else resolve(msg.result);
        }
    };

    let checkInterval = null;
    let isCleaningUp = false;

    function cleanup(exitCode) {
        if (isCleaningUp) return;
        isCleaningUp = true;
        if (checkInterval) {
            clearInterval(checkInterval);
            checkInterval = null;
        }
        try { sendCommand('Browser.close').catch(() => {}); } catch (e) {}
        try { ws.close(); } catch (e) {}
        try {
            if (server.closeAllConnections) server.closeAllConnections();
            server.close();
        } catch (e) {}
        try {
            if (edgeProc && edgeProc.pid) {
                spawn('taskkill', ['/F', '/T', '/PID', String(edgeProc.pid)], { stdio: 'ignore' });
            }
        } catch (e) {}
        try {
            fs.rmSync(tmpUserDataDir, { recursive: true, force: true });
        } catch (e) {}
        process.exit(exitCode);
    }

    ws.onopen = async () => {
        console.log('[BrowserRunner] CDP WebSocket connection open. Monitoring test execution...');
        await sendCommand('Runtime.enable');

        // Explicitly trigger runAll in case window.load already fired
        setTimeout(async () => {
            try {
                await sendCommand('Runtime.evaluate', { expression: 'if (typeof runAll === "function") runAll();' });
            } catch (e) {}
        }, 1000);

        const startTime = Date.now();
        const maxWaitMs = 30000;

        checkInterval = setInterval(async () => {
            if (Date.now() - startTime > maxWaitMs) {
                console.error('[BrowserRunner] Test execution timed out after 30 seconds.');
                cleanup(1);
                return;
            }

            try {
                const evalRes = await sendCommand('Runtime.evaluate', {
                    expression: 'JSON.stringify(window.__TEST_RESULTS__ || null)',
                    returnByValue: true
                });

                if (evalRes && evalRes.result && evalRes.result.value) {
                    const results = JSON.parse(evalRes.result.value);
                    if (results && results.total >= 14 && results.total === (results.passed + results.failed)) {
                        // Fetch log console text
                        const logRes = await sendCommand('Runtime.evaluate', {
                            expression: 'document.getElementById("logConsole") ? document.getElementById("logConsole").textContent : ""',
                            returnByValue: true
                        });

                        console.log('\n--- BROWSER TEST CONSOLE OUTPUT ---');
                        console.log(logRes ? logRes.result.value : '');
                        console.log('-----------------------------------\n');

                        console.log(`[BrowserRunner] SUMMARY: Total: ${results.total}, Passed: ${results.passed}, Failed: ${results.failed}`);
                        cleanup(results.failed > 0 ? 1 : 0);
                    }
                }
            } catch (err) {
                // Ignore transient eval errors while page is transitioning
            }
        }, 500);
    };
});
