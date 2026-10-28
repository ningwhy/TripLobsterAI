// SR-OH1 / T02 离线单测：日期感知营业时间解析（parseOpenTime）
//
// 背景（FX-OH 探针实测）：
//   · 旧 parseOpenTime 读 `biz_ext.opentime`（**恒不存在**），景点能解析出 closeTime 的只有 1/10；
//   · `open_time` 无值时是空数组 `[]`（JS truthy 且 String([])===''），旧链路会 stringify 后继续解析；
//   · 旧正则只取**第一个**匹配 → 多时段原文产生假阳性（"11:00-14:00 16:00-22:00" → close=14:00，
//     用户 19:00 到会被误报"已打烊"）。这是"显示错"，不是"少显示"，必须消灭。
//
// 本测试**完全离线**：金标原文来自 server/test/fixtures/open_hours_cases.json（脱敏，无密钥），
// 不联网、不消耗高德配额。parser 单测与线上覆盖率统计严格分离（设计 §7.1 第 8 条）。
//
// 运行：node test/planner_open_hours.mjs      （或 npm run test:open-hours）
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  parseOpenTime,
  openHoursSourceOf,
  emptyOpenHours,
  normalizePoi,
  toLocation,
} from '../src/planner.js';
import { createHolidayResolver, setDefaultHolidayResolver } from '../src/holiday.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE = path.join(__dirname, 'fixtures', 'open_hours_cases.json');

// 【T03】注入**离线**节假日日历解析器（enableNetwork:false），保证本测试全程零网络。
// 数据来源：server/src/data/holiday-cn/2026.json 内置快照（已核实含 2026 年 33 天法定节假日）。
// 不注入时 planner 走 getDefaultHolidayResolver()（enableNetwork 默认 true），
// 虽然 statusOfSnapshot 本身也不联网，但显式关网可以把「离线」从约定升级为断言。
setDefaultHolidayResolver(createHolidayResolver({ enableNetwork: false }));

let failed = 0;
let passed = 0;

/** 断言并打印；失败计数。 */
function check(name, cond, extra = '') {
  if (cond) {
    passed += 1;
    console.log(`PASS ${name}${extra ? ' | ' + extra : ''}`);
  } else {
    failed += 1;
    console.log(`FAIL ${name}${extra ? ' | ' + extra : ''}`);
  }
}

/** ISO 日期 → 星期序号（1=周一 … 7=周日），UTC 基准。 */
function weekdayOf(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso));
  if (!m) return null;
  const dow = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]))).getUTCDay();
  return dow === 0 ? 7 : dow;
}

/** 五字段全 null 契约（且 segments 必须为空数组）。 */
function assertAllNull(label, r) {
  check(`${label} 五字段全 null（契约）`,
    r.open === null && r.close === null && r.lastEntry === null &&
        r.closedOnThisDate === null && r.openHoursRaw === null,
    JSON.stringify(r));
  check(`${label} segments 为空数组`, Array.isArray(r.segments) && r.segments.length === 0,
    JSON.stringify(r.segments));
}

/** 段列表 → [open, close] 二维数组，便于与 fixture 比对。 */
function segPairs(r) {
  return (r.segments || []).map((s) => [s.open, s.close]);
}

// ---------------------------------------------------------------------------
// 1. 金标 fixture：逐例断言
// ---------------------------------------------------------------------------
const fixture = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
assert.ok(Array.isArray(fixture.cases) && fixture.cases.length > 0, 'fixture 必须含 cases');
assert.ok(fixture.cases.every((c) => typeof c.id === 'string' && c.poi && typeof c.date === 'string'),
  '每个用例必须有 id / poi / date');
// fixture 不得携带任何密钥（脱敏金标）
assert.ok(!/AMAP_KEY|apikey|secret/i.test(fs.readFileSync(FIXTURE, 'utf8')), 'fixture 不得含密钥');
check('fixture 可读且含用例', true, `${fixture.cases.length} 例`);

console.log('\n--- A. 离线金标用例（脱敏原文，零网络）---');
const bySemantic = new Map();
for (const c of fixture.cases) {
  const r = parseOpenTime(c.poi, c.date);

  // 0) 先自证 fixture 的星期没写错（设计共享知识第 20 条：不许只写月日后硬编码星期）
  if (c.expectWeekday != null) {
    const actual = weekdayOf(c.date);
    check(`[${c.id}] fixture 星期正确（${c.date} 为周${c.expectWeekday}）`, actual === c.expectWeekday,
      `实际周${actual}`);
  }

  if (c.expectNull) {
    assertAllNull(`[${c.id}]`, r);
    check(`[${c.id}] reason=${c.expectReason}`, r.reason === c.expectReason, `实际 ${r.reason}`);
    if (c.assertNotClose) {
      check(`[${c.id}] 零假阳性：close 不得为 ${c.assertNotClose}`, r.close !== c.assertNotClose,
        `实际 ${r.close}`);
    }
  } else {
    for (const key of ['open', 'close', 'lastEntry', 'closedOnThisDate']) {
      check(`[${c.id}] ${key}=${JSON.stringify(c.expect[key])}`, r[key] === c.expect[key],
        `实际 ${JSON.stringify(r[key])}`);
    }
    check(`[${c.id}] reason=${c.expectReason}`, r.reason === c.expectReason, `实际 ${r.reason}`);
    if (c.expectRawIncludes) {
      check(`[${c.id}] openHoursRaw 为原文命中切片`, typeof r.openHoursRaw === 'string' &&
          r.openHoursRaw.includes(c.expectRawIncludes), JSON.stringify(r.openHoursRaw));
    }
  }

  // segments 契约：逐例断言（多时段的核心产物）
  if (Array.isArray(c.expectSegments)) {
    const got = segPairs(r);
    check(`[${c.id}] segments=${JSON.stringify(c.expectSegments)}`,
      JSON.stringify(got) === JSON.stringify(c.expectSegments), `实际 ${JSON.stringify(got)}`);
  }
  if (Array.isArray(c.expectSegmentLastEntry)) {
    const got = (r.segments || []).map((s) => s.lastEntry ?? null);
    check(`[${c.id}] 各段 lastEntry=${JSON.stringify(c.expectSegmentLastEntry)}`,
      JSON.stringify(got) === JSON.stringify(c.expectSegmentLastEntry), `实际 ${JSON.stringify(got)}`);
  }
  // 【结构性防假阳性】多时段时 open/close 必须为空：调用方不可能把首段打烊时刻当当日打烊时刻
  if ((r.segments || []).length > 1) {
    check(`[${c.id}] 多时段：open/close 必须为 null（结构性防假阳性）`,
      r.open === null && r.close === null, `open=${r.open} close=${r.close}`);
  }
  if ((r.segments || []).length === 1 && !c.expectNull && r.closedOnThisDate !== true) {
    check(`[${c.id}] 单时段：open/close 与 segments[0] 一致`,
      r.open === r.segments[0].open && r.close === r.segments[0].close,
      `${r.open}/${r.close} vs ${r.segments[0].open}/${r.segments[0].close}`);
  }

  // 语义类统计（汇报用）
  const key = c.semantic || '其他';
  const bucket = bySemantic.get(key) || { ok: 0, nullResult: 0 };
  if (c.expectNull) bucket.nullResult += 1;
  else bucket.ok += 1;
  bySemantic.set(key, bucket);
}

