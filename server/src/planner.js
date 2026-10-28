// AI 行程生成引擎（P0-2 MVP）
// 架构：LLM 只做"编排与文案"，所有事实（地点/坐标/评分/路线）来自高德真实数据
// 默认走规则引擎：候选收集 → 评分排名 → 地理聚类分天 → NN+2-opt 排序 → 时刻表构建（含用餐、营业时间校验）
import { amapCall } from './amapProxy.js';
import { isLlmEnabled, llmChat } from './llm.js';
import { getDefaultHolidayResolver } from './holiday.js';

const INTERESTS = {
  nature: { label: '自然风光', queries: [{ types: '110200' }, { keywords: '自然风光', types: '110000' }] },
  culture: { label: '历史人文', queries: [{ types: '110100' }, { keywords: '古镇' }] },
  museum: { label: '博物馆馆', queries: [{ types: '140100' }] },
  fun: { label: '主题乐园', queries: [{ keywords: '主题乐园' }, { keywords: '游乐园' }, { keywords: '动物园' }] },
  shopping: { label: '购物商圈', queries: [{ types: '060101' }] },
  arts: { label: '文艺打卡', queries: [{ keywords: '文创园区' }, { keywords: '艺术区' }] },
};

const PER_DAY_CAP = { relaxed: 2, normal: 3, packed: 4 };
const START_CLOCK = { relaxed: 570, normal: 540, packed: 510 }; // 9:30 / 9:00 / 8:30
const STAY_FACTOR = { relaxed: 0.8, normal: 1.0, packed: 1.2 };

