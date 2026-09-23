// Servidor estático mínimo para el laboratorio (sin dependencias).
// Lo lanza servir.ps1. Escucha en 0.0.0.0 para verlo desde el iPhone.
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.PORT || 7797);
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.gif': 'image/gif',
  '.md': 'text/markdown; charset=utf-8', '.woff2': 'font/woff2', '.ico': 'image/x-icon', '.webmanifest': 'application/manifest+json'
};

http.createServer((req, res) => {
  let url = decodeURIComponent(req.url.split('?')[0]);
  if (url.endsWith('/')) url += 'index.html';
  const file = path.normalize(path.join(ROOT, url));
  if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('404 ' + url); }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
}).listen(PORT, '0.0.0.0', () => {
  const ips = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces()))
    for (const a of addrs) if (a.family === 'IPv4' && !a.internal) ips.push({ name, ip: a.address });
  console.log(`\nTrajet · laboratorio de diseño sirviendo ${ROOT}\n`);
  console.log(`  En este PC:   http://localhost:${PORT}/`);
  for (const { name, ip } of ips) console.log(`  ${name.padEnd(12)}  http://${ip}:${PORT}/`);
  console.log('\nEn el iPhone abre la URL de la red Wi-Fi (192.168.x.x) o la de Tailscale (100.x.x.x).\nCtrl+C para parar.\n');
});