// ---------------------------------------------------------------------------
// 2. 契约与边界（不依赖 fixture）
// ---------------------------------------------------------------------------
console.log('\n--- B. 取数与契约 ---');
check('B1 opentime2 优先于 open_time',
  openHoursSourceOf({ biz_ext: { opentime2: 'A', open_time: 'B' } }) === 'A');
check('B2 opentime2 缺失 → 回退 open_time',
  openHoursSourceOf({ biz_ext: { open_time: 'B' } }) === 'B');
check('B3 空数组 [] 视为无值（拒绝数组 truthy 陷阱）',
  openHoursSourceOf({ biz_ext: { opentime2: [], open_time: [] } }) === null);
check('B4 空串视为无值', openHoursSourceOf({ biz_ext: { opentime2: '   ' } }) === null);
check('B5 数字/对象视为无值', openHoursSourceOf({ biz_ext: { opentime2: 123 } }) === null &&
  openHoursSourceOf({ biz_ext: { opentime2: { a: 1 } } }) === null);
check('B6 undefined / null POI 不抛异常',
  openHoursSourceOf(undefined) === null && openHoursSourceOf(null) === null);
check('B7 已归一 POI 走 _openHoursSource',
  openHoursSourceOf({ _openHoursSource: 'X' }) === 'X');

const bad = parseOpenTime({ biz_ext: { opentime2: '09:00-17:00' } }, 'not-a-date');
assertAllNull('B8 非法日期', bad);
check('B8 reason=invalid_date', bad.reason === 'invalid_date');
assertAllNull('B9 日期缺省（null）', parseOpenTime({ biz_ext: { opentime2: '09:00-17:00' } }, null));

console.log('\n--- C. 多时段：解析出多段 + 零假阳性（最高优先级红线）---');
// 旧正则只取第一个匹配 → close=14:00 → 用户 19:00 到会被误报"已打烊"。
// 现在必须：① 解析出全部段；② open/close 为空；③ "落在任一段内"判定 19:00 为营业中。
const MULTI = [
  { src: '11:00-14:00 16:00-22:00', want: [['11:00', '14:00'], ['16:00', '22:00']], probeMin: 19 * 60, probeShouldBeOpen: true },
  { src: '11:00-14:30，17:00-21:00', want: [['11:00', '14:30'], ['17:00', '21:00']], probeMin: 19 * 60, probeShouldBeOpen: true },
  { src: '9:00-13:00 15:00-20:30', want: [['09:00', '13:00'], ['15:00', '20:30']], probeMin: 19 * 60, probeShouldBeOpen: true },
  { src: '11:00-14:00 16:00-22:00', want: [['11:00', '14:00'], ['16:00', '22:00']], probeMin: 15 * 60, probeShouldBeOpen: false },
];
/** 到达时刻是否落在任一时段内（服务端/客户端共用的判据）。 */
function withinAnySegment(r, atMin) {
  const toMin = (hhmm) => {
    if (!hhmm) return null;
    const [h, m] = String(hhmm).split(':').map(Number);
    if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
    return h * 60 + m;
  };
  return (r.segments || []).some((s) => {
    const o = toMin(s.open);
    const c = toMin(s.close);
    return o !== null && c !== null && atMin >= o && atMin <= c;
  });
}
for (const m of MULTI) {
  const r = parseOpenTime({ biz_ext: { opentime2: m.src } }, '2026-10-13');
  const got = segPairs(r);
  check(`C 「${m.src}」解析出 ${m.want.length} 段`, JSON.stringify(got) === JSON.stringify(m.want), JSON.stringify(got));
  check(`C 「${m.src}」open/close 为空（结构性防假阳性）`, r.open === null && r.close === null,
    `open=${r.open} close=${r.close}`);
  const open = withinAnySegment(r, m.probeMin);
  check(`C 「${m.src}」${String(Math.floor(m.probeMin / 60)).padStart(2, '0')}:00 ${m.probeShouldBeOpen ? '应判定营业中' : '应判定非营业时段'}`,
    open === m.probeShouldBeOpen, `实际 ${open ? '营业中' : '非营业'}`);
}

console.log('\n--- D. payload 契约：内部字段与诊断字段不得外泄 ---');
const normPoi = normalizePoi({
  id: 'P1', name: '故宫博物院', location: '116.397,39.918', cityname: '北京', adname: '东城区',
  typecode: '110101', biz_ext: {
    rating: '4.7',
    opentime2: '旺季4月1日至10月31日 周二至周日 08:30-17:00 16:00停止检票，淡季11月1日至3月31日 周二至周日 08:30-16:30 15:30停止检票，周一全天关闭，节假日营业时间以官方通知为准',
  },
});
check('D1 normalizePoi 暂存 _openHoursSource（延迟解析）',
  typeof normPoi._openHoursSource === 'string' && normPoi._openHoursSource.includes('旺季'));