function haversineKm(a, b) {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

// ===========================================================================
// 日期感知营业时间解析（SR-OH1 / T02）
// ---------------------------------------------------------------------------
// 事实来源只有高德原文：biz_ext.opentime2 → biz_ext.open_time（仅简单格式兼容）。
// 旧实现的两个致命问题（FX-OH 探针实测）：
//   1. 读 `biz_ext.opentime` —— 该键**恒不存在**（实测 undefined）；
//   2. `open_time` 无值时常为空数组 `[]`，JS 里 truthy 且 String([])===''。
// 另：营业时间不是单个时间段，而是带条件的自然语言（季节区间 / 星期 / 停止入场 /
// 闭馆日 / 多时段 / 24 小时）。只取"第一个匹配"会在多时段原文上产生**假阳性**
// （"11:00-14:00 16:00-22:00" → close=14:00 → 用户 19:00 到被误报"已打烊"）。
//
// 多时段的正确解法是**返回多段**，不是放弃：
//   · 多时段 → open/close 强制为 null，只由 `segments` 承载（结构性杜绝假阳性）；
//   · 判据从"落在 [open, close] 内"改为"落在 segments 中**任一段**内"；
//   · 餐饮 open_time 大量是多时段格式，放弃会把覆盖率最高的那类直接归零。
// 三铁律：不估算、不编造、不兜底填充 —— 任何不确定一律五字段全 null 且 segments: []。
// ===========================================================================

/** 星期汉字 → ISO 星期序号（周一=1 … 周日=7）。 */
const WEEKDAY_CHAR = { 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6, 日: 7, 天: 7 };

/** 各月最大日（2 月按 29 计，用于"月末"包容，避免 2/28 边界被误判为区间残缺）。 */
const MONTH_LAST_DAY = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/** 季节/月份提示词：出现但区间端点不完整 → 保守放弃（设计 §1.2.3）。 */
const SEASON_HINT_RE = /月|旺季|淡季|平季/;
/** 明确关闭词：只有命中其一才允许产出 closedOnThisDate=true。 */
const CLOSE_RE = /关闭|闭馆|闭园|不开放|停业/;
/** 24 小时/全天：可确定性判定 → 识别为 00:00-24:00 单段，绝不解析成 00:00-00:00。 */
const ALL_DAY_RE = /24\s*小时|全天开放|全天营业|通宵/;
/** 全天开放的标准表示（24:00 表示"到当日结束"，toMin 得 1440）。 */
const ALL_DAY_SEGMENT = Object.freeze({ open: '00:00', close: '24:00', lastEntry: null });
/** 节假日例外：需要外部权威节假日日历才能判定 → 放弃（设计 A-3）。 */
const HOLIDAY_RE = /法定节假日|法定节日|节假日|节日/;
// 【T02/R-1】宽松「除外」识别：节假日字样后 0~6 个非分隔符内出现 除外 / 除…外 / 外。
// 旧正则（/除外|正常开放|照常开放|正常营业/）漏掉「节假日除外」的宽松写法（上科技馆），
// 且把「正常开放」也当除外 —— 后者是 C 具名排班（节假日开放），不是除外。
const HOLIDAY_EXCEPT_RE = /(?:法定)?节(?:假)?日[^，；、]{0,6}(?:除外|除\s*外|外)/;
/** 另行通知类：属于非确定性语法 → 放弃。 */
const NOTICE_RE = /以官方通知为准|另行通知|以公告为准|以景区公告为准|以官方公告为准|以现场公告为准/;
/** 营业时间段 HH:mm-HH:mm（分隔符在归一后统一为 - / 至 / ~）。 */
const WINDOW_RE = /(\d{1,2})\s*:\s*(\d{2})\s*(?:至|到|-|~)\s*(\d{1,2})\s*:\s*(\d{2})/g;
/** 停止入场（时刻在前）：16:00停止检票 / 16:30停止入馆 / 17:00 停止入园。 */
const LAST_ENTRY_PREFIX_RE = /(\d{1,2})\s*:\s*(\d{2})\s*(?:停止|截止)\s*(?:检票|入馆|入园|入场|售票|参观|接待|进入)?/g;
/** 停止入场（时刻在后）：最晚进入15:00 / 最后入场 16:00。 */
const LAST_ENTRY_SUFFIX_RE = /(?:最晚|最后|末次)\s*(?:进入|入场|入园|入馆|检票|取票)\s*(\d{1,2})\s*:\s*(\d{2})/g;
/** 星期令牌：周二 / 星期日 / 礼拜六。 */
const WEEKDAY_TOKEN_RE = /(?:周|星期|礼拜)\s?([一二三四五六日天])/g;
/** 日期区间：M月D日 至 [次年] M月D日。 */
const MD_RANGE_RE = /(\d{1,2})\s*月\s*(\d{1,2})\s*日?\s*(?:至|到|-|~)\s*(次年|明年|翌年)?\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?/g;
/** 月份区间：M月至M月 / 3-10月（含全角破折号，归一后为 -）。 */
const MM_RANGE_RE = /(\d{1,2})\s*(?:月)?\s*(?:至|到|-|~)\s*(\d{1,2})\s*月/g;
/**
 * 无"月/日"字的日期区间：**03-16至10-31**、**09/25-09/27**、**01/01-09/24**（高德实测大量使用）。
 * 不支持会把"03-16至10-31"当成全年生效 → 与另一季节段同时命中，也会把"周一全天不开放"
 * 误判成全年闭馆（苏州博物馆实测：不加这条会**每一天都被判闭馆**，属高危假阳性）。
 */
const SLASH_MD_RANGE_RE = /(\d{1,2})[-/](\d{1,2})\s*(?:至|到|-|~)\s*(\d{1,2})[-/](\d{1,2})/g;
/** 具名节假日（春节/端午/国庆…）：没有权威节假日日历就无法判定是否命中 → 按未知处理。 */
const HOLIDAY_NAME_RE = /春节|除夕|元宵|元旦|清明|劳动节|端午|中秋|国庆|教师节|儿童节|妇女节/;

/**
 * 具名节假日 → 法定节假日日历规范名映射（与 holiday-cn 的 `name` 字段对齐）。
 * 规范名集合：元旦 / 春节 / 清明节 / 劳动节 / 端午节 / 中秋节 / 国庆节 / 教师节 / 儿童节 / 妇女节 / 元宵节。
 * @param {string} text 子句（已归一）
 * @returns {string[]} 去重后的规范名；空数组 = 泛指（如「法定节假日」「节假日」）
 */
const HOLIDAY_NAME_CANON = [
  ['元旦', '元旦'], ['春节', '春节'], ['除夕', '春节'], ['元宵', '元宵节'],
  ['清明', '清明节'], ['劳动节', '劳动节'], ['端午', '端午节'], ['中秋', '中秋节'],
  ['国庆', '国庆节'], ['教师节', '教师节'], ['儿童节', '儿童节'], ['妇女节', '妇女节'],
];
/**
 * 节假日名令牌正则（源于 HOLIDAY_NAME_CANON 的关键字）：用于判断一个短串是不是**纯节假日名**。
 * @type {{end: RegExp, start: RegExp}}
 */
const HOLIDAY_TOKEN_RE = (() => {
  const alt = HOLIDAY_NAME_CANON.map(([kw]) => kw).join('|');
  return { end: new RegExp(`(?:${alt})$`), start: new RegExp(`^\\s*(?:${alt})`) };
})();

function extractHolidayNames(text) {
  const out = [];
  for (const [kw, canon] of HOLIDAY_NAME_CANON) {
    if (text.includes(kw)) out.push(canon);
  }
  return [...new Set(out)];
}

/**
 * 解析失败的统一空对象（契约：五字段全 null **且 segments 为空数组**）。
 * `reason` 仅用于服务端诊断与探针统计，**不进入客户端 payload**。
 * @param {string} reason 失败原因枚举
 * @returns {{open: null, close: null, lastEntry: null, closedOnThisDate: null,
 *            openHoursRaw: null, segments: Array, reason: string}}
 */
export function emptyOpenHours(reason) {
  return { open: null, close: null, lastEntry: null, closedOnThisDate: null, openHoursRaw: null, segments: [], reason, holidayName: null, holidayStatus: null };
}

// 【T02】默认日历查询：同步快照优先（parser 纯函数路径，绝不联网）。
// 仅在 POI 含节假日语义条款时由 parseOpenTime 调用；其余 POI 完全不碰日历。
function defaultHolidayOf(dateISO) {
  return getDefaultHolidayResolver().statusOfSnapshot(dateISO);
}

/** 两位补零时刻：7:30 → 07:30。 */
function padClock(h, m) {
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/**
 * 收集某个全局正则的全部匹配（每次新建 RegExp，避免 lastIndex 跨调用串味）。
 * @param {RegExp} re 带 g 标志的正则
 * @param {string} text 待匹配文本（已归一）
 * @returns {RegExpExecArray[]} 全部匹配
 */
function collect(re, text) {
  const rx = new RegExp(re.source, re.flags.includes('g') ? re.flags : `${re.flags}g`);
  const out = [];
  let m;
  rx.lastIndex = 0;
  while ((m = rx.exec(text)) !== null) {
    out.push(m);
    if (m[0] === '') rx.lastIndex += 1; // 防御零宽匹配死循环
  }
  return out;
}

/**
 * 文本归一（**严格等长**，保证下标可原样切片回原文）。
 * 全角数字/标点 → 半角；全角破折号（－−–—―）→ `-`；全角空格 → 空格。
 * @param {string} s 原文
 * @returns {string} 等长归一文本
 */
function normalizeOpenHoursText(s) {
  return String(s)
    .replace(/[０-９]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0))
    .replace(/：/g, ':')
    .replace(/，/g, ',')
    .replace(/；/g, ';')
    .replace(/（/g, '(')
    .replace(/）/g, ')')
    .replace(/～/g, '~')
    .replace(/[－−–—―]/g, '-')
    .replace(/　/g, ' ');
}

/**
 * 按 `；;。\n，,` 切分子句，并保留每个子句在原文中的起止下标。
 * 两处例外不切分，避免把确定性语法切坏：
 *   1. 括号内的逗号（如"（周一,周二闭馆）"）；
 *   2. 星期并集的逗号（如"周一,周四至周日"）。
 * @param {string} original 原文
 * @returns {{raw: string, text: string}[]} 子句列表（raw 为原文切片，text 为归一文本）
 */
function splitOpenHoursClauses(original) {
  const norm = normalizeOpenHoursText(original);
  const spans = [];
  let start = 0;
  let depth = 0;
  for (let i = 0; i < norm.length; i++) {
    const ch = norm[i];
    if (ch === '(') depth += 1;
    else if (ch === ')') depth = Math.max(0, depth - 1);
    const isHard = ch === ';' || ch === '。' || ch === '\n';
    const isComma = ch === ',';
    if (!isHard && !isComma) continue;
    if (isComma) {
      if (depth > 0) continue;
      const before = norm.slice(start, i).trimEnd();
      const after = norm.slice(i + 1);
      // 星期并集：前段以 周X 结尾且后段以 周X 开头 → 不切（"周一,周四至周日"）
      if (/周\s?[一二三四五六日天]$/.test(before) && /^\s*周\s?[一二三四五六日天]/.test(after)) continue;
      // 月份/日期区间并集：前段以 月/日 结尾且后段以 数字+月/日 开头 → 不切
      // 实测原文：「1月至3月,11月至12月 周一至周日 06:30-19:00」（颐和园）。
      // 若在此切分，"1月至3月" 会丢掉挂在后段的营业时间，造成**本可解析却解析不出**的漏报。
      if (/[月日]$/.test(before) && /^\s*\d{1,2}\s*[月日]/.test(after)) continue;
      // 具名节假日并集：逗号两侧都是节假日名令牌 → 不切。
      // 实测原文：「春节,劳动节,端午节 09:00–17:00开放」（苏州博物馆）。
      // 若在此切分，会把"春节" / "劳动节" 切成无时段的裸条款、时段只剩在末段上，
      // 使 openHoursRaw 只剩「端午节 09:00–17:00开放」——对用户是**残缺原文**。
      if (HOLIDAY_TOKEN_RE.end.test(before) && HOLIDAY_TOKEN_RE.start.test(after)) continue;
    }
    spans.push([start, i]);
    start = i + 1;
  }
  spans.push([start, norm.length]);
  const out = [];
  for (const [s, e] of spans) {
    const raw = original.slice(s, e).trim();
    if (!raw) continue;
    out.push({ raw, text: norm.slice(s, e).trim() });
  }
  return out;
}

/**
 * 定位关闭词所在的括号组，把子句拆成「关闭部分」与「正文」。
 *
 * 实测原文里关闭词有两种位置，语义完全不同：
 *   · 不在括号内 —— "周一全天关闭(法定节假日除外)"：整句就是关闭规则；
 *   · 在括号内   —— "夜场18:30-21:00(周一闭园)"：括号只是**该场次**的关闭日，
 *                   正文仍是营业段。若把 周一 当成营业星期，会把夜场误判成"只在周一开"。
 * @param {string} text 子句（已归一）
 * @returns {{closePart: string|null, body: string}} closePart 为 null 表示关闭词不在括号内
 */
function splitClosePart(text) {
  const m = CLOSE_RE.exec(text);
  if (!m) return { closePart: null, body: text };
  const k = m.index;
  // 向前找未闭合的 '('
  let open = -1;
  for (let i = k - 1; i >= 0; i--) {
    if (text[i] === ')') break;
    if (text[i] === '(') { open = i; break; }
  }
  if (open === -1) return { closePart: null, body: text };
  // 向后找匹配的 ')'
  let close = -1;
  for (let i = k; i < text.length; i++) {
    if (text[i] === ')') { close = i; break; }
    if (text[i] === '(') break;
  }
  if (close === -1) return { closePart: null, body: text };
  const closePart = text.slice(open, close + 1);
  const body = (text.slice(0, open) + ' ' + text.slice(close + 1)).trim();
  return { closePart, body: body || text };
}

/**
 * 解析星期集合。
 * @param {string} text 子句（已归一）
 * @returns {Set<number>|null} 1..7 的集合；null = 未限定星期（全周）
 */
function parseWeekdaySet(text) {
  const tokens = collect(WEEKDAY_TOKEN_RE, text).map((m) => ({
    value: WEEKDAY_CHAR[m[1]],
    start: m.index,
    end: m.index + m[0].length,
  }));
  if (!tokens.length) return null;
  const set = new Set();
  let i = 0;
  while (i < tokens.length) {
    const cur = tokens[i];
    const next = tokens[i + 1];
    if (next) {
      const gap = text.slice(cur.end, next.start);
      if (/^\s*(?:至|到|-|~)\s*$/.test(gap)) {
        // 周X至周Y：循环展开（支持跨周末，如 周六至周一）
        for (let v = cur.value; ; v = (v % 7) + 1) {
          set.add(v);
          if (v === next.value) break;
        }
        i += 2;
        continue;
      }
    }
    set.add(cur.value);
    i += 1;
  }
  return set;
}

/**
 * 月日 → 可比大小的序（月*100+日）。
 * @param {number} m 月
 * @param {number} d 日
 * @returns {number} 序值
 */
function monthDayOrdinal(m, d) {
  return m * 100 + d;
}

/**
 * 构建区间；跨年（结束早于开始，或显式 次年）拆成两段。
 * @param {number} m1 始月
 * @param {number} d1 始日
 * @param {number} m2 终月
 * @param {number} d2 终日
 * @param {boolean} cross 是否显式跨年
 * @returns {{status: string, ranges: number[][]}}
 */
function buildDateRanges(m1, d1, m2, d2, cross) {
  const s = monthDayOrdinal(m1, d1);
  const e = monthDayOrdinal(m2, d2);
  if (cross || e < s) return { status: 'ok', ranges: [[s, 1231], [101, e]] };
  return { status: 'ok', ranges: [[s, e]] };
}

/**
 * 解析日期/月份区间。
 * @param {string} text 子句（已归一）
 * @returns {{status: 'none'|'ok'|'incomplete'|'ambiguous', ranges: number[][]}}
 */
function parseDateRange(text) {
  // 区间并集：多个区间之间只隔 `,`、`、`、`和/及/与` 时视为**并集**，端点明确即可判定。
  // 实测原文：「1月至3月,11月至12月 周一至周日 06:30-19:00」（颐和园）。
  // 若判为 ambiguous 会白白丢掉这类可确定性解析的样本。
  const unionOf = (hits, toRange) => {
    if (hits.length === 1) return toRange(hits[0]);
    for (let i = 0; i < hits.length - 1; i++) {
      const gap = text.slice(hits[i].index + hits[i][0].length, hits[i + 1].index);
      if (!/^\s*(?:,|、|和|及|与)\s*$/.test(gap)) return null; // 不是并集 → 真歧义
    }
    const ranges = [];
    for (const h of hits) {
      const r = toRange(h);
      if (!r || r.status !== 'ok') return null;
      ranges.push(...r.ranges);
    }
    return { status: 'ok', ranges };
  };

  const mdHits = collect(MD_RANGE_RE, text);
  if (mdHits.length) {
    const r = unionOf(mdHits, (h) => {
      const m1 = Number(h[1]);
      const d1 = Number(h[2]);
      const m2 = Number(h[4]);
      const d2 = Number(h[5]);
      const cross = Boolean(h[3]);
      const ok1 = m1 >= 1 && m1 <= 12 && d1 >= 1 && d1 <= MONTH_LAST_DAY[m1 - 1];
      const ok2 = m2 >= 1 && m2 <= 12 && d2 >= 1 && d2 <= MONTH_LAST_DAY[m2 - 1];
      if (!ok1 || !ok2) return { status: 'incomplete', ranges: [] };
      return buildDateRanges(m1, d1, m2, d2, cross);
    });
    return r || { status: 'ambiguous', ranges: [] };
  }

  // 无"月/日"字的日期区间（03-16至10-31 / 09/25-09/27）。
  // 端点不合法的命中先过滤掉，避免把时间区间误当日期区间后判成 incomplete 而整条报废。
  const slashHits = collect(SLASH_MD_RANGE_RE, text).filter((h) => {
    const a = Number(h[1]);
    const b = Number(h[2]);
    const c = Number(h[3]);
    const d = Number(h[4]);
    const ok = (m, dd) => m >= 1 && m <= 12 && dd >= 1 && dd <= MONTH_LAST_DAY[m - 1];
    return ok(a, b) && ok(c, d);
  });
  if (slashHits.length) {
    const r = unionOf(slashHits, (h) => {
      const m1 = Number(h[1]);
      const d1 = Number(h[2]);
      const m2 = Number(h[3]);
      const d2 = Number(h[4]);
      // 结束早于开始 → 跨年（如 11-01至03-15）
      return buildDateRanges(m1, d1, m2, d2, false);
    });
    return r || { status: 'ambiguous', ranges: [] };
  }

  const mmHits = collect(MM_RANGE_RE, text);
  if (mmHits.length) {
    const r = unionOf(mmHits, (h) => {
      const m1 = Number(h[1]);
      const m2 = Number(h[2]);
      if (m1 < 1 || m1 > 12 || m2 < 1 || m2 > 12) return { status: 'incomplete', ranges: [] };
      // 月份区间：3–10月 = 3/1 起至 10 月最后一日
      return buildDateRanges(m1, 1, m2, MONTH_LAST_DAY[m2 - 1], false);
    });
    return r || { status: 'ambiguous', ranges: [] };
  }

  return { status: SEASON_HINT_RE.test(text) ? 'incomplete' : 'none', ranges: [] };
}

/**
 * 解析营业时间段（全部，供"多时段 → 放弃"判据使用）。
 * @param {string} text 子句（已归一）
 * @returns {{openText: string, closeText: string, openMin: number, closeMin: number, valid: boolean}[]}
 */
function parseTimeWindows(text) {
  return collect(WINDOW_RE, text).map((m) => {
    const oh = Number(m[1]);
    const om = Number(m[2]);
    const ch = Number(m[3]);
    const cm = Number(m[4]);
    // 24:00 只作为**收尾时刻**合法（实测"周一至周日 00:00-24:00"，广州长隆）
    const valid = oh >= 0 && oh <= 23 && om >= 0 && om <= 59 &&
        ch >= 0 && ch <= 24 && cm >= 0 && cm <= 59 && (ch < 24 || cm === 0);
    return { openText: padClock(oh, om), closeText: padClock(ch, cm), openMin: oh * 60 + om, closeMin: ch * 60 + cm, valid };
  });
}

/**
 * 解析停止入场时刻（时刻在前与在后两种表达，去重）。
 * @param {string} text 子句（已归一）
 * @returns {{text: string, minutes: number, valid: boolean}[]}
 */
function parseLastEntries(text) {
  const out = [];
  for (const m of collect(LAST_ENTRY_PREFIX_RE, text)) {
    const h = Number(m[1]);
    const mi = Number(m[2]);
    out.push({ text: padClock(h, mi), minutes: h * 60 + mi, valid: h >= 0 && h <= 23 && mi >= 0 && mi <= 59 });
  }
  for (const m of collect(LAST_ENTRY_SUFFIX_RE, text)) {
    const h = Number(m[1]);
    const mi = Number(m[2]);
    out.push({ text: padClock(h, mi), minutes: h * 60 + mi, valid: h >= 0 && h <= 23 && mi >= 0 && mi <= 59 });
  }
  const seen = new Set();
  return out.filter((x) => {
    if (seen.has(x.text)) return false;
    seen.add(x.text);
    return true;
  });
}

/**
 * 单子句分析（纯函数，无副作用）。
 * @param {string} text 子句（已归一）
 * @returns {object} 子句特征
 */
function analyzeOpenHoursClause(text) {
  const close = CLOSE_RE.test(text);
  const { closePart, body } = splitClosePart(text);
  // 关闭词在括号内 → 该星期是"这一段的关闭日"，不是营业星期（见 splitClosePart 注释）
  const closeWeekdays = close ? (closePart ? parseWeekdaySet(closePart) : parseWeekdaySet(body)) : null;
  const range = parseDateRange(body);
  const windows = parseTimeWindows(body);
  // 关闭词不在括号内、且本句带营业段时（如 "09:00-17:00 周一闭馆"），
  // 星期令牌属于**关闭规则**而非营业星期 → 营业星期视为不限（否则会把周一之外全部误判为不开放）
  const weekdays = close && !closePart && windows.length >= 1 ? null : parseWeekdaySet(body);
  // 【T02】节假日语义归一：把"节假日"从「放弃信号」升级为「日历闸门信号」（设计 §1.3 / §1.4 / §3.1）。
  // 旧实现只有 holidayExcept / holidayNamed 两个布尔，且遇节假日条款就整条放弃；
  // 现归一成四态语义，交由统一闸门按 calendar 裁决。
  const namedHolidayMatches = extractHolidayNames(text);
  const hasHolidayWord = HOLIDAY_RE.test(text) || namedHolidayMatches.length > 0;
  const hasExcept = HOLIDAY_EXCEPT_RE.test(text);
  let holidaySemantics = 'none';
  let holidayNames = namedHolidayMatches;
  let holidayGeneric = false;
  if (NOTICE_RE.test(text)) {
    holidaySemantics = 'notice';
  } else if (hasHolidayWord) {
    if (hasExcept) {
      holidaySemantics = 'excluded_close';
    } else {
      holidaySemantics = 'holiday_open';
      holidayGeneric = holidayNames.length === 0; // 无具名 → 泛指（「法定节假日」）
    }
  }
  return {
    close,
    closeWeekdays,
    // "周一全天关闭" 含"全天"但不是 24 小时营业，必须先排除关闭子句
    allDay: !close && ALL_DAY_RE.test(body),
    rangeStatus: range.status,
    ranges: range.ranges,
    weekdays,
    windows,
    lastEntries: parseLastEntries(body),
    holidaySemantics,
    holidayNames,
    holidayGeneric,
    notice: NOTICE_RE.test(text),
  };
}

/**
 * 校验 ISO 日期并给出（UTC 基准的）星期与月日序。
 * @param {string|null} iso yyyy-MM-dd
 * @returns {{year: number, month: number, day: number, weekday: number, md: number}|null}
 */
function parseIsoDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso == null ? '' : iso).trim());
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  const dt = new Date(Date.UTC(y, mo - 1, d));
  // 拒绝 2026-02-30 这类会被 Date 静默进位的非法日期
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null;
  const dow = dt.getUTCDay();
  return { year: y, month: mo, day: d, weekday: dow === 0 ? 7 : dow, md: monthDayOrdinal(mo, d) };
}

