// 法定节假日日历取数模块。
//
// ## 职责边界（红线，设计 §1.2 难点 B）
// 日历**只用于放行已有的文本证据**，绝不用于推断：
//   ✅ 回答「D 是不是法定节假日」（`date === D && isOffDay === true`）
//   ✅ 给出节日名，供原文「清明节/劳动节…」具名排班直配
//   ✅ 让「(法定节假日除外)」条款在 D 生效或失效
//   ❌ 推断节假日营业时段
//   ❌ 推断「节假日通常按常规时段开放」
//   ❌ 解析「以官方通知为准」（那是模式 B，本模块不碰）
//
// ## 三态，不是布尔（设计 §2.3）
// `unknown` 与 `non_holiday` 是两个值。`unknown` 绝不当 `non_holiday` 用 ——
// 这是整条红线的技术落点：把 unknown 当 non_holiday，会让「除外型闭馆条款」
// 在日历不可得时恢复 `closed=true`，而那一天可能正是节假日 → 阻塞级假阳性。
//
// ## 取数三级（设计 §2.2）
//   L1 进程内缓存：成功 24h / 失败 60s
//   L2 内置快照  ：`server/src/data/holiday-cn/{year}.json`，**运行时只读不回写**
//   L3 运行时 CDN：3s 超时 + 最多 1 次重试（退避 300ms）
//
// 零新增运行时依赖：只用内建 `fetch` / `AbortSignal.timeout` / `node:fs`。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** 快照目录（随代码走，运行时只读）。 */
const DEFAULT_SNAPSHOT_DIR = path.join(__dirname, 'data', 'holiday-cn');
/** 成功态缓存 TTL：24h。国务院安排一年一发，不需要更频繁。 */
const DEFAULT_TTL_MS = 24 * 60 * 60 * 1000;
/** 失败态缓存 TTL：60s。防止每次请求都打 CDN（失败时 CDN 才是热点）。 */
const DEFAULT_FAIL_TTL_MS = 60 * 1000;
/** CDN 单次超时。行程生成是用户等待路径，不能让日历拖慢它。 */
const FETCH_TIMEOUT_MS = 3000;
/** 重试退避。 */
const FETCH_RETRY_BACKOFF_MS = 300;
/** 最多尝试次数（= 1 次重试）。 */
const MAX_FETCH_ATTEMPTS = 2;
/**
 * ISO 日期格式（schema 校验硬要求）。
 *
 * ⚠️ **必须带捕获组**：`yearOf()` 用 `m[1]` 取年份。写成 `/^\d{4}-...$/`
 *    时 `m[1]` 是 `undefined` → `Number(undefined)` = `NaN` → `path.join(dir,'NaN.json')`
 *    永远读不到快照 → 整个模块静默退化成「全是 unknown」。
 *    这是本次实现中真实踩到的坑，改动本行时务必保留括号。
 */
const ISO_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** 三态取值（封闭枚举，客户端对未知值一律按保守方向处理）。 */
export const HOLIDAY_STATUS = Object.freeze({
  HOLIDAY: 'holiday',
  NON_HOLIDAY: 'non_holiday',
  UNKNOWN: 'unknown',
});

const UNKNOWN_RESULT = Object.freeze({ status: HOLIDAY_STATUS.UNKNOWN, name: null });
const NON_HOLIDAY_RESULT = Object.freeze({ status: HOLIDAY_STATUS.NON_HOLIDAY, name: null });

/**
 * CDN 地址模板。
 * @param {number} year 年份
 * @returns {string} URL
 */
export function cdnUrlOf(year) {
  return `https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/${year}.json`;
}

/**
 * schema 校验（设计 §2.4，任一项不满足 → 整份判为非法 → unknown）。
 *
 * 硬要求：
 *   - `year === 请求年份`（防止拿错年份的快照凑数）
 *   - `days` 是数组
 *   - 每个 entry 的 `date` 匹配 `YYYY-MM-DD`、`isOffDay` 是布尔、`name` 是字符串
 *
 * ⚠️ `days.length === 0` **不是**非法，而是「合法但无覆盖」（2027 空壳），
 *    由 `classify()` 单独判为 unknown。这里不能把它判成非法而抛掉 ——
 *    那样会把「有文件但没数据」和「没文件」混成一件事，年度更新时排查会很难。
 *
 * @param {unknown} raw 解析后的 JSON
 * @param {number} year 期望年份
 * @returns {{year: number, papers: string[], days: Array<{date: string, name: string, isOffDay: boolean}>}|null}
 */
export function validateHolidayYear(raw, year) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  if (raw.year !== year) return null;
  if (!Array.isArray(raw.days)) return null;
  const days = [];
  for (const e of raw.days) {
    if (!e || typeof e !== 'object' || Array.isArray(e)) return null;
    if (typeof e.date !== 'string' || !ISO_DATE_RE.test(e.date)) return null;
    if (typeof e.isOffDay !== 'boolean') return null;
    if (typeof e.name !== 'string') return null;
    days.push({ date: e.date, name: e.name, isOffDay: e.isOffDay });
  }
  const papers = Array.isArray(raw.papers) ? raw.papers.filter((p) => typeof p === 'string') : [];
  return { year, papers, days };
}