check('D2 normalizePoi 不再产出 openTime/closeTime（延迟到 buildDay）',
  !('openTime' in normPoi) && !('closeTime' in normPoi));

const oh = parseOpenTime(normPoi, '2026-10-13');
const loc = toLocation(normPoi, 540, 90, null, { openHours: oh });
check('D3 toLocation 下发 openTime/closeTime/lastEntryTime',
  loc.openTime === '08:30' && loc.closeTime === '17:00' && loc.lastEntryTime === '16:00',
  `${loc.openTime}/${loc.closeTime}/${loc.lastEntryTime}`);
check('D4 toLocation 下发 closedOnThisDate（false，非 null）', loc.closedOnThisDate === false);
check('D5 toLocation 下发 openHoursRaw', typeof loc.openHoursRaw === 'string' && loc.openHoursRaw.includes('08:30-17:00'));
check('D6 内部 _openHoursSource 不进 payload', !('_openHoursSource' in loc));
check('D7 诊断 reason 不进 payload', !('reason' in loc));
check('D8 既有字段未被动', loc.arrivalTime === '09:00' && loc.leaveTime === '10:30' && loc.type === 'attraction',
  `${loc.arrivalTime}/${loc.leaveTime}/${loc.type}`);

const locClosed = toLocation(normPoi, 540, 90, null, { openHours: parseOpenTime(normPoi, '2026-10-12') });
check('D9 闭馆日 payload：三个时刻 null + closedOnThisDate=true',
  locClosed.openTime === null && locClosed.closeTime === null && locClosed.lastEntryTime === null &&
      locClosed.closedOnThisDate === true && typeof locClosed.openHoursRaw === 'string',
  JSON.stringify({ o: locClosed.openTime, c: locClosed.closeTime, cd: locClosed.closedOnThisDate }));

const locUnknown = toLocation(normalizePoi({ id: 'P2', name: 'X', location: '116.4,39.9', biz_ext: {} }), 540, 90, null, {});
check('D10 无原文 → payload 五字段全 null（不兜底填充）',
  locUnknown.openTime === null && locUnknown.closeTime === null && locUnknown.lastEntryTime === null &&
      locUnknown.closedOnThisDate === null && locUnknown.openHoursRaw === null,
  JSON.stringify(locUnknown));
check('D11 无原文 → openSegments 为空数组', Array.isArray(locUnknown.openSegments) && locUnknown.openSegments.length === 0);

const multiPoi = normalizePoi({ id: 'P3', name: '某餐厅', location: '116.4,39.9', typecode: '050100',
  biz_ext: { opentime2: '11:00-14:00 16:00-22:00' } });
const locMulti = toLocation(multiPoi, 720, 60, null, { openHours: parseOpenTime(multiPoi, '2026-10-13') });
check('D12 多时段 payload：openTime/closeTime 为 null', locMulti.openTime === null && locMulti.closeTime === null,
  `${locMulti.openTime}/${locMulti.closeTime}`);
check('D13 多时段 payload：openSegments 承载两段',
  JSON.stringify(locMulti.openSegments) === JSON.stringify([
    { open: '11:00', close: '14:00', lastEntry: null },
    { open: '16:00', close: '22:00', lastEntry: null },
  ]), JSON.stringify(locMulti.openSegments));
check('D14 多时段 payload：closedOnThisDate=false（不是未知）', locMulti.closedOnThisDate === false);

console.log('\n--- E. 空对象工厂与三态 ---');
const e = emptyOpenHours('unit_test');
assertAllNull('E1 emptyOpenHours', e);
check('E2 emptyOpenHours 带 reason', e.reason === 'unit_test');
check('E3 closedOnThisDate 三态：true/false/null 都出现过',
  [true, false, null].every((v) => [locClosed.closedOnThisDate, loc.closedOnThisDate, locUnknown.closedOnThisDate].includes(v)));

console.log('\n--- F. 纯函数性（相同输入 → 相同输出，不受时区影响）---');
const srcPoi = { biz_ext: { opentime2: '周二至周日 09:00-17:00 最晚进入15:00，周一闭馆' } };
const r1 = JSON.stringify(parseOpenTime(srcPoi, '2026-10-14'));
const r2 = JSON.stringify(parseOpenTime(srcPoi, '2026-10-14'));
check('F1 相同输入两次调用结果一致', r1 === r2);
const savedTz = process.env.TZ;
for (const tz of ['UTC', 'Asia/Shanghai', 'America/New_York']) {
  process.env.TZ = tz;
  const r3 = JSON.stringify(parseOpenTime(srcPoi, '2026-10-14'));
  check(`F2 时区 ${tz} 下结果一致（星期按 UTC 计算）`, r3 === r1, r3);
}
process.env.TZ = savedTz;

// ---------------------------------------------------------------------------
// G. T05 回归防护：四轮历史假阳性红线（2026-10-14 QA 补锁）
//
// 本项目历史上出过三轮"显示错"。本节把每轮的触发原文固化为断言，
// 防止修复被后续改动 silently 回退。
// ---------------------------------------------------------------------------
console.log('\n--- G. 历史假阳性回归防护（T05 补锁）---');

// G1 风险①：多时段原文 —— 旧正则只取首段，"11:00-14:00 16:00-22:00" 曾让 19:00 到达
// 被误报"已打烊"（餐厅 19:00 到 = 阻塞级错误）。C 节已覆盖解析，这里补 payload 契约：
// 多时段时 openTime/closeTime 必须为 null（调用方不可能把首段打烊时刻当当日打烊时刻）。
const g1Poi = normalizePoi({ id: 'G1', name: '原乡私厨饺子', location: '116.4,39.9', typecode: '050100',
  biz_ext: { opentime2: '11:00-14:00 16:00-22:00' } });