/**
 * 取营业时间原文：优先非空字符串 `opentime2`，缺失才兼容简单 `open_time`。
 * 数组（含空数组 `[]`）、空串、数字、对象一律视为**缺失**（拒绝数组 truthy 陷阱）。
 * @param {object} poi 高德原始 POI 或已归一的 POI（含 _openHoursSource）
 * @returns {string|null} 原文或 null
 */
export function openHoursSourceOf(poi) {
  if (!poi || typeof poi !== 'object') return null;
  if (typeof poi._openHoursSource === 'string' && poi._openHoursSource.trim() !== '') return poi._openHoursSource;
  const be = poi.biz_ext;
  if (be && typeof be === 'object') {
    for (const key of ['opentime2', 'open_time']) {
      const v = be[key];
      if (typeof v === 'string' && v.trim() !== '') return v;
    }
  }
  // 容错：个别上游把字段放在顶层
  for (const key of ['opentime2', 'open_time']) {
    const v = poi[key];
    if (typeof v === 'string' && v.trim() !== '') return v;
  }
  return null;
}

/**
 * POI 上是否存在营业时间键（哪怕值是 `[]`）—— 用于区分"无此字段"与"字段不是字符串"。
 * @param {object} poi POI
 * @returns {boolean} 是否存在键
 */
function hasOpenHoursKey(poi) {
  if (!poi || typeof poi !== 'object') return false;
  const be = poi.biz_ext;
  if (be && typeof be === 'object' && ('opentime2' in be || 'open_time' in be)) return true;
  return 'opentime2' in poi || 'open_time' in poi || '_openHoursSource' in poi;
}

/**
 * 【SR-OH1】日期感知营业时间解析（纯函数，可单测）。
 *
 * 输入高德原始 POI（或已归一 POI）与目标日期 `yyyy-MM-dd`，输出：
 *   open / close / lastEntry / closedOnThisDate / openHoursRaw / segments
 *
 * 多时段约定（**结构性防假阳性**）：
 *   · 单时段 → open/close 有值，segments 长度 1；
 *   · 多时段 → open/close **强制为 null**，只由 segments 承载，使调用方不可能
 *     把首段打烊时刻（如 14:00）误当成当日打烊时刻；
 *   · 判据为"到达时刻落在 segments 中**任一段**内"。
 * 任一项不确定 → 五字段全 null 且 segments 为 []（closedOnThisDate 三态：true/false/null）。
 *
 * @param {object} poi POI
 * @param {string|null} dateISO 目标日期 yyyy-MM-dd
 * @returns {{open: string|null, close: string|null, lastEntry: string|null,
 *            closedOnThisDate: boolean|null, openHoursRaw: string|null,
 *            segments: Array<{open: string, close: string, lastEntry: string|null}>, reason: string}}
 */
