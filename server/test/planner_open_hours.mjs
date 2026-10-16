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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE = path.join(__dirname, 'fixtures', 'open_hours_cases.json');

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
const SUZHOU = '开放时间:周二至周日9:00-17:00(16:00停止入馆)，周一全天闭馆(法定节假日除外)。' +
  '如本馆遇有重大活动或重要设备设施维修保养时，可根据需要临时闭馆，届时将告示公众。';
for (const d of ['2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-17']) {
  const r = parseOpenTime({ biz_ext: { opentime2: SUZHOU } }, d);
  check(`G2 苏州博物馆 ${d}：closedOnThisDate 不得为 true（条件式临时闭馆≠排期闭馆）`,
    r.closedOnThisDate !== true, `closed=${r.closedOnThisDate} reason=${r.reason}`);
}
const g2Wed = parseOpenTime({ biz_ext: { opentime2: SUZHOU } }, '2026-10-14');
check('G2 苏州博物馆周三仍正常解析出营业段（不该因尾部条款整体放弃）',
  g2Wed.open === '09:00' && g2Wed.close === '17:00' && g2Wed.closedOnThisDate === false,
  `${g2Wed.open}-${g2Wed.close} closed=${g2Wed.closedOnThisDate}`);
const g2Mon = parseOpenTime({ biz_ext: { opentime2: SUZHOU } }, '2026-10-12');
// 注意：该原文的闭馆句自带「(法定节假日除外)」—— 无法在无权威日历时判断 10-12
// 是否为例外假日，正确行为是**整体放弃返 null**（holiday_exception），
// 既不谎报闭馆、也不谎报营业，客户端走 CH-09 诚实披露。排期闭馆路径的存活证明见 G3。
check('G2 苏州博物馆周一：遇「法定节假日除外」限定 → 整体放弃返 null（不猜节假日日历）',
  g2Mon.closedOnThisDate === null && g2Mon.reason === 'holiday_exception',
  `closed=${g2Mon.closedOnThisDate} reason=${g2Mon.reason}`);

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
