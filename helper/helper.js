// Root helper for cleanyourtv launcher: bridges the launcher web app to luna and serves app icons.
// Listens on 127.0.0.1 only.
const http = require('http'), fs = require('fs'), path = require('path'), cp = require('child_process');
const VERSION = '1.1.0';
const PORT = 8765, DIR = '/media/developer/cleanyourtv', CONF = DIR + '/config.json', USAGE = DIR + '/usage.json';
const ENV = Object.assign({}, process.env, { PATH: '/usr/bin:/usr/sbin:/bin:/sbin:' + (process.env.PATH || '') });

function luna(uri, payload) {
  return new Promise(res => {
    const sh = 'luna-send -n 1 -w 5000 -f "$1" "$2" </dev/null';
    cp.execFile('/bin/sh', ['-c', sh, 'sh', uri, JSON.stringify(payload || {})],
      { env: ENV, timeout: 8000, maxBuffer: 8 << 20 }, (e, out) => {
        try { res(JSON.parse(out)); } catch (_) { res({ returnValue: false, errorText: String(e || 'bad json') }); }
      });
  });
}
const readConf = () => { try { return JSON.parse(fs.readFileSync(CONF, 'utf8')); } catch (_) { return {}; } };
let appCache = null, appCacheAt = 0;
async function apps() {
  if (appCache && Date.now() - appCacheAt < 5000) return appCache;
  const r = await luna('luna://com.webos.applicationManager/listApps', {});
  appCache = (r.apps || []).filter(a => a.visible !== false && a.id !== 'com.webos.app.home')
    .map(a => ({ id: a.id, title: a.title, icon: a.largeIcon || a.icon, folder: a.folderPath, type: a.type }));
  appCacheAt = Date.now();
  return appCache;
}

// ---- usage: count which apps get used (foreground changes), with a 30-day half-life ----
const HALF_LIFE = 30 * 24 * 3600 * 1000;
let usage = {};
try { usage = JSON.parse(fs.readFileSync(USAGE, 'utf8')); } catch (_) {}
const decayed = (u, now) => u.s * Math.pow(0.5, (now - u.t) / HALF_LIFE);
function usageScores() {
  const now = Date.now(), out = {};
  for (const id in usage) out[id] = Math.round(decayed(usage[id], now) * 1000) / 1000;
  return out;
}
let saveTimer = null;
function bump(id) {
  const now = Date.now(), u = usage[id];
  usage[id] = { s: (u ? decayed(u, now) : 0) + 1, t: now };
  if (!saveTimer) saveTimer = setTimeout(() => {
    saveTimer = null;
    try { fs.writeFileSync(USAGE + '.tmp', JSON.stringify(usage)); fs.renameSync(USAGE + '.tmp', USAGE); } catch (_) {}
  }, 15000);
}
let lastFg = null;
async function onForeground(id) {
  if (id === lastFg) return;
  const first = lastFg === null;
  lastFg = id;
  if (first || !id || id === 'com.webos.app.home') return;
  if ((await apps()).some(a => a.id === id)) bump(id);
}
// One long-lived subscription instead of polling; it restarts when the system app manager restarts.
function watchForeground() {
  const ch = cp.spawn('luna-send', ['-i', '-f', 'luna://com.webos.applicationManager/getForegroundAppInfo', '{"subscribe":true}'],
    { env: ENV, stdio: ['ignore', 'pipe', 'ignore'] });
  let buf = '', depth = 0, start = -1;
  ch.stdout.on('data', d => {
    buf += d;
    for (let i = 0; i < buf.length; i++) {
      if (buf[i] === '{') { if (depth++ === 0) start = i; }
      else if (buf[i] === '}' && --depth === 0 && start >= 0) {
        try { const o = JSON.parse(buf.slice(start, i + 1)); if (o.returnValue !== false) onForeground(o.appId || ''); } catch (_) {}
        buf = buf.slice(i + 1); i = -1; start = -1;
      }
    }
    if (buf.length > 65536) { buf = ''; depth = 0; start = -1; }
  });
  ch.on('error', () => setTimeout(watchForeground, 5000));
  ch.on('close', () => { lastFg = null; setTimeout(watchForeground, 3000); });
}
const body = req => new Promise(r => { let b = ''; req.on('data', c => b += c); req.on('end', () => { try { r(JSON.parse(b || '{}')); } catch (_) { r({}); } }); });

http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
  const json = (o, c) => { res.writeHead(c || 200, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
  const u = req.url.split('?')[0];
  try {
    if (u === '/api/version') return json({ version: VERSION });
    if (u === '/api/apps') return json({ apps: await apps(), config: readConf(), usage: usageScores(), version: VERSION });
    if (u === '/api/inputs') return json(await luna('luna://com.webos.service.eim/getAllInputStatus', {}));
    if (u === '/api/foreground') return json(await luna('luna://com.webos.applicationManager/getForegroundAppInfo', {}));
    if (u === '/api/launch' && req.method === 'POST') {
      const b = await body(req);
      if (!/^[\w.\-]+$/.test(b.id || '')) return json({ error: 'bad id' }, 400);
      return json(await luna('luna://com.webos.applicationManager/launch', { id: b.id, params: b.params || {} }));
    }
    if (u === '/api/config' && req.method === 'POST') {
      const b = await body(req), strs = v => Array.isArray(v) ? v.filter(x => typeof x === 'string').slice(0, 200) : undefined;
      const out = {};
      if (strs(b.dock)) out.dock = strs(b.dock).slice(0, 4);
      if (strs(b.hidden)) out.hidden = strs(b.hidden);
      if (b.sort === 'usage' || b.sort === 'alpha') out.sort = b.sort;
      if (Array.isArray(b.topbar)) out.topbar = b.topbar.slice(0, 12).filter(o => o && typeof o.label === 'string').map(o => {
        const t = { label: o.label.slice(0, 40), icon: String(o.icon || 'grid').slice(0, 20) };
        if (typeof o.action === 'string') t.action = o.action; if (typeof o.app === 'string') t.app = o.app;
        if (o.params && typeof o.params === 'object') t.params = o.params; return t; });
      fs.writeFileSync(CONF + '.tmp', JSON.stringify(out, null, 2)); fs.renameSync(CONF + '.tmp', CONF);
      return json({ returnValue: true });
    }
    if (u === '/api/undo' && req.method === 'POST') {
      cp.spawn('/bin/sh', ['-c', 'sleep 1; sh /media/developer/cleanyourtv/undo-home.sh temp'], { env: ENV, detached: true, stdio: 'ignore' }).unref();
      return json({ returnValue: true });
    }
    const m = u.match(/^\/icon\/([\w.\-]+)$/);
    if (m) {
      const a = (await apps()).find(x => x.id === m[1]);
      const f = a && a.icon && path.join(a.folder, a.icon);
      if (!f || !path.resolve(f).startsWith(path.resolve(a.folder)) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { 'content-type': 'image/png', 'cache-control': 'max-age=3600' });
      return fs.createReadStream(f).pipe(res);
    }
    res.writeHead(404); res.end();
  } catch (e) { json({ error: String(e) }, 500); }
}).listen(PORT, '127.0.0.1', watchForeground);
