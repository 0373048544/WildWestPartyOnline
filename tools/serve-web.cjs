'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../build/web');
const types = { '.html':'text/html; charset=utf-8', '.js':'application/javascript', '.wasm':'application/wasm', '.pck':'application/octet-stream', '.png':'image/png', '.svg':'image/svg+xml' };
const port = Number(process.env.WWPO_HTTP_PORT || 8080);
const server = http.createServer((req, res) => {
  let requested;
  try { requested = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400).end(); return; }
  const target = path.resolve(root, '.' + (requested === '/' ? '/index.html' : requested));
  if (!target.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  fs.stat(target, (err, stat) => {
    if (err || !stat.isFile()) { res.writeHead(404).end('Build missing. Export the Web preset first.'); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(target)] || 'application/octet-stream',
      'Cache-Control':'no-store', 'Cross-Origin-Opener-Policy':'same-origin', 'Cross-Origin-Embedder-Policy':'require-corp' });
    fs.createReadStream(target).pipe(res);
  });
});
server.listen(port, process.env.WWPO_HTTP_BIND || '127.0.0.1', () => console.log('WEB READY http://127.0.0.1:' + port));
