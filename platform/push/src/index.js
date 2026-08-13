'use strict';

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const webpush = require('web-push');

const PORT = Number(process.env.PORT || 3000);
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const STATIC_DIR =
  process.env.STATIC_DIR || path.join(__dirname, '..', '..', '..', 'site');
const API_KEY = process.env.PUSH_API_KEY || '';
const TICK_MS = Number(process.env.TICK_MS || 30_000);
const DEFAULT_APP_URL = process.env.DEFAULT_APP_URL || '/apps/microgreens/';

fs.mkdirSync(DATA_DIR, { recursive: true });

const vapidPath = path.join(DATA_DIR, 'vapid.json');
const subsPath = path.join(DATA_DIR, 'subscriptions.json');
const schedulePath = path.join(DATA_DIR, 'schedules.json');

function readJson(file, fallback) {
  try {
    if (!fs.existsSync(file)) return fallback;
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(file, value) {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2));
  fs.renameSync(tmp, file);
}

function loadVapid() {
  if (!fs.existsSync(vapidPath)) {
    const keys = webpush.generateVAPIDKeys();
    const vapid = {
      publicKey: keys.publicKey,
      privateKey: keys.privateKey,
      subject: process.env.VAPID_SUBJECT || 'mailto:support@agronizer.ru',
    };
    writeJson(vapidPath, vapid);
    console.log('Generated new VAPID keys at', vapidPath);
    return vapid;
  }
  return readJson(vapidPath, null);
}

const vapid = loadVapid();
if (!vapid?.publicKey || !vapid?.privateKey) {
  console.error('Invalid VAPID keys in', vapidPath);
  process.exit(1);
}

webpush.setVapidDetails(vapid.subject, vapid.publicKey, vapid.privateKey);

/** @type {Record<string, object>} */
let subscriptions = readJson(subsPath, {});
/** @type {Record<string, Array<{id:string,at:string,title:string,body:string,url?:string}>>} */
let schedules = readJson(schedulePath, {});

function saveSubs() {
  writeJson(subsPath, subscriptions);
}
function saveSchedules() {
  writeJson(schedulePath, schedules);
}

function requireApiKey(req, res, next) {
  if (!API_KEY) return next();
  const key = req.get('x-api-key') || '';
  if (key !== API_KEY) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  return next();
}

function resolveUnderStatic(relParts) {
  const resolved = path.resolve(STATIC_DIR, ...relParts);
  const root = path.resolve(STATIC_DIR);
  if (!resolved.startsWith(root + path.sep) && resolved !== root) {
    return null;
  }
  return resolved;
}

async function sendToDevice(deviceId, title, body, data = {}) {
  const sub = subscriptions[deviceId];
  if (!sub) return { ok: false, reason: 'no_subscription' };
  try {
    await webpush.sendNotification(
      sub,
      JSON.stringify({ title, body, data }),
    );
    return { ok: true };
  } catch (err) {
    const status = err.statusCode || err.status;
    if (status === 404 || status === 410) {
      delete subscriptions[deviceId];
      saveSubs();
      delete schedules[deviceId];
      saveSchedules();
      return { ok: false, reason: 'gone' };
    }
    console.error('send failed', deviceId, err.message);
    return { ok: false, reason: err.message };
  }
}

async function tick() {
  const now = Date.now();
  let changed = false;
  for (const [deviceId, items] of Object.entries(schedules)) {
    if (!Array.isArray(items) || items.length === 0) continue;
    const keep = [];
    for (const item of items) {
      const at = Date.parse(item.at);
      if (Number.isNaN(at) || at > now) {
        keep.push(item);
        continue;
      }
      const title = item.title || 'Агронайзер';
      const body = item.body || '';
      const url = item.url || DEFAULT_APP_URL;
      const result = await sendToDevice(deviceId, title, body, { url });
      console.log('due', deviceId, item.id, result);
      changed = true;
    }
    schedules[deviceId] = keep;
  }
  if (changed) saveSchedules();
}

function createPushRouter() {
  const router = express.Router();
  router.use(express.json({ limit: '256kb' }));

  router.get('/health', (_req, res) => {
    res.json({
      ok: true,
      service: 'agronizer',
      push: true,
      subscriptions: Object.keys(subscriptions).length,
      schedules: Object.values(schedules).reduce(
        (n, items) => n + (Array.isArray(items) ? items.length : 0),
        0,
      ),
    });
  });

  router.get('/api/vapid-public-key', (_req, res) => {
    res.json({ publicKey: vapid.publicKey });
  });

  router.post('/api/subscribe', (req, res) => {
    const { deviceId, subscription } = req.body || {};
    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ error: 'deviceId required' });
    }
    if (!subscription?.endpoint || !subscription?.keys) {
      return res.status(400).json({ error: 'subscription required' });
    }
    subscriptions[deviceId] = subscription;
    saveSubs();
    return res.json({ ok: true });
  });

  router.delete('/api/subscribe', (req, res) => {
    const deviceId = req.body?.deviceId || req.query.deviceId;
    if (!deviceId) return res.status(400).json({ error: 'deviceId required' });
    delete subscriptions[deviceId];
    delete schedules[deviceId];
    saveSubs();
    saveSchedules();
    return res.json({ ok: true });
  });

  router.put('/api/schedule', (req, res) => {
    const { deviceId, items } = req.body || {};
    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ error: 'deviceId required' });
    }
    if (!subscriptions[deviceId]) {
      return res.status(404).json({ error: 'subscribe first' });
    }
    if (!Array.isArray(items)) {
      return res.status(400).json({ error: 'items array required' });
    }
    const cleaned = items
      .filter((i) => i && i.id && i.at && i.body)
      .map((i) => ({
        id: String(i.id),
        at: String(i.at),
        title: String(i.title || 'Агронайзер'),
        body: String(i.body),
        url: i.url ? String(i.url) : DEFAULT_APP_URL,
      }));
    schedules[deviceId] = cleaned;
    saveSchedules();
    return res.json({ ok: true, count: cleaned.length });
  });

  router.post('/api/send', requireApiKey, async (req, res) => {
    const { deviceId, title, body, url } = req.body || {};
    if (!title || !body) {
      return res.status(400).json({ error: 'title and body required' });
    }
    const data = { url: url || DEFAULT_APP_URL };
    if (deviceId) {
      const result = await sendToDevice(deviceId, title, body, data);
      return res.json(result);
    }
    const results = {};
    for (const id of Object.keys(subscriptions)) {
      results[id] = await sendToDevice(id, title, body, data);
    }
    return res.json({ ok: true, results });
  });

  return router;
}