export function parseOpenTime(poi, dateISO = null, ctx = {}) {
  const source = openHoursSourceOf(poi);
  if (source === null) return emptyOpenHours(hasOpenHoursKey(poi) ? 'source_not_string' : 'no_source');
  const date = parseIsoDate(dateISO);
  if (!date) return emptyOpenHours('invalid_date');

  const clauses = splitOpenHoursClauses(source).map((c) => ({ ...c, info: analyzeOpenHoursClause(c.text) }));
  if (!clauses.length) return emptyOpenHours('empty_source');

  // ---- 全局保守拦截：原文语法本身不可确定，直接放弃，不做任何猜测 ----
  // 注意：**多时段与 24 小时不再在此放弃** —— 前者由 segments 承载，后者是确定性语义。
  for (const c of clauses) {
    if (c.info.rangeStatus === 'incomplete') return emptyOpenHours('incomplete_season_range');
    if (c.info.rangeStatus === 'ambiguous') return emptyOpenHours('ambiguous_season_range');
    if (c.info.windows.some((w) => !w.valid)) return emptyOpenHours('invalid_window');
    if (c.info.lastEntries.some((x) => !x.valid)) return emptyOpenHours('invalid_last_entry');
  }
  // 注：**不再**因为"一句多段"或"一句多个停止入场时刻"整体放弃 —— 多段由 segments 承载，
  // 停止入场时刻无法归属到具体某一段时置 null（见下方 le 取值），不制造错误信息。

  const rangeHit = (info) => (info.rangeStatus === 'none' ? true : info.ranges.some(([s, e]) => date.md >= s && date.md <= e));
  const weekdayHit = (info) => info.weekdays === null || info.weekdays.has(date.weekday);

  // ---- 统一闸门（T02）：节假日语义条款 → 必须先过权威日历 ----
  // 仅当存在「当日适用（rangeHit && weekdayHit）且节假日语义 != none」的条款时才查日历；
  // 绝大多数 POI 无节假日条款 → 完全不碰日历（零开销、零网络）。
  const holidayOf = (typeof ctx === 'object' && ctx && typeof ctx.holidayOf === 'function')
    ? ctx.holidayOf
    : defaultHolidayOf;
  const gated = clauses.filter((c) => rangeHit(c.info) && weekdayHit(c.info) && c.info.holidaySemantics !== 'none');
  let gateStatus = 'no_gate';
  let hCal = { status: 'non_holiday', name: null };
  if (gated.length) {
    try {
      hCal = holidayOf(dateISO) || { status: 'unknown', name: null };
    } catch {
      hCal = { status: 'unknown', name: null };
    }
    if (hCal.status === 'unknown') return emptyOpenHours('holiday_needs_calendar');
    gateStatus = hCal.status; // 'holiday' | 'non_holiday'
  }
  const isHoliday = gateStatus === 'holiday';
  const calName = isHoliday ? (hCal.name || null) : null;
  let excludedCloseTriggered = false;

  // 每条款在此日期的"解析角色"（设计 §1.3 / §1.4）：
  //   plain            → 按纯文本逻辑（节假日语义忽略）
  //   excluded_lifted  → 除外型闭馆在节假日失效：不产 closed=true；其营业段（若有）照常适用
  //   holiday_open_hit → 具名/泛指排班命中：套用其营业段
  //   notice_skip      → 官方通知型：不信赖任何时段（无依据）
  //   suppress         → 具名排班未命中今日 / 非节假日日其条款本就不适用 → 不参与
  function clauseMode(c) {
    const sem = c.info.holidaySemantics;
    if (sem === 'none') return 'plain';
    if (!isHoliday) {
      // 设计 §1.3：non_holiday → 丢弃"节假日限定"语义，按纯文本解析。但**不能一刀切当 plain**，
      // 三类条款在平日的时段归属完全不同（T03 实测出的 P0「显示错」）：
      //   · excluded_close（「周一闭馆(法定节假日除外)」）：限定只管节假日；平日它就是一条普通闭馆句
      //     → plain（保留 P0-1 收益：非节假日周一给出 closed=true，不再整体返 null）
      //   · notice（「周二至周日 09:00-17:00（节假日另行通知）」）："另行通知"只覆盖节假日，
      //     平日时段仍然有效 → plain（否则平日会被误判成无时段，是新的误伤）
      //   · holiday_open（「劳动节 07:30-20:00开放」）：该时段是**节假日专属**，
      //     平日套用就是"显示错" → suppress
      //     例外：若该 clause 自带星期限定（如「周二至周日 09:00-17:00 法定节假日正常开放」），
      //     说明时段由星期管辖、节假日字样只是"顺带延长"，平日仍应生效 → plain
      if (sem === 'holiday_open' && c.info.windows.length > 0 && c.info.weekdays === null) {
        return 'suppress';
      }
      return 'plain';
    }
    if (sem === 'excluded_close') return 'excluded_lifted';
    if (sem === 'notice') return 'notice_skip';
    // holiday_open：泛指或名称集合命中今日 → 套用；否则抑制
    if (c.info.holidayGeneric || c.info.holidayNames.length === 0) return 'holiday_open_hit';
    if (calName && c.info.holidayNames.includes(calName)) return 'holiday_open_hit';
    return 'suppress';
  }
  // 节假日状态码（设计 §0.5）：② 优先（除外型失效），否则逢节假日记为 'holiday'；无节假日条款则 'none'
  function finalHolidayStatus() {
    if (excludedCloseTriggered) return 'holiday_excluded_close';
    if (isHoliday && gated.length > 0) return 'holiday';
    return 'none';
  }

  // 节假日"开放"信号预扫描（设计 §1.4 优先级：C 具名/泛指排班 > 常规条款 > A 失效）：
  //   holidayOpenApplies    → 当日存在适用的 C 类排班（具名命中或泛指「正常开放」）→
  //                           抑制无条件闭馆句，并放宽常规营业段的星期限制（覆盖周一闭馆等常规排除）
  //   excludedCloseTriggered → 当日存在适用的 A 类除外型闭馆（节假日失效）→ 抑制无条件闭馆句
  //                           （但**不**放宽，因无"正常开放"明示）
  let holidayOpenApplies = false;
  let holidayNoticeApplies = false;
  for (const c of gated) {
    const m = clauseMode(c);
    if (m === 'holiday_open_hit') holidayOpenApplies = true;
    if (m === 'excluded_lifted') excludedCloseTriggered = true;
    if (m === 'notice_skip') holidayNoticeApplies = true;
  }
  const holidaySuppressClose = holidayOpenApplies || excludedCloseTriggered;

  // ---- 1. 24 小时 / 全天开放：确定性语义，识别为 00:00-24:00 单段 ----
  const allDayHits = clauses.filter((c) => c.info.allDay && rangeHit(c.info) && weekdayHit(c.info) && clauseMode(c) === 'plain');
  if (allDayHits.length) {
    return {
      open: ALL_DAY_SEGMENT.open,
      close: ALL_DAY_SEGMENT.close,
      lastEntry: null,
      closedOnThisDate: false,
      openHoursRaw: allDayHits[0].raw,
      segments: [{ ...ALL_DAY_SEGMENT }],
      reason: 'ok',
      holidayName: null,
      holidayStatus: 'none',
    };
  }

  // ---- 2. 明确关闭子句（无营业段的纯关闭句）优先 ----
  // 关闭词自带星期（"周一全天关闭" / "(周一闭园)"）时以它为准；没有星期限定才视为整段期间全关。
  const closeWdHit = (info) => (info.closeWeekdays ? info.closeWeekdays.has(date.weekday) : weekdayHit(info));
  // 【防假阳性】纯关闭句必须**带星期或日期区间**才算排期性闭馆。
  // 实测反例（苏州博物馆）："……如本馆遇有重大活动或重要设备设施维修保养时，可根据需要临时闭馆，
  // 届时将告示公众。" 含"闭馆"但既无星期也无日期 → 若当成排期闭馆，会**每一天都被判闭馆**
  // （阻塞级错误）。这类条件句一律不产出 closedOnThisDate。
  const isScheduled = (info) => info.weekdays !== null || info.rangeStatus === 'ok';
  const closeHits = clauses.filter((c) => {
    if (clauseMode(c) !== 'plain') return false; // 节假日语义条款不在此产出 closed=true
    if (holidaySuppressClose) return false;       // 节假日开放/除外失效信号抑制无条件闭馆句（设计 §1.4）
    return c.info.close && c.info.windows.length === 0 &&
        isScheduled(c.info) && rangeHit(c.info) && closeWdHit(c.info);
  });
  if (closeHits.length) {
    // 明确闭馆 = 成功解析：三个时刻为 null，segments 为空，raw 为关闭原文切片
    return { open: null, close: null, lastEntry: null, closedOnThisDate: true, openHoursRaw: closeHits[0].raw, segments: [], reason: 'closed', holidayName: calName, holidayStatus: finalHolidayStatus() };
  }

  // ---- 3. 收集该日期全部适用营业段（多时段：合并而非放弃）----
  // 统一闸门已裁决 isHoliday / calName；此处按 clauseMode 逐条款归类（设计 §1.3 / §1.4）：
  //   plain / holiday_open_hit → 营业段入 entries（holiday_open_hit 套用其时段；plain 按纯文本）
  //   excluded_lifted         → 除外型闭馆失效：标记失效；其自身为关闭句（无营业段），不产出 closed=true
  //   suppress / notice_skip  → 不参与（不贡献营业段，也不进 excludedByClose）
  const entries = [];
  const excludedByClose = [];
  for (const c of clauses) {
    const mode = clauseMode(c);
    if (mode === 'excluded_lifted') {
      // 除外型闭馆在节假日失效：标记失效；关闭句无营业段，绝不在此产出 closed=true
      excludedCloseTriggered = true;
      continue;
    }
    if (mode === 'suppress' || mode === 'notice_skip') continue;
    if (!rangeHit(c.info)) continue;
    if (c.info.windows.length === 0) continue;
    if (c.info.closeWeekdays && c.info.closeWeekdays.has(date.weekday)) {
      // 括号里的关闭日属于**这一段**（如"夜场(周一闭园)"）→ 该段在该星期不适用
      if (holidaySuppressClose) {
        // 节假日开放信号解除关闭日限制：营业段照常适用（不 continue，落到下方入段）；仅不进 excludedByClose
      } else {
        excludedByClose.push(c);
        continue;
      }
    }
    // 星期范围未命中：不反推闭馆，保持未知；但节假日"正常开放"信号可放宽（覆盖周一闭馆等常规排除）
    if (!weekdayHit(c.info) && !(holidayOpenApplies && mode === 'plain')) continue;
    // 停止入场时刻多于一个时无法归属到具体某一段 → 置 null（丢 lastEntry 不造错误信息）
    const le = c.info.lastEntries.length === 1 ? c.info.lastEntries[0] : null;
    for (const w of c.info.windows) {
      if (!(w.openMin < w.closeMin)) return emptyOpenHours('invalid_window');
      if (le && (le.minutes < w.openMin || le.minutes > w.closeMin)) return emptyOpenHours('invalid_last_entry');
      entries.push({
        open: w.openText, close: w.closeText, lastEntry: le ? le.text : null,
        openMin: w.openMin, closeMin: w.closeMin, raw: c.raw,
      });
    }
  }

  // 该日期一段都不适用：
  if (entries.length === 0) {
    // ② 除外型在节假日失效 / 节假日开放信号：原文有"节假日除外 / 正常开放"字样且当日是节假日
    //   → 无法据原文给出具体时段，故开放但不给时段（closedOnThisDate=false, segments=[]）。
    if (excludedCloseTriggered) {
      return { open: null, close: null, lastEntry: null, closedOnThisDate: false, openHoursRaw: null, segments: [], reason: 'holiday_excluded_open', holidayName: calName, holidayStatus: finalHolidayStatus() };
    }
    // 存在被"明确关闭文字"排除掉的段 → 走闭馆语义（有原文证据，不是反推）
    if (excludedByClose.length) {
      return { open: null, close: null, lastEntry: null, closedOnThisDate: true, openHoursRaw: excludedByClose[0].raw, segments: [], reason: 'closed', holidayName: calName, holidayStatus: finalHolidayStatus() };
    }
    // ③ 逢节假日但时段无依据：有"正常开放"明示却无具体时段（C 类排班命中但无营业段）
    if (holidayOpenApplies) {
      return { open: null, close: null, lastEntry: null, closedOnThisDate: false, openHoursRaw: null, segments: [], reason: 'holiday_open_no_hours', holidayName: calName, holidayStatus: finalHolidayStatus() };
    }
    // ③ 逢节假日且当日唯一匹配条款是"另行通知"型（节假日另行通知）→ 无依据时段，
    //   诚实返回 official_notice（五字段 null），而非 no_matching_clause（后者语义偏"无任何条款"）。
    //   设计 §1.3：notice 在节假日一律不信赖任何时段，故不套用其营业段，也不反推闭馆。
    if (holidayNoticeApplies) {
      return emptyOpenHours('official_notice');
    }
    return emptyOpenHours('no_matching_clause');
  }

  // 去重 + 按开门时刻排序，保证相同输入 → 相同输出
  const seen = new Set();
  const segments = entries
    .filter((e) => {
      const k = `${e.open}-${e.close}`;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    })
    .sort((a, b) => a.openMin - b.openMin || a.closeMin - b.closeMin)
    .map((e) => ({ open: e.open, close: e.close, lastEntry: e.lastEntry }));
  const raws = [...new Set(entries.map((e) => e.raw))];

  if (segments.length === 1) {
    return {
      open: segments[0].open,
      close: segments[0].close,
      lastEntry: segments[0].lastEntry,
      closedOnThisDate: false,
      openHoursRaw: raws.join('；'),
      segments,
      reason: 'ok',
      holidayName: calName,
      holidayStatus: finalHolidayStatus(),
    };
  }
  // 多时段：open/close 必须为空，且 lastEntry 只在"能明确归属整日"时才给 —— 各段自带 lastEntry
  return {
    open: null,
    close: null,
    lastEntry: null,
    closedOnThisDate: false,
    openHoursRaw: raws.join('；'),
    segments,
    reason: 'ok_multi_segment',
    holidayName: calName,
    holidayStatus: finalHolidayStatus(),
  };
}

function toMin(hhmm) {
  if (!hhmm) return null;
  const [h, mi] = hhmm.split(':').map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(mi)) return null;
  return h * 60 + mi;
}