/**
 * 判定：某日是否为法定节假日（设计 §7 第 1 条，唯一式）。
 *
 * ⛔ 禁止写成 `days.some(e => e.date === D)`（「D 在 days 里」）——
 *    `days` 同时含**调休补班日**（`isOffDay:false`），那样会把 6 个补班日
 *    当成节假日，进而让「法定节假日除外」条款在补班日失效 → 该闭馆的日子不闭馆。
 *
 * @param {object|null} data 已校验的年份数据
 * @param {string} dateISO yyyy-MM-dd
 * @returns {{status: string, name: string|null}} 三态结果
 */
function classify(data, dateISO) {
  if (!data) return UNKNOWN_RESULT;
  // 「合法但无覆盖」：2027 空壳（days.length === 0）→ 不知道这天是什么日子
  if (data.days.length === 0) return UNKNOWN_RESULT;
  const entry = data.days.find((e) => e.date === dateISO);
  if (entry && entry.isOffDay === true) return { status: HOLIDAY_STATUS.HOLIDAY, name: entry.name };
  return NON_HOLIDAY_RESULT;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * 取 `yyyy-MM-dd` 的年份；**不是真实日期则返回 null**。
 *
 * ⛔ 不能只校验「格式像不像」：`2026-13-99` 格式合法但不是一天。
 *    若把它的年份取出来继续判定，会得到 `non_holiday` ——
 *    等于对「一个不存在的日子」断言「它不是节假日」，这是无依据的结论。
 *    与 `planner.js` 的 `parseIsoDate()` 同口径：用 UTC 构造再回读，拒绝进位。
 *
 * @param {string} dateISO 日期
 * @returns {number|null} 年份或 null
 */
function yearOf(dateISO) {
  const m = ISO_DATE_RE.exec(String(dateISO == null ? '' : dateISO).trim());
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  return y;
}

/**
 * 创建节假日解析器。
 *
 * @param {object} [options]
 * @param {string} [options.snapshotDir] 快照目录
 * @param {typeof fetch} [options.fetchImpl] 可注入的 fetch（测试打桩）
 * @param {number} [options.ttlMs] 成功态 TTL，默认 24h
 * @param {number} [options.failTtlMs] 失败态 TTL，默认 60s
 * @param {() => number} [options.now] 可注入的时钟（测试用）
 * @param {boolean} [options.enableNetwork] 是否允许 L3 CDN（测试默认关）
 * @returns {object} HolidayResolver
 */
export function createHolidayResolver(options = {}) {
  const {
    snapshotDir = DEFAULT_SNAPSHOT_DIR,
    fetchImpl = globalThis.fetch,
    ttlMs = DEFAULT_TTL_MS,
    failTtlMs = DEFAULT_FAIL_TTL_MS,
    now = () => Date.now(),
    enableNetwork = true,
  } = options;

  /** @type {Map<number, {state: 'ok'|'fail', data?: object, at: number, source: string}>} */
  const cache = new Map();
  /** @type {Map<number, Promise<object|null>>} 同一年份的并发取数合并，避免打爆 CDN */
  const inflight = new Map();

  /**
   * L2：读内置快照（同步、只读、永不回写）。
   * @param {number} year 年份
   * @returns {object|null} 已校验数据或 null
   */
  function loadSnapshot(year) {
    try {
      const file = path.join(snapshotDir, `${year}.json`);
      const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
      return validateHolidayYear(raw, year);
    } catch {
      // 文件不存在 / JSON 坏 / schema 非法 → 都当没有快照
      return null;
    }
  }

  /**
   * L3：CDN 取数（3s 超时 + 1 次重试）。
   *
   * schema 非法时**不重试**：同一份非法数据重试多少次都不会变合法，
   * 重试只会白白多花 3 秒在用户等待路径上。
   *
   * @param {number} year 年份
   * @returns {Promise<object|null>} 已校验数据或 null
   */
  async function fetchYear(year) {
    if (!enableNetwork || typeof fetchImpl !== 'function') return null;
    for (let attempt = 0; attempt < MAX_FETCH_ATTEMPTS; attempt++) {
      if (attempt > 0) await sleep(FETCH_RETRY_BACKOFF_MS);
      try {
        const resp = await fetchImpl(cdnUrlOf(year), { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
        if (!resp || !resp.ok) continue; // 404（2028 尚未发布）→ 下一次尝试
        const raw = await resp.json();
        return validateHolidayYear(raw, year);
      } catch {
        // 超时 / 网络错误 / JSON 解析失败 → 退避后重试
      }
    }
    return null;
  }

  const isFresh = (entry, t) => {
    if (!entry) return false;
    const ttl = entry.state === 'ok' ? ttlMs : failTtlMs;
    return t - entry.at < ttl;
  };

  /**
   * 异步取某年数据（L1 → L2 → L3），并在 L2 命中时后台刷新 L3。
   * @param {number} year 年份
   * @returns {Promise<object|null>} 已校验数据或 null
   */
  async function resolveYear(year) {
    const t = now();
    const hit = cache.get(year);
    if (isFresh(hit, t)) return hit.state === 'ok' ? hit.data : null;

    const snap = loadSnapshot(year);
    if (snap) {
      cache.set(year, { state: 'ok', data: snap, at: t, source: 'snapshot' });
      // fire-and-forget 刷新：快照可能已过期（国务院通常在 11 月发布次年安排）。
      // ⛔ 必须 .catch：否则失败会变成 unhandled rejection 打死进程。
      const pending = inflight.get(year) ?? fetchYear(year).finally(() => inflight.delete(year));
      if (!inflight.has(year)) inflight.set(year, pending);
      pending
        .then((data) => {
          if (data) cache.set(year, { state: 'ok', data, at: now(), source: 'network' });
        })
        .catch(() => {});
      return snap;
    }

    if (!enableNetwork && typeof fetchImpl === 'function') {
      cache.set(year, { state: 'fail', at: t, source: 'none' });
      return null;
    }

    let pending = inflight.get(year);
    if (!pending) {
      pending = fetchYear(year).finally(() => inflight.delete(year));
      inflight.set(year, pending);
    }
    const data = await pending.catch(() => null);
    if (data) {
      cache.set(year, { state: 'ok', data, at: now(), source: 'network' });
      return data;
    }
    cache.set(year, { state: 'fail', at: now(), source: 'none' });
    return null;
  }

  /**
   * 同步取某年数据（**不走网络**）：L1 → L2。
   *
   * 给 parser 纯函数路径用（设计 §7 第 13 条：`parseOpenTime` 必须保持同步）。
   * @param {number} year 年份
   * @returns {object|null} 已校验数据或 null
   */
  function resolveYearSync(year) {
    const t = now();
    const hit = cache.get(year);
    if (isFresh(hit, t)) return hit.state === 'ok' ? hit.data : null;
    const snap = loadSnapshot(year);
    if (snap) {
      cache.set(year, { state: 'ok', data: snap, at: t, source: 'snapshot' });
      return snap;
    }
    return null;
  }

  return {
    /**
     * 三态查询（异步，可用于生成管线预热路径）。
     * @param {string} dateISO yyyy-MM-dd
     * @returns {Promise<{status: string, name: string|null}>}
     */
    async statusOf(dateISO) {
      const year = yearOf(dateISO);
      if (year === null) return UNKNOWN_RESULT;
      const data = await resolveYear(year);
      return classify(data, dateISO);
    },

    /**
     * 同步快照查询（parser 纯函数路径专用，**绝不联网**）。
     *
     * 离线/无快照时返回 `unknown` —— 与改动前「拿不到日历」完全同构，
     * parser 会退回 null，不产生部分降级。
     *
     * @param {string} dateISO yyyy-MM-dd
     * @returns {{status: string, name: string|null}}
     */
    statusOfSnapshot(dateISO) {
      const year = yearOf(dateISO);
      if (year === null) return UNKNOWN_RESULT;
      return classify(resolveYearSync(year), dateISO);
    },

    /**
     * 预热指定年份（生成管线启动时调用当年 + 次年）。
     * @param {number[]} years 年份列表
     * @returns {Promise<void>}
     */
    async warmup(years) {
      await Promise.all(
        (Array.isArray(years) ? years : []).map(async (year) => {
          const snap = loadSnapshot(year);
          if (snap) cache.set(year, { state: 'ok', data: snap, at: now(), source: 'snapshot' });
          const data = await fetchYear(year).catch(() => null);
          if (data) cache.set(year, { state: 'ok', data, at: now(), source: 'network' });
        }),
      );
    },

    /**
     * 运行状态（诊断/探针用）。
     * @returns {{source: string, years: number[]}}
     */
    stats() {
      const years = [...cache.keys()].sort((a, b) => a - b);
      const sources = new Set([...cache.values()].map((e) => e.source));
      const source = sources.has('network')
        ? 'network'
        : sources.has('snapshot')
          ? 'snapshot'
          : 'memory';
      return { source, years };
    },
  };
}

/** 进程级默认解析器（懒创建：避免 import 时就读盘）。 */
let defaultResolver = null;

/**
 * 取默认解析器。
 * @returns {object} HolidayResolver
 */
export function getDefaultHolidayResolver() {
  if (!defaultResolver) defaultResolver = createHolidayResolver();
  return defaultResolver;
}

/**
 * 替换默认解析器（测试注入离线实现用）。
 * @param {object|null} resolver 解析器或 null（null 表示恢复懒创建）
 * @returns {void}
 */
export function setDefaultHolidayResolver(resolver) {
  defaultResolver = resolver;
}
