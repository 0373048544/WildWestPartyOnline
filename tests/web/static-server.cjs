'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../build/web');
const port = Number(process.env.WWPO_HTTP_PORT || 18080);
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'};
http.createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
  const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const filename = path.resolve(root, relative);
  if (!filename.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
  fs.readFile(filename, (error, data) => {
    if (error) { response.writeHead(404).end('not found'); return; }
    response.writeHead(200, {'Content-Type': mime[path.extname(filename)] || 'application/octet-stream', 'Cache-Control':'no-store'});
    response.end(data);
  });
}).listen(port, '127.0.0.1', () => console.log(`STATIC READY http://127.0.0.1:${port}`));
