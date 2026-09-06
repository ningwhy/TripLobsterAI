// 高德 Web API 代理：Key 只存在服务端 .env，客户端不再持有
// 白名单转发 + 内存缓存（省配额）+ 独立限流
import { makeCache, makeRateLimit, fetchJson } from './util.js';

const AMAP_BASE = 'https://restapi.amap.com';

const ALLOWED = new Set([
  '/v3/place/text',
  '/v3/place/around',
  '/v3/place/detail',
  '/v3/direction/driving',
  '/v3/direction/transit/integrated',
  '/v3/direction/walking',
  '/v3/geocode/geo',
  '/v3/geocode/regeo',
  '/v3/intercity/transit',
]);

const cache = makeCache(10 * 60 * 1000);

// 全局串行队列：高德免费额度 QPS 有限（10021 CUQPS_HAS_EXCEEDED_THE_LIMIT）
// 统一限频 + 退避重试，宁可慢不可错
let queueTail = Promise.resolve();
const MIN_GAP_MS = 260;
let lastCallAt = 0;

function schedule(fn) {
  const run = queueTail.then(async () => {
    const wait = MIN_GAP_MS - (Date.now() - lastCallAt);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    lastCallAt = Date.now();
    return fn();
  });
  // 不让单次失败阻断队列
  queueTail = run.then(() => {}, () => {});
  return run;
}

const RETRY_INFOCODES = new Set(['10021', '10022', '10023', '20003']);

async function amapOnce(url) {
  const { status, data } = await fetchJson(url, { timeoutMs: 12000 });
  if (status !== 200 || !data) {
    const e = new Error('高德服务暂不可用');
    e.status = 502;
    e.expose = true;
    throw e;
  }
  return data;
}

async function amapCallInternal(path, params) {
  const key = process.env.AMAP_KEY;
  if (!key) { const e = new Error('服务端未配置 AMAP_KEY'); e.status = 500; e.expose = true; throw e; }
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '' && k !== 'key') q.set(k, String(v));
  }
  q.set('key', key);
  const url = `${AMAP_BASE}${path}?${q.toString()}`;
  const cacheable = path.includes('/place/') || path.includes('/geocode/');
  const ck = path + '?' + q.toString().replace(/key=[^&]+/, 'key=*');
  if (cacheable) {
    const hit = cache.get(ck);
    if (hit) return hit;
  }
  let data = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    data = await schedule(() => amapOnce(url));
    const infocode = String(data?.infocode || '');
    // 限流/配额类错误：退避重试
    if (data?.status !== '1' && RETRY_INFOCODES.has(infocode) && attempt < 2) {
      await new Promise((r) => setTimeout(r, 700 * (attempt + 1)));
      continue;
    }
    break;
  }
  if (cacheable && data?.status === '1') cache.set(ck, data);
  return data;
}

export function amapCall(path, params = {}) {
  return amapCallInternal(path, params);
}

export function registerAmapRoutes(app) {
  const limit = makeRateLimit({ windowMs: 60_000, max: 120 });

  for (const path of ALLOWED) {
    app.get(`/api/amap${path}`, limit, async (req, res, next) => {
      try {
        const params = { ...req.query };
        delete params.key;
        const data = await amapCallInternal(path, params);
        res.json(data);
      } catch (e) { next(e); }
    });
  }
}