const g1 = parseOpenTime(g1Poi, '2026-10-13');
check('G1 多时段：open=null, close=null（旧逻辑会给出 close=14:00）',
  g1.open === null && g1.close === null, `open=${g1.open} close=${g1.close}`);
check('G1 多时段：segments.length>=2', Array.isArray(g1.segments) && g1.segments.length >= 2,
  JSON.stringify(segPairs(g1)));
check('G1 多时段：19:00 到达判定营业中（防"已打烊"假阳性）',
  withinAnySegment(g1, 19 * 60) === true);
const g1Loc = toLocation(g1Poi, 720, 60, null, { openHours: g1 });
check('G1 多时段 payload：openTime/closeTime 为 null（D12 复述，锁定契约）',
  g1Loc.openTime === null && g1Loc.closeTime === null && g1Loc.openSegments.length === 2,
  JSON.stringify({ o: g1Loc.openTime, c: g1Loc.closeTime, n: g1Loc.openSegments.length }));

// G2 风险④：苏州博物馆尾部条款"……可根据需要临时闭馆，届时将告示公众"含"闭馆"
// 但无星期、无日期 —— 旧逻辑判"每天都闭馆"（阻塞级假阳性）。
// 修复（planner.js isScheduled）：纯关闭句必须带星期或日期区间才算排期闭馆。
//
// 【T03 改动】原文由简化文本还原为**高德真实原文**（opentime2 逐字照抄），
// 因为简化文本丢掉了「春节,劳动节,端午节 09:00–17:00开放」这条具名排班 clause，
// 使 G2 无法覆盖 T02 最重要的新能力（节假日命中具名排班）。
const SUZHOU_REAL = '09/25-09/27 10:00–20:00开放 最晚进入19:00；09/30-10/06 10:00–20:00开放 最晚进入19:00；' +
  '01/01-09/24 周二–周日 09:00–17:00开放 最晚进入16:00；09/28-09/29 周二–周日 09:00–17:00开放 最晚进入16:00；' +
  '10/07-12/31 周二–周日 09:00–17:00开放 最晚进入16:00；01/01-09/24 周一 全天不开放；09/28-09/29 周一 全天不开放；' +
  '10/07-12/31 周一 全天不开放；春节,劳动节,端午节 09:00–17:00开放；夜间开放时间另行公布。' +
  '如本馆遇有重大活动或重要设备设施维修保养时，可根据需要临时闭馆，届时将告示公众。';
for (const d of ['2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17']) {
  const r = parseOpenTime({ biz_ext: { opentime2: SUZHOU_REAL } }, d);
  check(`G2 苏州博物馆 ${d}：closedOnThisDate 不得为 true（条件式临时闭馆≠排期闭馆）`,
    r.closedOnThisDate !== true, `closed=${r.closedOnThisDate} reason=${r.reason}`);
  // 用真实原文时这些日期（周二至周六）应落在「10/07-12/31 周二–周日」段上，解析出 09:00-17:00
  check(`G2 苏州博物馆 ${d}：真实原文仍解析出 09:00-17:00（lastEntry 16:00）`,
    r.open === '09:00' && r.close === '17:00' && r.lastEntry === '16:00',
    `${r.open}-${r.close} le=${r.lastEntry}`);
}
const g2Wed = parseOpenTime({ biz_ext: { opentime2: SUZHOU_REAL } }, '2026-10-14');
check('G2 苏州博物馆周三仍正常解析出营业段（不该因尾部条款整体放弃）',
  g2Wed.open === '09:00' && g2Wed.close === '17:00' && g2Wed.closedOnThisDate === false,
  `${g2Wed.open}-${g2Wed.close} closed=${g2Wed.closedOnThisDate}`);

// G2-① 非节假日周一（2026-10-12 已核实：周一，且国庆 10/01-10/07 已结束 → 非节假日）
// P0-1 误伤修复：旧逻辑遇「节假日除外 / 具名节假日」就整体放弃返 null。
// 新逻辑先查权威日历 → 非节假日 → 丢弃全部节假日限定条款、按纯文本解析：
// 「10/07-12/31 周一 全天不开放」是**带日期区间 + 星期**的排期闭馆 → closed=true。
// 这是确定结论，不是猜测：原文有明确闭馆证据。
const g2Mon = parseOpenTime({ biz_ext: { opentime2: SUZHOU_REAL } }, '2026-10-12');
check('G2① 苏州博物馆非节假日周一（2026-10-12）：closedOnThisDate=true（不再是 null）',
  g2Mon.closedOnThisDate === true, `closed=${g2Mon.closedOnThisDate} reason=${g2Mon.reason}`);
check('G2① 苏州博物馆非节假日周一：reason=closed',
  g2Mon.reason === 'closed', `实际 ${g2Mon.reason}`);
check('G2① 苏州博物馆非节假日周一：三个时刻为 null 且 segments 为空',
  g2Mon.open === null && g2Mon.close === null && g2Mon.lastEntry === null &&
      g2Mon.segments.length === 0, JSON.stringify(g2Mon));

// G2-② 节假日周一（2026-05-04 已核实：劳动节假期且为周一）
// 常规段「周二–周日」不含周一 → 若无节假日 clause 就只能返 no_matching_clause；
// 靠具名 clause「春节,劳动节,端午节 09:00–17:00开放」命中 → 给出确定时段。
const g2HolMon = parseOpenTime({ biz_ext: { opentime2: SUZHOU_REAL } }, '2026-05-04');
check('G2② 苏州博物馆节假日周一（2026-05-04 劳动节）：open=09:00 close=17:00 lastEntry=16:00',
  g2HolMon.open === '09:00' && g2HolMon.close === '17:00' && g2HolMon.lastEntry === '16:00',
  `${g2HolMon.open}-${g2HolMon.close} le=${g2HolMon.lastEntry}`);
