// Capturas y GIFs sin extensión de navegador: Chrome headless por CDP.
//
//   node design-lab/tools/capturar.mjs plan.json
//
// plan.json:
// {
//   "base": "http://localhost:7797",          // opcional
//   "shots": [
//     { "url": "/b-cristal-v2/?full=1", "width": 390, "height": 844, "dpr": 2,
//       "scheme": "dark", "reducedMotion": false, "waitMs": 1500,
//       "eval": "window.setScenario && setScenario('via')",   // JS antes de la captura
//       "selector": "#la-lock",                                // opcional: recorta a ese elemento
//       "out": "design-lab/capturas/la-widgets/lock-a-oscuro.png" },
//     { "url": "...", "gif": { "frames": 24, "intervalMs": 120 }, "out": "....gif" }
//   ]
// }
//
// Los GIF se montan con Pillow (python -m pip show pillow) a partir de PNGs.
// Node 22+ trae WebSocket de serie: sin dependencias.
import { spawn, execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const CHROME = process.env.CHROME_PATH
  || ['C:/Program Files/Google/Chrome/Application/chrome.exe',
      'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      '/usr/bin/google-chrome', '/usr/bin/chromium']
    .find(p => existsSync(p));
const PORT = 9300 + Math.floor(Math.random() * 500);
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function waitJson(url, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try { const r = await fetch(url); if (r.ok) return await r.json(); } catch { /* aún no */ }
    await sleep(250);
  }
  throw new Error('Chrome no responde en ' + url);
}

class Cdp {
  constructor(wsUrl) { this.ws = new WebSocket(wsUrl); this.id = 0; this.pending = new Map(); this.events = []; this.listeners = []; }
  open() {
    return new Promise((ok, ko) => {
      this.ws.onopen = ok; this.ws.onerror = ko;
      this.ws.onmessage = ev => {
        const m = JSON.parse(ev.data);
        if (m.id && this.pending.has(m.id)) {
          const { res, rej } = this.pending.get(m.id); this.pending.delete(m.id);
          m.error ? rej(new Error(m.error.message)) : res(m.result);
        } else if (m.method) { this.listeners.forEach(l => l(m)); }
      };
    });
  }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((res, rej) => this.pending.set(id, { res, rej }));
  }
  on(fn) { this.listeners.push(fn); }
}

async function shot(cdp, s, base, errors) {
  const width = s.width || 390, height = s.height || 844, dpr = s.dpr || 2;
  await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: dpr, mobile: width < 700 });
  await cdp.send('Emulation.setEmulatedMedia', { features: [
    { name: 'prefers-color-scheme', value: s.scheme || 'light' },
    { name: 'prefers-reduced-motion', value: s.reducedMotion ? 'reduce' : 'no-preference' },
    { name: 'prefers-reduced-transparency', value: s.reducedTransparency ? 'reduce' : 'no-preference' },
  ] });
  const url = s.url.startsWith('http') ? s.url : (base || '') + s.url;
  if (!s.sameUrl) {
    await cdp.send('Page.navigate', { url });
    await sleep(s.loadMs ?? 1200);
  }
  if (s.eval) {
    const r = await cdp.send('Runtime.evaluate', { expression: s.eval, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) errors.push(`${s.out}: eval falló: ${r.exceptionDetails.text}`);
  }
  await sleep(s.waitMs ?? 800);
  let clip;
  if (s.selector) {
    const r = await cdp.send('Runtime.evaluate', { returnByValue: true, expression:
      `(()=>{const e=document.querySelector(${JSON.stringify(s.selector)}); if(!e) return null; const b=e.getBoundingClientRect(); return {x:b.x,y:b.y,width:b.width,height:b.height};})()` });
    if (r.result && r.result.value) clip = { ...r.result.value, scale: 1 };
    else errors.push(`${s.out}: no encuentro ${s.selector}`);
  }
  mkdirSync(dirname(resolve(s.out)), { recursive: true });
  if (s.gif) {
    const tmp = mkdtempSync(join(tmpdir(), 'trajet-gif-'));
    const frames = s.gif.frames || 20;
    for (let i = 0; i < frames; i++) {
      const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', clip, captureBeyondViewport: false });
      writeFileSync(join(tmp, `f${String(i).padStart(3, '0')}.png`), Buffer.from(data, 'base64'));
      if (s.gif.evalEach) await cdp.send('Runtime.evaluate', { expression: s.gif.evalEach });
      await sleep(s.gif.intervalMs || 120);
    }
    const py = `import glob,sys\nfrom PIL import Image\nfs=sorted(glob.glob(sys.argv[1]+'/*.png'))\nims=[Image.open(f).convert('RGB') for f in fs]\nw=${s.gif.width || 0}\nif w:\n  ims=[i.resize((w,int(i.height*w/i.width))) for i in ims]\nims=[i.quantize(colors=128, method=Image.Quantize.MEDIANCUT) for i in ims]\nims[0].save(sys.argv[2],save_all=True,append_images=ims[1:],duration=${s.gif.intervalMs || 120},loop=0,optimize=True)`;
    execFileSync(process.env.PYTHON || 'python', ['-c', py, tmp, resolve(s.out)]);
    rmSync(tmp, { recursive: true, force: true });
  } else {
    const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', clip });
    writeFileSync(resolve(s.out), Buffer.from(data, 'base64'));
  }
  console.log('ok', s.out);
}

async function main() {
  const plan = JSON.parse(readFileSync(process.argv[2], 'utf8'));
  if (!CHROME) throw new Error('No encuentro Chrome (CHROME_PATH)');
  const profile = mkdtempSync(join(tmpdir(), 'trajet-chrome-'));
  const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--force-color-profile=srgb',
    '--disable-extensions', '--mute-audio', 'about:blank'], { stdio: 'ignore' });
  const errors = [];
  try {
    const list = await waitJson(`http://127.0.0.1:${PORT}/json/list`);
    const page = list.find(t => t.type === 'page');
    const cdp = new Cdp(page.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Page.enable'); await cdp.send('Runtime.enable'); await cdp.send('Log.enable');
    cdp.on(m => {
      if (m.method === 'Runtime.exceptionThrown') errors.push('excepción: ' + (m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text));
      if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errors.push('console.error: ' + m.params.args.map(a => a.value ?? a.description).join(' '));
      if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error' && !/favicon.ico/.test(m.params.entry.url || '')) errors.push('log: ' + m.params.entry.text + ' ' + (m.params.entry.url || ''));
    });
    for (const s of plan.shots) await shot(cdp, s, plan.base, errors);
    cdp.ws.close();
  } finally {
    chrome.kill();
    await sleep(300);
    try { rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome aún cerrando */ }
  }
  if (errors.length) { console.log('ERRORES EN LA PÁGINA:'); errors.forEach(e => console.log('  ' + e)); process.exitCode = 2; }
  else console.log('sin errores en consola');
}
main().catch(e => { console.error(e); process.exit(1); });
