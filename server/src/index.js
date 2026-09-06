// 旅行助手后端服务入口
import express from 'express';
import { openDb } from './db.js';
import { loadEnv } from './env.js';
import { makeRateLimit } from './util.js';
import { registerAuthRoutes } from './auth.js';
import { registerSyncRoutes } from './sync.js';
import { registerAmapRoutes } from './amapProxy.js';
import { registerWeatherRoutes } from './weather.js';
import { registerPlannerRoutes } from './planner.js';

loadEnv();

const PORT = parseInt(process.env.PORT || '8787', 10);
const DB_FILE = process.env.DB_FILE || new URL('../data/trip.db', import.meta.url).pathname.replace(/^\/(\w:)/, '$1');

const db = openDb(DB_FILE);

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '4mb' }));

// 基础安全头（生产建议 HTTPS + 反代）
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  // 移动端原生不依赖CORS；仅便于本地调试
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// 全局限流
app.use('/api', makeRateLimit({ windowMs: 60_000, max: 300 }));

app.get('/', (req, res) => res.json({ ok: true, name: 'trip-server', version: '0.1.0' }));

registerAuthRoutes(app, db);
registerSyncRoutes(app, db);
registerAmapRoutes(app, db);
registerWeatherRoutes(app);
registerPlannerRoutes(app, db);

// 统一错误处理
app.use((err, req, res, next) => {
  console.error('[error]', err.message);
  res.status(err.status || 500).json({ error: err.expose ? err.message : '服务内部错误' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`trip-server listening on http://0.0.0.0:${PORT}`);
  console.log(`db: ${DB_FILE}`);
  console.log(`amap key loaded: ${process.env.AMAP_KEY ? 'yes' : 'NO - set AMAP_KEY in .env'}`);
});
