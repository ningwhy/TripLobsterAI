// 通用工具：限流、缓存、http 转发
const buckets = new Map();

export function makeRateLimit({ windowMs, max }) {
  return (req, res, next) => {
    const ip = req.socket.remoteAddress || 'unknown';
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