check('G2② 苏州博物馆节假日周一：closedOnThisDate=false 且 reason=ok',
  g2HolMon.closedOnThisDate === false && g2HolMon.reason === 'ok',
  `closed=${g2HolMon.closedOnThisDate} reason=${g2HolMon.reason}`);
check('G2② 苏州博物馆节假日周一：holidayName=劳动节 / holidayStatus=holiday',
  g2HolMon.holidayName === '劳动节' && g2HolMon.holidayStatus === 'holiday',
  `${g2HolMon.holidayName} / ${g2HolMon.holidayStatus}`);

// G3 风险③/CH-03 链路：故宫季节 + 星期双条件选段。周一 → 闭馆；旺季周三 → 08:30-17:00 且 lastEntry=16:00。
const GUGONG = '旺季4月1日至10月31日 周二至周日 08:30-17:00 16:00停止检票，' +
  '淡季11月1日至3月31日 周二至周日 08:30-16:30 15:30停止检票，周一全天关闭';
const g3Mon = parseOpenTime({ biz_ext: { opentime2: GUGONG } }, '2026-10-12'); // 周一
check('G3 故宫周一（2026-10-12）：closedOnThisDate=true',
  g3Mon.closedOnThisDate === true && g3Mon.segments.length === 0, JSON.stringify(segPairs(g3Mon)));
const g3Wed = parseOpenTime({ biz_ext: { opentime2: GUGONG } }, '2026-10-14'); // 周三·旺季
check('G3 故宫旺季周三：open=08:30 close=17:00 lastEntry=16:00',
  g3Wed.open === '08:30' && g3Wed.close === '17:00' && g3Wed.lastEntry === '16:00',
  `${g3Wed.open}-${g3Wed.close} le=${g3Wed.lastEntry}`);
const g3Winter = parseOpenTime({ biz_ext: { opentime2: GUGONG } }, '2026-11-11'); // 周三·淡季
check('G3 故宫淡季周三：open=08:30 close=16:30 lastEntry=15:30（季节选段生效）',
  g3Winter.open === '08:30' && g3Winter.close === '16:30' && g3Winter.lastEntry === '15:30',
  `${g3Winter.open}-${g3Winter.close} le=${g3Winter.lastEntry}`);

// G4 "24小时营业" → 确定性语义：00:00-24:00 单段，闭馆三态 false（不是未知）。
const g4 = parseOpenTime({ biz_ext: { opentime2: '24小时营业' } }, '2026-10-13');
check('G4 24小时营业：open=00:00 close=24:00 closedOnThisDate=false',
  g4.open === '00:00' && g4.close === '24:00' && g4.closedOnThisDate === false,
  `${g4.open}-${g4.close} closed=${g4.closedOnThisDate}`);

// ---------------------------------------------------------------------------
// H. 节假日当天离线金标（T03 新增）
//
// 为什么单独一节：A 节 fixture 覆盖的是**常规日**（含非节假日周一），
// 而 T02 最有价值的新能力恰恰发生在**节假日当天**——那天常规星期段（"周二至周日"）
// 通通不适用，只有靠节假日 clause 才能给出结论。这两条路径必须分开锁。
//
// 离线保证：本节全部日期的节假日属性由内置快照 server/src/data/holiday-cn/2026.json
// 裁决（文件顶部已注入 enableNetwork:false 的解析器），全程零网络、零配额。
//
// 【诚实口径 —— 宁可少显示，不可显示错】
// H1–H5 这类「周一闭馆(法定节假日除外)」的馆，在节假日当天该闭馆条款**失效**了，
// 但原文**没有**"节假日正常开放/节假日 09:00-17:00"的明示 → 没有任何依据给出时段。
// 因此正确结果是**"开放但无时段"**（closedOnThisDate=false, segments=[]），
// **绝不是**"闭馆"——把失效的闭馆条款继续当闭馆，会让用户在节假日当天看到
// "今日闭馆"而白跑一趟，那是阻塞级假阳性。宁可少显示一个时段，不可显示错。
// ---------------------------------------------------------------------------
console.log('\n--- H. 节假日当天离线金标（T03 新增）---');

// H1 上海科技馆（高德 opentime2 真实原文）
const H1_SRC = '周一 全天关闭；周二至周五,周日 09:00-17:00 最晚进入16:00；周六 09:00-20:00 最晚进入19:00；' +
  '周一闭馆，节假日除外,具体营业状态以当天开放情况为准';
// H2 中国国家博物馆
const H2_SRC = '周一全天关闭(法定节假日除外)；11月1日至次年5月31日周二至周日09:00-17:00(16:00停止入馆)；' +
  '6月1日至10月31日周二至周日09:00-17:30(16:30停止入馆)';
// H3 南京博物院
const H3_SRC = '周一 闭馆(法定节假日除外)；周二至周日 09:00-17:00开放(16:00停止入园)';
// H4 广东省博物馆
const H4_SRC = '7月-8月 周二-周日 09:00-21:00开放 最晚进入20:00； 1月-6月, 9月-12月 周二-周日 09:00-17:00开放 ' +
  '最晚进入16:00； 周一 全天不开放(法定节假日除外)';
// H5 陕西历史博物馆（2026-02-16 落在冬季区间 11/15–3/14）
const H5_SRC = '4月1日至11月14日 08:30-19:00 (18:00停止检票),11月15日至3月14日周一 全天关闭(法定节假日除外), ' +
  '周二至周日09:00-17:30 (16:30停止检票)';
// H7 良渚博物院
const H7_SRC = '全年 周二–周日 09:00–17:00开放 最晚进入16:30；全年 周一 全天不开放；' +
  '清明节,劳动节,端午节,中秋节,国庆节 09:00–17:00开放 最晚进入16:30';
// H8 中山陵
const H8_SRC = '08:30-17:00(周一闭馆)；法定节假日及孙中山先生诞辰、逝世纪念日正常开放,墓室仅周二至周五开放' +
  '(数据来源:江苏省文旅厅公共服务平台苏心游)';