function fmt(min) {
  const m = ((min % 1440) + 1440) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(Math.round(m % 60)).padStart(2, '0')}`;
}

function ratingOf(poi) {
  const r = parseFloat(poi.biz_ext?.rating);
  return Number.isFinite(r) ? r : 0;
}

// 六类归类（与客户端 PoiClassifier 一致）：美食/住宿/游玩/购物/枢纽/其他
function classifyType(typecode = '', name = '') {
  if (typecode.startsWith('05')) return 'restaurant';
  if (typecode.startsWith('10')) return 'hotel';
  if (typecode.startsWith('06')) return 'shopping';
  if (typecode.startsWith('11') || typecode.startsWith('14') || typecode.startsWith('08') || typecode.startsWith('1902')) return 'attraction';
  if (/^(1501|1502|1503|1504)/.test(typecode)) return 'transport';
  if (!typecode) {
    if (/机场/.test(name)) return 'transport';
    if (/火车站|汽车站/.test(name)) return 'transport';
  }
  return 'other';
}

function hubKindOf(typecode = '') {
  if (typecode.startsWith('1501')) return 'airport';
  if (typecode.startsWith('1502')) return 'station';
  if (typecode.startsWith('1503')) return 'port';
  if (typecode.startsWith('1504')) return 'bus';
  return null;
}

// 同城移动方式 → TransportType
const MODE_TYPE = { walk: 'walk', transit: 'transit', drive: 'selfDrive' };
const BUDGET_LABEL = { economy: '经济', comfort: '舒适', luxury: '高档' };
const ROOM_TYPE_LABEL = { twin: '标间', family: '亲子间', king: '大床房' };

const PACE_LABEL = { relaxed: '轻松', normal: '标准', packed: '特种兵' };

// 从简短描述提取偏好线索（规则版；LLM 启用时描述会一并喂给 LLM）
function extractHints(desc = '') {
  const hints = { interests: [], pace: null, notes: [] };
  if (!desc) return hints;
  if (/亲子|带娃|孩子|小孩|遛娃|宝宝/.test(desc)) {
    hints.interests.push('fun');
    hints.notes.push('检测到亲子需求：已补充主题乐园类兴趣');
  }
  if (/老人|长辈|爸妈|父母|爷爷|奶奶|外婆|外公/.test(desc)) {
    if (!hints.pace) hints.pace = 'relaxed';
    hints.notes.push('同行有老人：已放缓节奏');
  }
  if (/特种兵|紧凑|多打卡|高强度/.test(desc)) {
    hints.pace = 'packed';
    hints.notes.push('按描述调整为特种兵节奏');
  }
  if (/慢慢|休闲|躺平|放松|不赶/.test(desc)) {
    if (!hints.pace) hints.pace = 'relaxed';
  }
  if (/博物馆|历史|人文|古迹|古镇/.test(desc)) {
    hints.interests.push('culture', 'museum');
    hints.notes.push('检测到人文偏好：已补充历史/博物馆兴趣');
  }
  if (/拍照|摄影|出片|风景|自然/.test(desc)) hints.interests.push('nature');
  if (/购物|逛街|买买买/.test(desc)) hints.interests.push('shopping');
  if (/文艺|艺术|文创/.test(desc)) hints.interests.push('arts');
  if (/美食|小吃|觅食|好吃|吃货/.test(desc)) {
    hints.notes.push('美食偏好：餐厅推荐会更注重本地特色');
  }
  return hints;
}

function baseStay(poi) {
  const tc = String(poi.typecode || '');
  const name = String(poi.name || '');
  if (tc === 'rental') return 30; // 租车取车点
  if (/服务区/.test(name)) return 20; // 休息点
  if (tc === 'evcharge' || /充电站|充电桩|换电站/.test(name)) return 40; // EV 补能停留
  if (/动物园|乐园|游乐园|野生动物/.test(name) || tc.startsWith('0805')) return 210;
  if (tc.startsWith('1401')) return 100;
  if (tc.startsWith('1101')) return 90;
  if (tc.startsWith('1102')) return 120;
  if (tc.startsWith('0601')) return 90;
  if (tc.startsWith('0501') || tc.startsWith('0503')) return 75;
  return 90;
}

async function queryPois(city, q, pages = 2) {
  const out = [];
  for (let p = 1; p <= pages; p++) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const data = await amapCall('/v3/place/text', {
          keywords: q.keywords || '',
          types: q.types || '',
          city,
          citylimit: 'true',
          offset: '25',
          page: String(p),
          extensions: 'all',
        });
        if (data?.status === '1' && Array.isArray(data.pois)) {
          if (data.pois.length) out.push(...data.pois);
          if (data.pois.length || p > 1) break; // 空结果重试一次
        } else break;
      } catch {
        if (attempt === 0) { await new Promise((r) => setTimeout(r, 400)); continue; }
        break;
      }
    }
  }
  return out;
}

// 【SR-02】高德 `biz_ext.cost` 的两种形态必须归一：
//   有值 → 字符串（餐饮实测 `"150.00"`，酒店历史口径 `"300-500"`）
//   无值 → **空数组 `[]`**（FX-06a 探针实测酒店/景点 0/20 全空）
// `[]` 在 JS 里是 **truthy**，直接透传会让下游 `if (h.cost)` 拼出悬空的「¥」（见 SR-04），
// 也会让客户端拿到 `[]` 而不是 null。故统一归一为字符串或 null。
function costOf(p) {
  const c = p && p.biz_ext ? p.biz_ext.cost : undefined;
  if (typeof c === 'number' && Number.isFinite(c)) return String(c);
  if (typeof c === 'string' && c.trim() !== '') return c;
  return null; // [] / undefined / '' / 其他类型一律归 null
}

function normalizePoi(p) {
  const [lng, lat] = String(p.location || '').split(',').map(Number);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  // 【SR-OH1/T02】此处**不解析**营业时间：候选收集阶段 POI 还没分配到某一天，
  // 而季节区间与星期规则必须拿到目标日期才能判定。只暂存原文，解析延迟到 buildDay。
  const _openHoursSource = openHoursSourceOf(p);
  return {
    // 服务端内部字段：绝不进入客户端 payload（toLocation 只显式取解析结论五字段）
    _openHoursSource,
    id: p.id,
    name: p.name,
    address: typeof p.address === 'string' ? p.address : (p.address?.[0]?.value || p.address?.[0] || ''),
    lat, lng,
    city: p.cityname || p.city || '',
    district: p.adname || p.district || '',
    typecode: p.typecode || '',
    rating: ratingOf(p),
    typeText: typeof p.type === 'string' ? p.type : '',
    // 【SR-02】参考价原串透传（已归一：空数组 → null）
    cost: costOf(p),
  };
}

async function gatherCandidates(city, interestKeys, need) {
  const map = new Map();
  const seenQueries = new Set();
  for (const key of interestKeys) {
    const cfg = INTERESTS[key];
    if (!cfg) continue;
    for (const q of cfg.queries) {
      const qk = `${q.keywords}|${q.types}`;
      if (seenQueries.has(qk)) continue;
      seenQueries.add(qk);
      const pois = await queryPois(city, q, map.size < need ? 2 : 1);
      for (const raw of pois) {
        const poi = normalizePoi(raw);
        if (!poi || !poi.id) continue;
        if (poi.typecode.startsWith('99')) continue; // 门牌地址类
        if (!map.has(poi.id)) map.set(poi.id, poi);
      }
    }
    if (map.size >= need * 2) break;
  }
  // 兜底：候选太少时补通用风景名胜
  if (map.size < need) {
    const pois = await queryPois(city, { types: '110000' }, 2);
    for (const raw of pois) {
      const poi = normalizePoi(raw);
      if (poi && poi.id && !map.has(poi.id)) map.set(poi.id, poi);
    }
  }
  return [...map.values()];
}

/**
 * 就近餐厅候选。时段筛选**复用同一个日期感知 parser**，不再保留第二套简单正则
 * （设计 §1.2：禁止第二套正则；旧写法依赖恒为 null 的 closeTime，等于不筛选）。
 * @param {number} lng 经度
 * @param {number} lat 纬度
 * @param {number|null} atMin 目标时刻（当日 0 点起分钟）
 * @param {string|null} dateISO 目标日期 yyyy-MM-dd
 * @returns {Promise<object|null>} 餐厅 POI 或 null
 */
async function findNearbyRestaurant(lng, lat, atMin = null, dateISO = null) {
  try {
    const data = await amapCall('/v3/place/around', {
      location: `${lng},${lat}`,
      types: '050000',
      radius: '2500',
      offset: '15',
      page: '1',
      extensions: 'all',
      sortrule: 'distance',
    });
    const pois = (data?.pois || []).map(normalizePoi).filter(Boolean);
    if (!pois.length) return null;
    let pool = pois;
    if (atMin !== null) {
      // 优先选该时段营业中的餐厅（日期感知：同一 POI 在周一/淡季可能不营业）
      const open = pois.filter((p) => {
        const oh = parseOpenTime(p, dateISO);
        if (oh.closedOnThisDate === true) return false; // 明确闭店；null（未知）不拦
        const segs = (oh.segments || [])
          .map((s) => ({ openMin: toMin(s.open), closeMin: toMin(s.close) }))
          .filter((s) => s.openMin !== null && s.closeMin !== null);
        if (!segs.length) return true; // 未知 → 不拦，宁可漏报
        // 判据：到达时刻落在**任一段**内，且该段剩余 ≥ 60 分钟（沿用原有余量约定）
        const seg = segs.find((s) => atMin >= s.openMin && atMin <= s.closeMin);
        if (!seg) return false; // 还没开门，或已过全部时段
        return seg.closeMin - atMin >= 60;
      });
      if (open.length) pool = open;
    }
    const ranked = [...pool].sort((a, b) => (b.rating || 3.5) - (a.rating || 3.5));
    const best = ranked[0];
    return { ...best, name: best.name, type: 'restaurant' };
  } catch {
    return null;
  }
}

// 最近邻 + 2-opt（参考 TREK 的日内排序算法，锁定站点不参与）
function tourOrder(points, lockedHead = true) {
  if (points.length <= 2) return points.slice();
  const remaining = points.slice(1);
  const order = [points[0]];
  let cur = points[0];
  while (remaining.length) {
    let bi = 0, bd = Infinity;
    remaining.forEach((p, i) => {
      const d = haversineKm(cur, p);
      if (d < bd) { bd = d; bi = i; }
    });
    cur = remaining.splice(bi, 1)[0];
    order.push(cur);
  }
  // 2-opt（头部固定，保持从第一站出发）
  const cost = (arr) => {
    let s = 0;
    for (let i = 0; i < arr.length - 1; i++) s += haversineKm(arr[i], arr[i + 1]);
    return s;
  };
  let improved = true;
  let guard = 0;
  while (improved && guard++ < 20) {
    improved = false;
    for (let i = 1; i < order.length - 1; i++) {
      for (let k = i + 1; k < order.length; k++) {
        const next = order.slice();
        const seg = next.slice(i, k + 1).reverse();
        next.splice(i, k - i + 1, ...seg);
        if (cost(next) + 1e-9 < cost(order)) {
          order.splice(0, order.length, ...next);
          improved = true;
        }
      }
    }
  }
  return lockedHead ? order : order;
}

// 最远点播种 + 最近簇分配，均衡各天景点数
function clusterByDay(selected, days, cap) {
  if (days <= 1) return [selected.slice(0, cap)];
  const seeds = [];
  const pool = selected.slice();
  seeds.push(pool.shift()); // 评分最高
  while (seeds.length < Math.min(days, pool.length + 1)) {
    let bi = 0, bd = -1;
    pool.forEach((p, i) => {
      const d = Math.min(...seeds.map((s) => haversineKm(s, p)));
      if (d > bd) { bd = d; bi = i; }
    });
    seeds.push(pool.splice(bi, 1)[0]);
  }
  const clusters = seeds.map((s) => [s]);
  for (const p of pool) {
    let bi = 0, bd = Infinity;
    seeds.forEach((s, i) => {
      const d = haversineKm(s, p);
      if (d < bd) { bd = d; bi = i; }
    });
    if (clusters[bi].length < cap) clusters[bi].push(p);
    else {
      const alt = clusters.findIndex((c) => c.length < cap);
      if (alt >= 0) clusters[alt].push(p);
    }
  }
  // 补齐不足的天：复制空位
  while (clusters.length < days) clusters.push([]);
  return clusters.slice(0, days).map((c) => c.slice(0, cap + 1));
}

async function segmentMinutes(from, to, city, mode = 'transit') {
  const distKm = haversineKm(from, to);
  const walk = distKm * 1000 / 1.25 / 60; // 5km/h
  try {
    // 自驾类（纯自驾/落地租车）：统一驾车路线
    if (mode === 'drive') {
      const data = await amapCall('/v3/direction/driving', {
        origin: `${from.lng},${from.lat}`,
        destination: `${to.lng},${to.lat}`,
        strategy: '0',
        extensions: 'base',
      });
      const p = data?.route?.paths?.[0];
      const t = parseInt(p?.duration, 10);
      const d = parseFloat(p?.distance);
      if (Number.isFinite(t)) return { minutes: Math.max(3, Math.round(t / 60)), mode: 'drive', km: Number.isFinite(d) ? d / 1000 : distKm };
      return { minutes: Math.max(5, Math.round(distKm / 40 * 60 + 5)), mode: 'drive', km: distKm };
    }
    if (distKm < 1.5) {
      const data = await amapCall('/v3/direction/walking', {
        origin: `${from.lng},${from.lat}`,
        destination: `${to.lng},${to.lat}`,
        extensions: 'base',
      });
      const d = parseInt(data?.route?.paths?.[0]?.distance, 10);
      const t = parseInt(data?.route?.paths?.[0]?.duration, 10);
      if (Number.isFinite(t)) return { minutes: Math.max(3, Math.round(t / 60)), mode: 'walk', km: d / 1000 };
    }
    const data = await amapCall('/v3/direction/transit/integrated', {
      origin: `${from.lng},${from.lat}`,
      destination: `${to.lng},${to.lat}`,
      city: from.city || city,
      citydst: to.city || city,
      strategy: '0',
      extensions: 'base',
    });
    const t = parseInt(data?.route?.transits?.[0]?.duration, 10);
    const d = parseFloat(data?.route?.transits?.[0]?.distance);
    if (Number.isFinite(t)) return { minutes: Math.max(5, Math.round(t / 60)), mode: 'transit', km: d / 1000 };
  } catch { /* 估算兜底 */ }
  const est = walk > 30 ? distKm / 25 * 60 + 10 : walk;
  return { minutes: Math.max(5, Math.round(est)), mode: walk > 30 ? 'transit' : 'walk', km: distKm };
}

// 长距离自驾（>200km）自动找服务区休息点（决策#4）
async function findRestStop(from, to) {
  try {
    const midLng = (from.lng + to.lng) / 2;
    const midLat = (from.lat + to.lat) / 2;
    const data = await amapCall('/v3/place/around', {
      location: `${midLng},${midLat}`,
      keywords: '服务区',
      radius: '30000',
      offset: '5',
      page: '1',
      extensions: 'base',
      sortrule: 'distance',
    });
    const pois = (data?.pois || []).map(normalizePoi).filter(Boolean);
    return pois.length ? pois[0] : null;
  } catch {
    return null;
  }
}

// 落地租车：找取车点（决策#2：租车点=枢纽子类型 rental）
async function findRentalHub(city, near) {
  try {
    const data = await amapCall('/v3/place/around', {
      location: `${near.lng},${near.lat}`,
      keywords: '租车',
      radius: '10000',
      offset: '5',
      page: '1',
      extensions: 'base',
      sortrule: 'distance',
    });
    const pois = (data?.pois || []).map(normalizePoi).filter(Boolean);
    if (pois.length) return { ...pois[0], typecode: 'rental' };
    const text = await queryPois(city, { keywords: '租车' }, 1);
    const p = text.map(normalizePoi).find(Boolean);
    return p ? { ...p, typecode: 'rental' } : null;
  } catch {
    return null;
  }
}

// ---------- 跨城交通（班次建议 + 真实枢纽） ----------
async function geocodeCity(name) {
  try {
    const d = await amapCall('/v3/geocode/geo', { address: name });
    const g = d?.geocodes?.[0];
    if (g?.location && String(g.location).includes(',')) {
      const [lng, lat] = String(g.location).split(',').map(Number);
      if (Number.isFinite(lng) && Number.isFinite(lat)) return { lng, lat };
    }
  } catch {}
  return null;
}

function parseHm(s) {
  return toMin(String(s || ''));
}

// 用户选定的跨城工具 → 枢纽关键词/速度/图标（类型由用户选择，禁止自动推断）
const VEHICLE_CONF = {
  flight: { hubKw: '机场', fallbackCode: '150100', hubKind: 'airport', speedKmh: 800, emoji: '✈️', label: '飞机', prep: 150 },
  highSpeedTrain: { hubKw: '火车站', fallbackCode: '150200', hubKind: 'station', speedKmh: 300, emoji: '🚄', label: '高铁/火车', prep: 60 },
  train: { hubKw: '火车站', fallbackCode: '150200', hubKind: 'station', speedKmh: 220, emoji: '🚃', label: '火车', prep: 60 },
  bus: { hubKw: '汽车站', fallbackCode: '150400', hubKind: 'bus', speedKmh: 80, emoji: '🚌', label: '大巴', prep: 45 },
  ship: { hubKw: '港口', fallbackCode: '150300', hubKind: 'port', speedKmh: 40, emoji: '⛴️', label: '轮船', prep: 60 },
};

async function buildIntercityPrefix(fromCity, toCity, vehicle, warnings) {
  const conf = VEHICLE_CONF[vehicle] || VEHICLE_CONF.highSpeedTrain;
  const o = await geocodeCity(fromCity);
  const dest = await geocodeCity(toCity);
  if (!o || !dest) {
    warnings.push(`无法定位「${fromCity}→${toCity}」，请自行安排跨城交通`);
    return null;
  }
  const distKm = haversineKm(o, dest);
  let data = null;
  try {
    data = await amapCall('/v3/intercity/transit', {
      origin: `${o.lng},${o.lat}`,
      destination: `${dest.lng},${dest.lat}`,
      cityd: fromCity,
      dstd: toCity,
      strategy: '0',
      extensions: 'all',
    });
  } catch {}
  const mapLine = (x, kind) => ({
    kind,
    no: x.line_name || x.flight_no || x.train_no || '',
    dep: x.dep_time || '',
    arr: x.arr_time || '',
    dur: parseInt(x.duration, 10) || null,
    price: x.price,
    depName: x.dep_airport || x.dep_station || '',
    arrName: x.arr_airport || x.arr_station || '',
  });
  // 只在用户选定的工具类型里选班次
  const pool = vehicle === 'flight'
    ? (data?.flight || []).map((f) => mapLine(f, 'flight')).filter((l) => parseHm(l.dep) != null && parseHm(l.arr) != null)
    : (vehicle === 'bus'
        ? (data?.bus || []).map((b) => mapLine(b, 'bus')).filter((l) => parseHm(l.dep) != null && parseHm(l.arr) != null)
        : (data?.train || []).map((t) => mapLine(t, 'train')).filter((l) => parseHm(l.dep) != null && parseHm(l.arr) != null));
  pool.sort((a, b) => parseHm(a.dep) - parseHm(b.dep));

  let line;
  if (pool.length) {
    // 班次建议：优先早上出发（到达后还能玩半天）
    const morning = pool.filter((l) => {
      const m = parseHm(l.dep);
      return m >= 450 && m <= 690;
    });
    line = morning[0] || pool[0];
  } else {
    // 高德跨城班次接口需企业认证（10002）：按用户选定工具的典型速度估算时段，班次号待用户预订时填
    const dur = Math.round((distKm / conf.speedKmh) * 60 + conf.prep);
    const dep = vehicle === 'flight' ? 510 : 480;
    line = { kind: vehicle, no: '', dep: fmt(dep), arr: fmt(dep + dur), dur, price: null, depName: '', arrName: '' };
    warnings.push('跨城班次实时查询需要高德企业认证，已按你选的交通工具和典型时长生成建议时段，预订时选早班（到达后还能玩半天）');
  }
  const depMin = parseHm(line.dep);
  const arrMin = parseHm(line.arr);
  const hubKw = conf.hubKw;
  const fallbackCode = conf.fallbackCode;

  const mkHub = async (cityName, ref) => {
    const pois = await queryPois(cityName, { keywords: hubKw }, 1);
    const poi = pois.map(normalizePoi).find(Boolean);
    return {
      lng: poi ? poi.lng : ref.lng,
      lat: poi ? poi.lat : ref.lat,
      name: poi ? poi.name : `${cityName}${hubKw}`,
      address: poi ? poi.address : cityName,
      city: poi ? poi.city : cityName,
      typecode: poi && poi.typecode ? poi.typecode : fallbackCode,
      rating: poi ? poi.rating : 0,
    };
  };
  const depPoi = await mkHub(fromCity, o);
  const arrPoi = await mkHub(toCity, dest);

  // 出发枢纽：提前到达（飞机提前150分钟/火车60/大巴45），停留即候车，离开=发车
  const hubArr = depMin - conf.prep;
  const depHub = toLocation(depPoi, hubArr, conf.prep, null, {});
  depHub.transport = {
    type: 'taxi',
    scope: 'intraCity',
    durationMinutes: 90,
    departureTime: fmt(hubArr - 90),
    arrivalTime: fmt(hubArr),
  };
  // 到达枢纽：下机/出站45分钟
  const arrHub = toLocation(arrPoi, arrMin, 45, null, {});
  arrHub.transport = {
    type: vehicle,
    scope: 'intercity',
    flightNumber: line.no || null,
    departureTime: line.dep,
    arrivalTime: line.arr,
    durationMinutes: line.dur,
    price: line.price,
  };
  warnings.push(
    `跨城交通建议：${conf.emoji} ${line.no ? line.no + ' ' : ''}${fromCity} ${line.dep} → ${toCity} ${line.arr}${line.price ? `（约¥${line.price}）` : ''}，第1天行程从到达后开始`
  );
  return { depHub, arrHub, depMin, arrMin };
}

// ---------- 每晚酒店（评分 + 价格档过滤） ----------
const BUDGET_RANGE = {
  economy: { max: 250 },
  comfort: { min: 150, max: 600 },
  luxury: { min: 400 },
};

function parseCost(cost) {
  const m = String(cost || '').match(/(\d+)(?:\s*-\s*(\d+))?/);
  if (!m) return null;
  return { low: parseInt(m[1], 10), high: m[2] ? parseInt(m[2], 10) : parseInt(m[1], 10) };
}

// 【SR-04a 收敛】参考价的**展示文案唯一出口**。
//
// ⚠️ 任何"把 cost 显示给人看"的地方都**必须调本函数**，不要各自拼 `¥${cost}`：
// `biz_ext.cost` 无值时是**空数组 `[]`**，在 JS 里 truthy —— 直接写
// `if (cost) bits.push(\`¥${cost}\`)` 会拼出悬空的「¥」（本文件 :608 修掉的 bug）。
// 走 `parseCost()` 判空 + 本函数格式化，才能同时保证"无价不显示"和"区间/单值一致"。
//
// @param {string|null} cost 已由 `costOf()` 归一过的原串（`"300-500"` / `"400"` / null）
// @returns {string|null} `¥300-500` / `¥400`；**无价返回 null**，调用方据此跳过拼接。
function costText(cost) {
  const c = parseCost(cost);
  if (!c) return null;
  return c.low === c.high ? `¥${c.low}` : `¥${c.low}-${c.high}`;
}

// 星级从高德 POI 类型文本提取（“住宿服务;五星级宾馆;…”）
function starFromType(t = '') {
  if (/五星级|豪华型/.test(t)) return 5;
  if (/四星级|高档型/.test(t)) return 4;
  if (/三星级|舒适型/.test(t)) return 3;
  if (/经济型|连锁/.test(t)) return 2;
  return null;
}

const BUDGET_STARS = { economy: [2, 3], comfort: [3, 4], luxury: [4, 5] };

// 多目标酒店评分：位置(当晚余下+次日上午的加权重心) + 口碑 + 星级档 + 亲子加分
// 返回前3候选（含推荐理由），装修年份/房型库存高德无数据→靠候选对比+预订时核实
async function findHotels(anchors, budgetKey, party) {
  try {
    let W = 0, lng = 0, lat = 0;
    for (const a of anchors) {
      W += a.w;
      lng += a.poi.lng * a.w;
      lat += a.poi.lat * a.w;
    }
    const c = { lng: lng / W, lat: lat / W };
    const data = await amapCall('/v3/place/around', {
      location: `${c.lng.toFixed(6)},${c.lat.toFixed(6)}`,
      types: '100000',
      radius: '10000',
      offset: '25',
      page: '1',
      extensions: 'all',
      sortrule: 'weight',
    });
    const hotels = (data?.pois || [])
      .map((p) => normalizePoi(p)) // cost 已在 normalizePoi 内归一（SR-02），此处不再重复赋值
      .filter(Boolean);
    if (!hotels.length) return [];

    // 价格档宽松过滤：档内优先，无档内则任何有价格的，再不行全部
    const range = BUDGET_RANGE[budgetKey];
    let pool = hotels.filter((h) => {
      const cst = parseCost(h.cost);
      if (!cst) return false;
      if (range.max != null && cst.low > range.max) return false;
      if (range.min != null && cst.high < range.min) return false;
      return true;
    });
    if (!pool.length) pool = hotels.filter((h) => parseCost(h.cost));

    // 【SR-04b】FX-06a 探针实测：酒店 `biz_ext.cost` **0/20 全空** → 上面两级价格过滤
    // 必然落空，最终 `pool = hotels` 全量，预算档（economy/comfort/luxury）对选酒店
    // **零影响** —— 这是创建页与 PRD 明确承诺的能力，属承诺落空而非技术瑕疵。
    // 兜底：价格不可用时改用**星级档**过滤，星级来自高德 POI 类型文本（`p.type`，
    // 与 `cost` 无关，不受"酒店无价格源"影响），且 `BUDGET_STARS` 与下方评分用的是
    // 同一张表，口径一致。仍为空才退回全量（优雅降级，不会比修复前更差）。
    let budgetBasis = 'price';
    if (!pool.length) {
      budgetBasis = 'star';
      const stars = BUDGET_STARS[budgetKey] || [];
      pool = hotels.filter((h) => stars.includes(starFromType(h.typeText || '')));
    }
    if (!pool.length) {
      budgetBasis = 'none';
      pool = hotels;
    }

    // 位置分：到锚点集合的加权距离（越小越好，min-max 归一）
    const weightedDist = (h) => anchors.reduce((s, a) => s + a.w * haversineKm(h, a.poi), 0);
    const dists = pool.map(weightedDist);
    const minD = Math.min(...dists), maxD = Math.max(...dists);
    const normPos = (v) => (maxD > minD ? 1 - (v - minD) / (maxD - minD) : 1);

    const targetStars = BUDGET_STARS[budgetKey] || [3, 4];
    const scored = pool.map((h) => {
      const posScore = normPos(weightedDist(h));
      const ratingScore = Math.min(1, (h.rating || 3.5) / 5);
      const star = starFromType(h.typeText || '');
      const starScore = star == null ? 0.4 : targetStars.includes(star) ? 1 : Math.min(Math.abs(star - targetStars[0]), Math.abs(star - targetStars[1])) === 1 ? 0.6 : 0.2;
      const familyBonus = party.children > 0 && /亲子|家庭|套房|公寓/.test(h.name) ? 0.12 : 0;
      const total = 0.45 * posScore + 0.3 * ratingScore + 0.15 * starScore + familyBonus;

      const nearest = Math.min(...anchors.map((a) => haversineKm(h, a.poi)));
      const bits = [`位置${posScore >= 0.66 ? '优' : posScore >= 0.33 ? '良' : '一般'}·距行程点${nearest.toFixed(1)}km`];
      if (h.rating) bits.push(`口碑${h.rating}`);
      // 【SR-04a】旧写法 `if (h.cost) bits.push(\`¥${h.cost}\`)` 会拼出**悬空的 ¥**：
      // `biz_ext.cost` 无值时是空数组 `[]`，在 JS 里 truthy → 推荐理由变成
      // 「位置优·口碑4.6·¥·四星」。现在统一走 `costText()` —— 与 :581/:587 的
      // `parseCost()` 同一套口径，且无价返回 null → 整段跳过，不拼接。
      const costLabel = costText(h.cost);
      if (costLabel) bits.push(costLabel);
      if (star) bits.push(star === 5 ? '五星' : star === 4 ? '四星' : star === 3 ? '三星' : '经济连锁');
      if (familyBonus) bits.push('或有亲子房型');
      // 【SR-04b 诚实降级】预算档没有按价格生效时，明说是按什么匹配的，不假装按价格选过
      if (budgetBasis === 'star') bits.push('档位按星级匹配（参考价缺失）');
      else if (budgetBasis === 'none') bits.push('档位未生效（参考价与星级均不可用）');
      return { poi: h, score: total, reason: bits.join('·') };
    });
    scored.sort((a, b) => b.score - a.score);
    return scored.slice(0, 3);
  } catch {
    return [];
  }
}

async function buildDay(dayIndex, dateStr, points, { pace, city, warnings, tripMode = 'pureTransit', startClock = null, origin = null }) {
  if (!points.length) return { date: dateStr, dayNumber: dayIndex + 1, locations: [] };
  const driveMode = tripMode === 'pureDrive' || tripMode === 'transitPlusRental';
  const ordered = tourOrder(points);
  let clock = startClock ?? START_CLOCK[pace];
  const locations = [];
  let prev = null;
  let lunchDone = false, dinnerDone = false;
  const mealLimit = { lunch: 13 * 60, dinner: 17 * 60 + 45 };

  const pushLoc = async (poi, travel, extra = {}) => {
    if (travel) {
      clock += travel.minutes;
    }
    const stay = extra.stayOverride ?? Math.round((baseStay({ typecode: poi.typecode || '', name: poi.name }) * STAY_FACTOR[pace]) / 15) * 15;
    const arrival = clock;
    // 【SR-OH1/T02】按**目标日期**解析一次营业时间，注入 toLocation；
    // poi 上已不再有 openTime/closeTime（normalizePoi 只暂存 _openHoursSource）。
    const openHours = extra.openHours || parseOpenTime(poi, dateStr);
    const closeMin = toMin(openHours.close);
    if (closeMin !== null && arrival + stay > closeMin) {
      if (closeMin - arrival >= 45) {
        // 压缩停留时长以适应打烊
        const fit = Math.max(45, closeMin - arrival - 10);
        locations.push(toLocation(poi, arrival, fit, travel, { ...extra, openHours }));
        clock = arrival + fit;
        warnings.push(`第${dayIndex + 1}天「${poi.name}」打烊较早，建议停留时长已压缩至${fit}分钟`);
        return;
      }
      warnings.push(`第${dayIndex + 1}天「${poi.name}」按当前时间排到打烊前玩不完(${openHours.close}打烊)，建议调换顺序、提前安排或替换`);
    }
    locations.push(toLocation(poi, arrival, stay, travel, { ...extra, openHours }));
    clock = arrival + stay;
  };

  for (const poi of ordered) {
    let travel = prev
        ? await segmentMinutes(prev, poi, city, driveMode ? 'drive' : 'transit')
        : (origin ? await segmentMinutes(origin, poi, city, driveMode ? 'drive' : 'transit') : null);
    // 长距离自驾（>200km）插入服务区休息点（决策#4）
    if (travel && driveMode && travel.km > 200) {
      const rest = await findRestStop(prev, poi);
      if (rest) {
        const origKm = travel.km;
        await pushLoc(rest, { minutes: Math.round(travel.minutes / 2), mode: 'drive', km: travel.km / 2 }, { stayOverride: 20 });
        warnings.push(`第${dayIndex + 1}天长距离自驾(${Math.round(origKm)}km)，已在中途插入「${rest.name}」休息20分钟`);
        travel = { minutes: Math.ceil(travel.minutes / 2), mode: 'drive', km: travel.km / 2 };
        prev = rest;
      }
    }
    if (!lunchDone && clock >= mealLimit.lunch - 60) {
      const meal = await findNearbyRestaurant(prev ? prev.lng : poi.lng, prev ? prev.lat : poi.lat, Math.max(clock, 12 * 60), dateStr);
      if (meal) {
        await pushLoc({ ...meal, typecode: '050100' }, null, { isMeal: '午餐' });
        lunchDone = true;
      } else lunchDone = true;
    }
    await pushLoc(poi, travel);
    prev = poi;
    if (lunchDone && !dinnerDone && clock >= mealLimit.dinner) {
      const meal = await findNearbyRestaurant(poi.lng, poi.lat, clock, dateStr);
      if (meal) {
        await pushLoc({ ...meal, typecode: '050100' }, { minutes: 10, mode: 'walk', km: 0.6 }, { isMeal: '晚餐' });
        dinnerDone = true;
      }
    }
  }
  // 天结束较早（如轻松节奏）时，补插入午餐
  if (!lunchDone && clock >= 12 * 60 && ordered.length) {
    const lastPoi = ordered[ordered.length - 1];
    const meal = await findNearbyRestaurant(lastPoi.lng, lastPoi.lat, Math.max(clock, 12 * 60), dateStr);
    if (meal) {
      await pushLoc({ ...meal, typecode: '050100' }, { minutes: 10, mode: 'walk', km: 0.6 }, { isMeal: '午餐' });
      lunchDone = true;
    }
  }
  // 超时裁剪：砍掉最晚的非必去景点
  while (clock > 21.5 * 60 && locations.length > 2) {
    const idx = [...locations].reverse().findIndex((l) => !l._must && l.type === 'attraction');
    if (idx < 0) break;
    const realIdx = locations.length - 1 - idx;
    const removed = locations.splice(realIdx, 1)[0];
    warnings.push(`第${dayIndex + 1}天时间超限，已移除「${removed.name}」（可手动加回）`);
    clock = locations.length ? toMin(locations[locations.length - 1].leaveTime) || clock : START_CLOCK[pace];
  }
  return { date: dateStr, dayNumber: dayIndex + 1, locations };
}

/**
 * 地点 payload。营业时间五字段来自 buildDay 已解析的一次性值 `extra.openHours`；
 * 解析失败即五字段全 null（不估算、不兜底填充）。`_openHoursSource` 原文绝不入 payload。
 * @param {object} poi 已归一 POI
 * @param {number} arrival 到达分钟
 * @param {number} stay 停留分钟
 * @param {object|null} travel 交通段
 * @param {object} extra 扩展（isMeal / must / stayOverride / openHours）
 * @returns {object} 地点 payload
 */
function toLocation(poi, arrival, stay, travel, extra = {}) {
  const openHours = extra.openHours || emptyOpenHours('not_parsed');
  return {
    name: poi.name,
    address: poi.address,
    latitude: poi.lat,
    longitude: poi.lng,
    city: poi.city,
    district: poi.district,
    type: extra.isMeal ? 'restaurant' : classifyType(poi.typecode, poi.name),
    hubKind: poi.typecode === 'rental' ? 'rental' : hubKindOf(poi.typecode),
    stayMinutes: stay,
    transportMinutes: travel ? travel.minutes : null,
    transportMode: travel ? travel.mode : null,
    transport: travel
        ? {
            type: MODE_TYPE[travel.mode] || 'other',
            scope: 'intraCity',
            durationMinutes: travel.minutes,
            distance: Math.round((travel.km || 0) * 1000),
          }
        : null,
    // 【SR-OH1/T02】日期感知营业时间结论：解析不出即 null（三态 closedOnThisDate，null≠false）
    openTime: openHours.open ?? null,
    closeTime: openHours.close ?? null,
    lastEntryTime: openHours.lastEntry ?? null,
    closedOnThisDate: openHours.closedOnThisDate ?? null,
    // 【T02】节假日关系：可选、向后兼容；老 payload 缺失 → null → 客户端按 ① 降级
    holidayName: openHours.holidayName ?? null,
    holidayStatus: openHours.holidayStatus ?? null,
    // 与结论对应的原文命中子句（原样切片），供 UI 副行核对；无证据则不展示结构化结论
    openHoursRaw: openHours.openHoursRaw ?? null,
    // 多时段：单时段时长度 1；多时段时 openTime/closeTime 为 null，只由本字段承载
    openSegments: Array.isArray(openHours.segments) ? openHours.segments.map((s) => ({ ...s })) : [],
    rating: poi.rating || null,
    // 【SR-02】参考价原串透传到地点层（已由 normalizePoi 归一：空数组 → null）。
    // 餐饮：实测 18/20 有值（人均）→ 客户端可**离线**取用，无需再打 /api/planner/prices。
    // 酒店/景点：实测 0/20 全空 → 恒 null，客户端按"暂无参考价"降级，不编造。
    cost: poi.cost || null,
    // 【可执行性校验】服务端规划时算出的时刻锚 —— 客户端 `itinerary_checker.dart`
    // 时间链的**唯一锚点**（没有它，CH-01/02/06/07/08 全部静默跳过）。
    //
    // ⚠️ **已知行为：fmt() 会 mod 1440**（见本文件 :642）。
    //    排过午夜的站会被绕回成次日凌晨 —— 真实产物里酒店 24:58 到达下发成 "00:58"。
    //    客户端不把这两个字段当绝对分钟数用：`ItinerarySlot` 保留 raw 值做绕回检测
    //    （`sourceWrapped`），并按锚单调展开后才参与比较（`_unwrapSourceArrivals`）。
    //    绕回可被检测，不会静默变成错误结论，故下发 fmt 版是可接受的。
    //
    // ⛔ `Number.isFinite` 守卫：`arrival` 在某些分支可能为 null/undefined，
    //    而 `fmt(undefined)` 会产出 `"NaN:NaN"` 这种脏值并直接进 payload
    //    （客户端 `parseClockMinutes` 会返回 null，但服务端不该先造出脏串）。
    //    同 `toMin()` 的判空口径（:638）：非有限数一律 null，不进结构化字段。
    arrivalTime: Number.isFinite(arrival) ? fmt(arrival) : null,
    leaveTime: Number.isFinite(arrival) && Number.isFinite(stay) ? fmt(arrival + stay) : null,
    mealFor: extra.isMeal || null,
    _must: extra.must || false,
  };
}

// FX-01：日期加减必须走 UTC 基准。
// 旧实现 `new Date(iso + 'T00:00:00')` 按**本地时区**解析、`toISOString()` 按 **UTC** 输出，
// 在东八区（UTC+8）每一天系统性少 1 天（10-01 + 0 天 → 09-30），在 UTC-5 则可能多算。
// 这里统一按 UTC 年月日构造（Date.UTC 会自动处理跨月/跨年/闰年进位），结果与时区无关。
// multiCity.js 从本模块 import addDays —— 改这一处即修两条管线，不要在别处另写第二份实现。
export function addDays(iso, n) {
  const head = String(iso == null ? '' : iso).slice(0, 10);
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(head);
  if (!m) return String(iso == null ? '' : iso); // 非 yyyy-MM-dd：原样返回，不静默产出错误日期
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const step = Number.isFinite(Number(n)) ? Number(n) : 0;
  return new Date(Date.UTC(y, mo - 1, d + step)).toISOString().slice(0, 10);
}

async function llmAssign(candidates, days, interestLabels, desc = '') {
  // LLM 只负责"分组与主题"，失败返回 null 由规则兜底
  try {
    const list = candidates.map((c, i) => ({ i, name: c.name, rating: c.rating, district: c.district }));
    const content = await llmChat(
      [
        { role: 'system', content: '你是旅行规划师。把给定景点分配到各天，按地理就近原则，输出JSON：{"groups":[[索引,...],...],"themes":["主题",...]}，groups数量必须等于天数，每个索引只能用一次。' },
        { role: 'user', content: JSON.stringify({ days, interests: interestLabels, 用户描述: desc || '无', places: list }) },
      ],
      { jsonMode: true }
    );
    if (!content) return null;
    const parsed = JSON.parse(content);
    if (!Array.isArray(parsed.groups) || parsed.groups.length !== days) return null;
    const groups = parsed.groups.map((g) => (Array.isArray(g) ? g.map((i) => candidates[i]).filter(Boolean) : []));
    return groups.every((g) => g.length) ? groups : null;
  } catch {
    return null;
  }
}

export async function generateTrip(input) {
  const city = String(input.city || '').trim();
  if (!city) { const e = new Error('请填写目的地城市'); e.status = 400; e.expose = true; throw e; }
  const days = Math.min(10, Math.max(1, parseInt(input.days, 10) || 3));
  const tripMode = ['pureDrive', 'pureTransit', 'transitPlusRental'].includes(input.tripMode) ? input.tripMode : 'pureTransit';
  const warnings = [];

  // 简短描述 → 偏好线索（兴趣补充、节奏调整）
  const hints = extractHints(String(input.description || '').trim());
  let pace = ['relaxed', 'normal', 'packed'].includes(input.pace) ? input.pace : 'normal';
  let interestKeys = (Array.isArray(input.interests) && input.interests.filter((k) => INTERESTS[k]).length
    ? input.interests.filter((k) => INTERESTS[k])
    : ['nature', 'culture']);
  for (const k of hints.interests) {
    if (!interestKeys.includes(k)) interestKeys.push(k);
  }
  if (hints.pace && hints.pace !== pace) {
    warnings.push(`根据你的描述，节奏已调整为「${PACE_LABEL[hints.pace]}」`);
    pace = hints.pace;
  }
  for (const n of hints.notes) warnings.push(n);

  const startDate = /^\d{4}-\d{2}-\d{2}$/.test(input.startDate || '') ? input.startDate : addDays(new Date().toISOString().slice(0, 10), 14);

  const cap = PER_DAY_CAP[pace];
  const need = days * cap;
  let candidates = await gatherCandidates(city, interestKeys, need);
  if (candidates.length === 0) {
    const e = new Error('未搜索到可用景点，请检查城市名称');
    e.status = 404;
    e.expose = true;
    throw e;
  }

  // 必去点
  const mustList = [];
  for (const name of (Array.isArray(input.mustVisit) ? input.mustVisit.slice(0, 5) : [])) {
    const kw = String(name).trim();
    if (!kw) continue;
    const pois = await queryPois(city, { keywords: kw }, 1);
    const poi = pois.map(normalizePoi).find(Boolean);
    if (poi) {
      mustList.push(poi);
      candidates = candidates.filter((c) => c.id !== poi.id);
    } else {
      warnings.push(`未找到必去点「${kw}」，已忽略`);
    }
  }

  candidates.sort((a, b) => b.rating - a.rating);
  const selected = [...mustList, ...candidates].slice(0, need);
  const mustIds = new Set(mustList.map((m) => m.id));
  if (selected.length < days * 2) warnings.push('候选景点偏少，已放宽数量，可尝试增加天数或兴趣类型');

  let groups;
  let source = 'rule';
  if (isLlmEnabled()) {
    const assigned = await llmAssign(selected, days, interestKeys.map((k) => INTERESTS[k].label), String(input.description || '').trim());
    if (assigned) { groups = assigned; source = 'llm+rule'; }
  }
  if (!groups) groups = clusterByDay(selected, days, cap);

  // 出行人数/房型/预算（决策#5）
  const party = {
    adults: Math.max(1, parseInt(input.adults, 10) || 2),
    children: Math.max(0, parseInt(input.children, 10) || 0),
    rooms: Math.max(1, parseInt(input.rooms, 10) || 1),
    roomType: ['twin', 'family', 'king'].includes(input.roomType) ? input.roomType : null,
  };
  const budget = ['economy', 'comfort', 'luxury'].includes(input.budget) ? input.budget : 'comfort';
  const driveMode = tripMode === 'pureDrive' || tripMode === 'transitPlusRental';

  // 跨城交通：用户选定工具类型，AI 只建议班次（决策#3修正：类型禁止自动推断）
  const fromCity = String(input.fromCity || '').trim();
  const intercityVehicle = ['flight', 'highSpeedTrain', 'train', 'bus', 'ship'].includes(input.intercityVehicle)
    ? input.intercityVehicle
    : 'highSpeedTrain';
  let prefix = null;
  if (fromCity && fromCity.replace(/(市|地区|自治州)$/, '') !== city.replace(/(市|地区|自治州)$/, '')) {
    prefix = await buildIntercityPrefix(fromCity, city, intercityVehicle, warnings);
  }

  // 落地租车：第1天首位插入取车点（枢纽子类型 rental，决策#2）
  if (tripMode === 'transitPlusRental' && groups[0]?.length) {
    const rental = await findRentalHub(city, groups[0][0]);
    if (rental) {
      groups[0].unshift({ ...rental, typecode: 'rental', rating: 0 });
      warnings.push(`已插入取车点「${rental.name}」，取车后同城均按自驾计算`);
    } else {
      warnings.push('未找到合适租车点，请到达后自行安排取车');
    }
  }

  const dayResults = [];
  let prevHotel = null;
  for (let i = 0; i < days; i++) {
    const isLastDay = i === days - 1;
    let pts = (groups[i] || []).map((p) => ({ ...p, _must: mustIds.has(p.id) }));
    let startClock = null;
    if (i === 0 && prefix) {
      // 第1天从到达后开始，按剩余时间裁剪景点数
      startClock = Math.min(prefix.arrMin + 45, 20 * 60);
      const remainH = Math.max(0.5, (20 * 60 - startClock) / 60);
      const cap1 = Math.max(1, Math.floor(remainH / 2.8));
      if (pts.length > cap1) pts = pts.slice(0, cap1);
    }
    dayResults.push(
      await buildDay(i, addDays(startDate, i), pts, { pace, city, warnings, tripMode, startClock, origin: prevHotel })
    );
    const day = dayResults[dayResults.length - 1];

    // 每晚酒店：多目标评分（当晚余下+次日上午的加权重心），给三个候选可切换（决策#4升级）
    if (!isLastDay) {
      const dayPts = (groups[i] || []).filter((p) => p.lat && p.lng);
      const nextPts = ((groups[i + 1] || []).filter((p) => p.lat && p.lng)).slice(0, 2);
      const travelOrigin = dayPts.length ? dayPts[dayPts.length - 1] : prevHotel;
      const anchors = [];
      if (travelOrigin) anchors.push({ poi: travelOrigin, w: nextPts.length ? 0.35 : 1 });
      for (const np of nextPts) anchors.push({ poi: np, w: 0.6 });
      if (anchors.length) {
        const cands = await findHotels(anchors, budget, party);
        if (cands.length) {
          const best = cands[0];
          const lastLoc = day.locations[day.locations.length - 1];
          const base = lastLoc && toMin(lastLoc.leaveTime) ? toMin(lastLoc.leaveTime) : (startClock ?? START_CLOCK[pace]);
          const travel = await segmentMinutes(travelOrigin, best.poi, city, driveMode ? 'drive' : 'transit');
          const arrival = base + (travel ? travel.minutes : 15);
          const hotelLoc = toLocation({ ...best.poi, typecode: '100100' }, arrival, 600, travel, {});
          hotelLoc.hotelCandidates = cands.map((cd) => ({
            name: cd.poi.name,
            address: cd.poi.address,
            latitude: cd.poi.lat,
            longitude: cd.poi.lng,
            rating: cd.poi.rating || null,
            cost: cd.poi.cost || null,
            reason: cd.reason,
          }));
          day.locations.push(hotelLoc);
          prevHotel = best.poi;
          const partyNote = party.children > 0 ? `${party.adults}大${party.children}小` : `${party.adults}人`;
          const roomNote = party.roomType ? `·${ROOM_TYPE_LABEL[party.roomType]}` : '';
          warnings.push(`第${i + 1}晚住宿：${best.poi.name}（${best.reason}｜${partyNote}·${party.rooms}间${roomNote}，房型库存请预订时确认）${cands.length > 1 ? `，另有${cands.length - 1}个候选可在行程中切换` : ''}`);
        } else {
          warnings.push(`第${i + 1}晚未找到合适酒店，请自行预订`);
        }
      }
    }
  }

  // 跨城段插入第1天头部：家→出发枢纽→班次→到达枢纽→市区
  if (prefix) {
    dayResults[0].locations = [prefix.depHub, prefix.arrHub, ...dayResults[0].locations];
  }

  const totalPlaces = dayResults.reduce((s, d) => s + d.locations.filter((l) => l.type === 'attraction').length, 0);
  return {
    trip: {
      name: `${city.replace(/(市|地区|自治州)$/,'')}${days}日游`,
      startDate,
      endDate: addDays(startDate, days - 1),
      tripMode,
      adults: party.adults,
      children: party.children,
      rooms: party.rooms,
      roomType: party.roomType,
      budget,
      days: dayResults,
    },
    stats: { totalPlaces, days, source, pace, tripMode, hints: hints.notes, fromCity: input.fromCity || null },
    warnings,
  };
}

export function registerPlannerRoutes(app) {
  app.post('/api/planner/generate', async (req, res, next) => {
    try {
      const result = await generateTrip(req.body || {});
      res.json(result);
    } catch (e) { next(e); }
  });
  app.get('/api/planner/interests', (req, res) => {
    res.json({ interests: Object.entries(INTERESTS).map(([key, v]) => ({ key, label: v.label })) });
  });
}

// ---------- 供多城走廊管线（multiCity.js）复用的内部构件 ----------
export {
  queryPois, normalizePoi, gatherCandidates, geocodeCity, haversineKm,
  clusterByDay, buildDay, findHotels, findNearbyRestaurant, segmentMinutes,
  findRestStop, findRentalHub, toLocation, fmt, toMin, extractHints,
  // cost 口径三件套（SR-02 / SR-04a 收敛）：多城管线复用同一套，避免各抄一份正则
  costOf, parseCost, costText,
  // 营业时间解析（SR-OH1/T02）已在函数定义处 export（openHoursSourceOf / parseOpenTime /
  // emptyOpenHours），供多城管线复用同一套，禁止另写第二套正则。
  INTERESTS, PER_DAY_CAP, START_CLOCK, STAY_FACTOR, VEHICLE_CONF,
};
