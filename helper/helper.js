// Root helper for cleanyourtv launcher: bridges the launcher web app to luna and serves app icons.
// Listens on 127.0.0.1 only.
const http = require('http'), fs = require('fs'), path = require('path'), cp = require('child_process');
const PORT = 8765, CONF = '/media/developer/cleanyourtv/config.json';
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
const body = req => new Promise(r => { let b = ''; req.on('data', c => b += c); req.on('end', () => { try { r(JSON.parse(b || '{}')); } catch (_) { r({}); } }); });

http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'content-type');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
  const json = (o, c) => { res.writeHead(c || 200, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
  const u = req.url.split('?')[0];
  try {
    if (u === '/api/apps') return json({ apps: await apps(), config: readConf() });
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
}).listen(PORT, '127.0.0.1');