// H9 秦始皇帝陵博物院（多时段：劳动节专属段 + 常规季节段同时命中）
const H9_SRC = '09/25-09/30 08:00–19:30开放 最晚售票17:30；10/01-10/07 07:30–20:00开放 最晚售票18:00；' +
  '03/16-09/24 08:30–19:00开放 最晚售票17:00 最晚进入17:00；10/08-11/15 08:30–19:00开放 最晚售票17:00 最晚进入17:00；' +
  '11/16-12/31 08:30–18:00开放 最晚进入16:30；01/01-03/15 08:30–18:00开放 最晚进入16:30；' +
  '劳动节 07:30–20:00开放 最晚售票18:00 最晚进入18:00';

// 日期自证（与 fixture 同口径：不许只写日期而硬编码星期 —— 设计共享知识第 20 条）
// 已核实的 2026 年周一·法定节假日：02-16 / 02-23 / 04-06 / 05-04 / 10-05。
for (const [iso, wd] of [['2026-05-04', 1], ['2026-10-05', 1], ['2026-02-16', 1], ['2026-10-12', 1]]) {
  check(`H 日期自证：${iso} 为周${wd}`, weekdayOf(iso) === wd, `实际周${weekdayOf(iso)}`);
}

/**
 * 断言「开放但无时段」型（reason=holiday_excluded_open）：
 * 除外型闭馆条款在节假日失效 → 不许显示成闭馆；但也无依据给时段 → 三个时刻为 null。
 * @param {string} id 用例号
 * @param {string} src POI 真实原文
 * @param {string} date 日期
 * @param {string} wantName 期望节日名
 * @returns {void}
 */
function assertExcludedOpen(id, src, date, wantName) {
  const r = parseOpenTime({ biz_ext: { opentime2: src } }, date);
  check(`${id} reason=holiday_excluded_open`, r.reason === 'holiday_excluded_open', `实际 ${r.reason}`);
  check(`${id} closedOnThisDate=false（失效的闭馆条款不得再显示成闭馆）`,
    r.closedOnThisDate === false, `实际 ${r.closedOnThisDate}`);
  check(`${id} open/close/lastEntry 全 null（无依据给时段，绝不编造）`,
    r.open === null && r.close === null && r.lastEntry === null,
    `${r.open}/${r.close}/${r.lastEntry}`);
  check(`${id} segments 为空数组`, Array.isArray(r.segments) && r.segments.length === 0,
    JSON.stringify(segPairs(r)));
  check(`${id} holidayName=${wantName}`, r.holidayName === wantName, `实际 ${r.holidayName}`);
  check(`${id} holidayStatus=holiday_excluded_close`,
    r.holidayStatus === 'holiday_excluded_close', `实际 ${r.holidayStatus}`);
}

/**
 * 断言「节假日命中具名/泛指排班 → 给出确定单时段」型（reason=ok）。
 * @param {string} id 用例号
 * @param {string} src POI 真实原文
 * @param {string} date 日期
 * @param {{open: string, close: string, lastEntry: string|null, name: string}} want 期望
 * @returns {void}
 */
function assertOkSegment(id, src, date, want) {
  const r = parseOpenTime({ biz_ext: { opentime2: src } }, date);
  check(`${id} open=${want.open} close=${want.close} lastEntry=${JSON.stringify(want.lastEntry)}`,
    r.open === want.open && r.close === want.close && r.lastEntry === want.lastEntry,
    `${r.open}-${r.close} le=${r.lastEntry}`);
  check(`${id} closedOnThisDate=false 且 reason=ok`,
    r.closedOnThisDate === false && r.reason === 'ok',
    `closed=${r.closedOnThisDate} reason=${r.reason}`);
  check(`${id} segments 单段一致`,
    JSON.stringify(segPairs(r)) === JSON.stringify([[want.open, want.close]]), JSON.stringify(segPairs(r)));
  check(`${id} holidayName=${want.name} / holidayStatus=holiday`,
    r.holidayName === want.name && r.holidayStatus === 'holiday',
    `${r.holidayName} / ${r.holidayStatus}`);
}

// H1–H5：除外型闭馆在节假日失效 → 开放但无时段（绝不谎报闭馆）
assertExcludedOpen('H1 上科技馆（2026-05-04 劳动节·周一）', H1_SRC, '2026-05-04', '劳动节');
assertExcludedOpen('H2 国博（2026-05-04 劳动节·周一）', H2_SRC, '2026-05-04', '劳动节');
assertExcludedOpen('H3 南博（2026-05-04 劳动节·周一）', H3_SRC, '2026-05-04', '劳动节');
assertExcludedOpen('H4 粤博（2026-05-04 劳动节·周一）', H4_SRC, '2026-05-04', '劳动节');
assertExcludedOpen('H5 陕历博（2026-02-16 春节·周一，冬季区间）', H5_SRC, '2026-02-16', '春节');

// H6 苏博：具名 clause「春节,劳动节,端午节 09:00–17:00开放」命中劳动节
assertOkSegment('H6 苏博（2026-05-04 劳动节·周一）', SUZHOU_REAL, '2026-05-04',
  { open: '09:00', close: '17:00', lastEntry: '16:00', name: '劳动节' });
// H7 良渚：具名 clause 命中国庆节（周一常规闭馆，靠节假日 clause 救回）
assertOkSegment('H7 良渚（2026-10-05 国庆·周一）', H7_SRC, '2026-10-05',
  { open: '09:00', close: '17:00', lastEntry: '16:30', name: '国庆节' });
// H8 中山陵：泛指 clause「法定节假日…正常开放」放宽周一闭馆限制
assertOkSegment('H8 中山陵（2026-05-04 劳动节·周一）', H8_SRC, '2026-05-04',
  { open: '08:30', close: '17:00', lastEntry: null, name: '劳动节' });

// H9 秦陵：劳动节专属段 + 常规季节段**同时命中** → 诚实输出多时段（不"择优"只留一段）
const h9 = parseOpenTime({ biz_ext: { opentime2: H9_SRC } }, '2026-05-04');
check('H9 秦陵（2026-05-04 劳动节·周一）reason=ok_multi_segment',
  h9.reason === 'ok_multi_segment', `实际 ${h9.reason}`);
