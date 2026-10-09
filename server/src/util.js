// 通用工具：限流、缓存、http 转发
// 注意：buckets 必须是**每个限流器实例一份**（放在 makeRateLimit 内部）。
// 旧实现把 buckets 放在模块级，导致 index.js 的全局 300/分、amapProxy 的 120/分、
// multiCity 的 5/分 三个限流器共用同一张表 —— 打满 corridor 的 5 次后，
// 该 IP 的所有 /api 请求（含 POI 搜索）都会被 429，属于串桶缺陷。
export function makeRateLimit({ windowMs, max }) {
  const buckets = new Map();
  return (req, res, next) => {
    const ip = (req && req.socket && req.socket.remoteAddress) || 'unknown';
    const now = Date.now();
    let b = buckets.get(ip);
    if (!b || now - b.start > windowMs) {
      b = { start: now, count: 0 };
      buckets.set(ip, b);
    }
    b.count += 1;
    if (b.count > max) {
      res.setHeader('Retry-After', Math.ceil((b.start + windowMs - now) / 1000));
      return res.status(429).json({ error: '请求过于频繁，请稍后再试' });
    }
    next();
  };
}

// 简易内存缓存
export function makeCache(ttlMs) {
  const store = new Map();
  return {
    get(key) {
      const hit = store.get(key);
      if (!hit) return null;
      if (Date.now() - hit.t > ttlMs) {
        store.delete(key);
        return null;
      }
      return hit.v;
    },
    set(key, v) {
      if (store.size > 5000) store.clear(); // 防爆
      store.set(key, { t: Date.now(), v });
    },
  };
}

// 带超时的 fetch JSON
export async function fetchJson(url, { timeoutMs = 12000, ...init } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const resp = await fetch(url, { ...init, signal: ctrl.signal });
    const text = await resp.text();
    let data = null;
    try { data = JSON.parse(text); } catch { /* 保留原始文本 */ }
    return { ok: resp.ok, status: resp.status, data, text };
  } finally {
    clearTimeout(timer);
  }
}