const app = express();
app.use(cors({ origin: true }));

app.use('/push', createPushRouter());
app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'agronizer',
    staticDir: STATIC_DIR,
    staticOk: fs.existsSync(STATIC_DIR),
  });
});

if (!fs.existsSync(STATIC_DIR)) {
  console.warn('STATIC_DIR missing:', STATIC_DIR);
}

// Legacy single-app URLs → multi-app paths
app.get('/app', (_req, res) => res.redirect(301, '/apps/microgreens/'));
app.get('/app/', (_req, res) => res.redirect(301, '/apps/microgreens/'));
app.get(/^\/app\/(.*)$/, (req, res) => {
  const rest = req.params[0] || '';
  res.redirect(301, `/apps/microgreens/${rest}`);
});
app.get('/green_grow.apk', (_req, res) => {
  res.redirect(301, '/apps/microgreens/microgreens.apk');
});

app.get(/\.apk$/i, (req, res, next) => {
  const rel = req.path.replace(/^\//, '').split('/');
  const resolved = resolveUnderStatic(rel);
  if (!resolved || !fs.existsSync(resolved)) return next();
  res.type('application/vnd.android.package-archive');
  res.set('Cache-Control', 'public, max-age=3600');
  return res.sendFile(resolved);
});

// Per-app service worker + manifest (Service-Worker-Allowed = app base)
app.get(
  /^\/apps\/([a-z0-9-]+)\/flutter_service_worker\.js$/i,
  (req, res, next) => {
    const slug = req.params[0];
    const filePath = resolveUnderStatic(['apps', slug, 'flutter_service_worker.js']);
    if (!filePath || !fs.existsSync(filePath)) return next();
    res.setHeader('Content-Type', 'application/javascript; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.setHeader('Service-Worker-Allowed', `/apps/${slug}/`);
    return res.sendFile(filePath, (err) => {
      if (err) next(err);
    });
  },
);

app.get(/^\/apps\/([a-z0-9-]+)\/manifest\.json$/i, (req, res, next) => {
  const slug = req.params[0];
  const filePath = resolveUnderStatic(['apps', slug, 'manifest.json']);
  if (!filePath || !fs.existsSync(filePath)) return next();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache');
  return res.sendFile(filePath, (err) => {
    if (err) next(err);
  });
});

app.use(
  express.static(STATIC_DIR, {
    index: ['index.html'],
    fallthrough: true,
    setHeaders(res, filePath) {
      if (filePath.includes(`${path.sep}assets${path.sep}`)) {
        res.setHeader('Cache-Control', 'public, max-age=604800');
      }
      if (filePath.endsWith(`${path.sep}manifest.json`)) {
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
      }
    },
  }),
);

// SPA deep links for each app: /apps/<slug>/... → index.html
app.get(/^\/apps\/([a-z0-9-]+)\/?$/, (req, res, next) => {
  const slug = req.params[0];
  const index = resolveUnderStatic(['apps', slug, 'index.html']);
  if (!index || !fs.existsSync(index)) return next();
  if (!req.path.endsWith('/')) {
    return res.redirect(301, `/apps/${slug}/`);
  }
  return res.sendFile(index, (err) => {
    if (err) next(err);
  });
});

app.get(/^\/apps\/([a-z0-9-]+)\/(.*)$/, (req, res, next) => {
  if (path.extname(req.path)) return next();
  const slug = req.params[0];
  const index = resolveUnderStatic(['apps', slug, 'index.html']);
  if (!index || !fs.existsSync(index)) return next();
  return res.sendFile(index, (err) => {
    if (err) next(err);
  });
});

app.use((req, res) => {
  res.status(404).type('text').send('Not found');
});

app.use((err, _req, res, _next) => {
  console.error('request error', err);
  if (!res.headersSent) {
    res.status(500).type('text').send('Server error');
  }
});

app.listen(PORT, () => {
  console.log(`agronizer (static + push) on :${PORT}`);
  console.log(`STATIC_DIR=${STATIC_DIR}`);
  console.log(`VAPID public: ${vapid.publicKey.slice(0, 12)}…`);
  setInterval(() => {
    tick().catch((e) => console.error('tick', e));
  }, TICK_MS);
  tick().catch((e) => console.error('tick', e));
});