check('H9 秦陵：open/close 为 null（多时段结构性防假阳性）',
  h9.open === null && h9.close === null, `open=${h9.open} close=${h9.close}`);
check('H9 秦陵：segments=[07:30-20:00, 08:30-19:00]（劳动节段 + 常规段，不择优）',
  JSON.stringify(segPairs(h9)) === JSON.stringify([['07:30', '20:00'], ['08:30', '19:00']]),
  JSON.stringify(segPairs(h9)));
check('H9 秦陵：closedOnThisDate=false', h9.closedOnThisDate === false, `实际 ${h9.closedOnThisDate}`);
check('H9 秦陵：holidayName=劳动节 / holidayStatus=holiday',
  h9.holidayName === '劳动节' && h9.holidayStatus === 'holiday',
  `${h9.holidayName} / ${h9.holidayStatus}`);

// 对照组：P0-1 修复的**反面**没被破坏 —— H1–H3 在非节假日周一（2026-10-12）
// 仍必须给出确定闭馆（closed=true, reason=closed, holidayStatus=none）。
// 若这组挂了，说明修复方向搞反了：把闭馆证据也一并丢弃了。
for (const [id, src] of [['H1 上科技馆', H1_SRC], ['H2 国博', H2_SRC], ['H3 南博', H3_SRC]]) {
  const r = parseOpenTime({ biz_ext: { opentime2: src } }, '2026-10-12');
  check(`对照组 ${id} 非节假日周一（2026-10-12）：closedOnThisDate=true`,
    r.closedOnThisDate === true, `实际 ${r.closedOnThisDate}`);
  check(`对照组 ${id} 非节假日周一：reason=closed / holidayStatus=none`,
    r.reason === 'closed' && r.holidayStatus === 'none',
    `reason=${r.reason} status=${r.holidayStatus}`);
}

// ---------------------------------------------------------------------------
// K. 非节假日不得泄漏节假日专属时段（T03 回归锁）
//
// 【这个坑的来历】T02 的 P0-1 修复（"遇节假日条款不再整体放弃"）把 clauseMode 的
// !isHoliday 分支统一返回 'plain'，导致**带营业段的节假日 clause 在平日也被当常规段**：
// 秦始皇帝陵博物院在非节假日 2026-10-13 输出 segments=[07:30-20:00(劳动节专属), 08:30-19:00]，
// 用户会在普通10月周二被告诉"07:30 开门"，早到 60 分钟吃闭门羹 —— 这是"显示错"，
// 方向与 P0-1 正好相反。修复（264e083）把该分支按语义三分，只抑制 holiday_open 型。
//
// 【本节为什么成对锁】只锁"平日不泄漏"是不够的：后人看到 K1 很可能"一劳永逸"地把
// holiday_open 全抑制 → 节假日当天就没时段了（K2 防的就是这个）；
// 或者把抑制条件放宽到"带节假日字样就抑制" → 把"时段由星期管辖、节假日字样只是顺带
// 延长"的常规条款一起抑制掉，造成大面积 under-show（K3 防的就是这个）。
// K1/K2/K3 三条一起才锁住那个精确的例外条件（holiday_open && 有营业段 && 无星期限定）。
//
// 【K4/K5 锁的是抑制的代价】抑制节假日条款后，原本靠它支撑的时段会消失。
// 代价必须落在"少显示"一侧：真实良渚含「周一全天不开放」→ 平日周一仍是 closed=true（K5）；
// 而简写版良渚没有闭馆句 → 平日周一只能退回"未知"（K4），这才是"宁可少显示不可显示错"。
// ---------------------------------------------------------------------------
console.log('\n--- K. 非节假日不得泄漏节假日专属时段（T03 回归锁）---');

// 简写版良渚（与 fixture 用例 holiday-named-unknown 同源，但**不含**「周一全天不开放」）
const K4_SRC = '全年 周二–周日 09:00–17:00开放 最晚进入16:30；' +
  '清明节,劳动节,端午节 09:00–17:00开放 最晚进入16:30';
// 泛指 + 自带星期限定：时段由「周二至周日」管辖，"法定节假日"字样只是顺带延长
const K3_SRC = '周二至周日 09:00-17:00 法定节假日正常开放';

// 日期自证（项目惯例：不许只写日期而硬编码星期）
for (const [iso, wd] of [['2026-10-13', 2], ['2026-05-12', 2], ['2026-03-20', 5],
  ['2026-05-04', 1], ['2026-10-14', 3], ['2026-01-05', 1], ['2026-01-06', 2]]) {
  check(`K 日期自证：${iso} 为周${wd}`, weekdayOf(iso) === wd, `实际周${weekdayOf(iso)}`);
}

// K1 核心锁：秦陵在非节假日只给常规季节段，**劳动节专属段 07:30-20:00 绝不出现在平日**
for (const d of ['2026-10-13', '2026-05-12', '2026-03-20']) {
  const r = parseOpenTime({ biz_ext: { opentime2: H9_SRC } }, d);
  check(`K1 秦陵非节假日 ${d}：open=08:30 close=19:00 lastEntry=17:00`,
    r.open === '08:30' && r.close === '19:00' && r.lastEntry === '17:00',
    `${r.open}-${r.close} le=${r.lastEntry}`);
  check(`K1 秦陵非节假日 ${d}：closedOnThisDate=false reason=ok holidayStatus=none`,
    r.closedOnThisDate === false && r.reason === 'ok' && r.holidayStatus === 'none',
    `closed=${r.closedOnThisDate} reason=${r.reason} hs=${r.holidayStatus}`);
  check(`K1 秦陵非节假日 ${d}：segments 只有常规季节段 [08:30-19:00]`,
    JSON.stringify(segPairs(r)) === JSON.stringify([['08:30', '19:00']]), JSON.stringify(segPairs(r)));
  // ↓ 本次 P0 的直接锁：**显式点名**被泄漏的那个时段，后人一眼看懂在防什么
  check(`K1 秦陵非节假日 ${d}：segments 中不得出现劳动节专属段 [07:30-20:00]`,
    !segPairs(r).some(([o, c]) => o === '07:30' && c === '20:00'), JSON.stringify(segPairs(r)));
}

// K2 防过度抑制①：节假日当天劳动节段必须还在（只锁 K1 的话，最省事的"修法"就是全抑制）
const k2 = parseOpenTime({ biz_ext: { opentime2: H9_SRC } }, '2026-05-04');
check('K2 秦陵节假日当天（2026-05-04 劳动节）：reason=ok_multi_segment',
  k2.reason === 'ok_multi_segment', `实际 ${k2.reason}`);
check('K2 秦陵节假日当天：open/close 为 null（多时段结构性防假阳性）',
  k2.open === null && k2.close === null, `open=${k2.open} close=${k2.close}`);
check('K2 秦陵节假日当天：segments=[07:30-20:00, 08:30-19:00]（劳动节段未被抑制掉）',
  JSON.stringify(segPairs(k2)) === JSON.stringify([['07:30', '20:00'], ['08:30', '19:00']]),
  JSON.stringify(segPairs(k2)));
check('K2 秦陵节假日当天：closedOnThisDate=false', k2.closedOnThisDate === false,
  `实际 ${k2.closedOnThisDate}`);
check('K2 秦陵节假日当天：holidayName=劳动节 / holidayStatus=holiday',
  k2.holidayName === '劳动节' && k2.holidayStatus === 'holiday',
  `${k2.holidayName} / ${k2.holidayStatus}`);

// K3 防过度抑制②：自带星期限定的常规条款（"周二至周日 09:00-17:00 法定节假日正常开放"）
// 时段由星期管辖、节假日字样只是顺带延长 → 平日必须保留 09:00-17:00。
// 这是 clauseMode 里「weekdays === null 才抑制」的例外分支；删掉这个例外会大面积 under-show。
for (const d of ['2026-10-13', '2026-10-14']) {
  const r = parseOpenTime({ biz_ext: { opentime2: K3_SRC } }, d);
  check(`K3 泛指+星期限定 ${d}：open=09:00 close=17:00`,
    r.open === '09:00' && r.close === '17:00', `${r.open}-${r.close}`);
  check(`K3 泛指+星期限定 ${d}：reason=ok holidayStatus=none`,
    r.reason === 'ok' && r.holidayStatus === 'none', `reason=${r.reason} hs=${r.holidayStatus}`);
  check(`K3 泛指+星期限定 ${d}：segments=[09:00-17:00]（平日时段未被抑制）`,
    JSON.stringify(segPairs(r)) === JSON.stringify([['09:00', '17:00']]), JSON.stringify(segPairs(r)));
}

// K4 抑制的代价落在"少显示"一侧：简写版良渚无闭馆句，非节假日周一唯一能支撑
// "09:00 开门"的证据就是那条节假日专属条款 → 抑制后只能退回"未知"（no_matching_clause），
// 这才是"宁可少显示不可显示错"。同文周二有常规星期段 → 正常给出 09:00-17:00。
const k4Mon = parseOpenTime({ biz_ext: { opentime2: K4_SRC } }, '2026-01-05');
assertAllNull('K4 简写良渚非节假日周一（2026-01-05）', k4Mon);
check('K4 简写良渚非节假日周一：reason=no_matching_clause',
  k4Mon.reason === 'no_matching_clause', `实际 ${k4Mon.reason}`);
const k4Tue = parseOpenTime({ biz_ext: { opentime2: K4_SRC } }, '2026-01-06');
check('K4 简写良渚非节假日周二（2026-01-06）：open=09:00 close=17:00 lastEntry=16:30',
  k4Tue.open === '09:00' && k4Tue.close === '17:00' && k4Tue.lastEntry === '16:30',
  `${k4Tue.open}-${k4Tue.close} le=${k4Tue.lastEntry}`);
check('K4 简写良渚非节假日周二：reason=ok', k4Tue.reason === 'ok', `实际 ${k4Tue.reason}`);
check('K4 简写良渚非节假日周二：segments=[09:00-17:00]',
  JSON.stringify(segPairs(k4Tue)) === JSON.stringify([['09:00', '17:00']]),
  JSON.stringify(segPairs(k4Tue)));

// K5 证明 P0-1 的收益没被这次修复回退：真实良渚含「周一全天不开放」，
// 非节假日周一仍给出确定闭馆（closed=true），而不是退回 null。
const k5Mon = parseOpenTime({ biz_ext: { opentime2: H7_SRC } }, '2026-01-05');
check('K5 真实良渚非节假日周一（2026-01-05）：closedOnThisDate=true',
  k5Mon.closedOnThisDate === true, `实际 ${k5Mon.closedOnThisDate}`);
check('K5 真实良渚非节假日周一：reason=closed', k5Mon.reason === 'closed', `实际 ${k5Mon.reason}`);
check('K5 真实良渚非节假日周一：segments 为空数组',
  Array.isArray(k5Mon.segments) && k5Mon.segments.length === 0, JSON.stringify(segPairs(k5Mon)));

// ---------------------------------------------------------------------------
// 汇总
// ---------------------------------------------------------------------------
console.log('\n--- 语义类覆盖汇总（成功解析 / 保守放弃返 null）---');
for (const [sem, v] of [...bySemantic.entries()].sort()) {
  console.log(`  ${sem.padEnd(28)} 成功 ${v.ok} ／ 放弃 ${v.nullResult}`);
}

console.log('');
if (failed === 0) {
  console.log(`ALL TESTS PASSED（${passed} 项断言，${fixture.cases.length} 个金标用例，全程离线）`);
} else {
  console.log(`${failed} CHECK(S) FAILED（通过 ${passed} 项）`);
  process.exit(1);
}
