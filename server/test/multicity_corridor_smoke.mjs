// 多城走廊管线 · corridor 冒烟测试（不依赖高德真实 Key / 网络）
//
// 覆盖 T01 验收点：
//   ② 传 schedules 的 corridor 不再 500（M1 TDZ 回归哨兵）
//   days[0].date == startDate（FX-01 addDays 时区修复的下游验证）
//   stats.cost 存在（【裁 2】客户端 statsCost 取数点的上游保证）
//   ③ cities 超上限 → 400 且错误信息回显实际数量
//   ⑤ 第 6 次 corridor 请求 → 429（限流已挂到真实路由上）
//
// 运行：node test/multicity_corridor_smoke.mjs
import express from 'express';
import { planCorridor, recalcTrip, registerMultiCityRoutes } from '../src/multiCity.js';
import { addDays } from '../src/planner.js';

// 高德 Key 只做"非空"校验，本测试不发真实网络请求（fetch 已被 stub）
process.env.AMAP_KEY = process.env.AMAP_KEY || 'stub-key-for-test';

let failed = 0;
/** 断言并打印；失败计数。 */
function check(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ' | ' + extra : ''}`);
  if (!cond) failed++;
}

// ---------------------------------------------------------------------------
// 1. stub globalThis.fetch：按高德路径返回最小可用响应
// ---------------------------------------------------------------------------
const realFetch = globalThis.fetch; // 保留真身，第 5 段（限流）要用真 HTTP
const callLog = [];
const CITY_GEO = {
  北京: [116.407, 39.904],
  天津: [117.201, 39.085],
  潍坊: [119.161, 36.706],
};
let poiSeq = 0;

/** 城市中心坐标（未登记的城市给一个合法兜底，保证管线不因缺坐标而走异常分支）。 */
function geoOf(city) {
  return CITY_GEO[city] || [116.407, 39.904];
}

/** /v3/place/text 响应：按 keywords 判定返回景点 or 交通枢纽。 */
function textPois(params) {
  const city = String(params.get('city') || '');
  const kw = String(params.get('keywords') || '');
  const [clng, clat] = geoOf(city);
  const isStation = /火车站|高铁站/.test(kw);
  const isAirport = /机场/.test(kw);
  const typecode = isStation ? '150200' : isAirport ? '150100' : '110200';
  const typeText = isStation ? '交通设施服务;火车站' : isAirport ? '交通设施服务;机场' : '风景名胜;风景名胜';
  const pois = [];
  for (let i = 0; i < 6; i++) {
    poiSeq += 1;
    pois.push({
      id: `P${poiSeq}`,
      name: isStation ? `${city}火车站` : isAirport ? `${city}机场` : `${city}景点${poiSeq}`,
      location: `${(clng + i * 0.012).toFixed(6)},${(clat + i * 0.012).toFixed(6)}`,
      address: `${city}某路${i}号`,
      cityname: city,
      adname: `${city}某区`,
      typecode,
      type: typeText,
      biz_ext: { rating: '4.5', cost: null, opentime: '08:00-18:00' },
    });
  }
  return { status: '1', infocode: '10000', count: String(pois.length), pois };
}

/** /v3/place/around 响应：酒店要给 biz_ext.cost（比价/当日合计的数据源）。 */
function aroundPois(params) {
  const types = String(params.get('types') || '');
  const kw = String(params.get('keywords') || '');
  const location = String(params.get('location') || '116.407,39.904');
  const [clng, clat] = location.split(',').map(Number);
  let n = 3;
  let maker;
  if (types === '100000') {
    maker = (i) => ({
      typecode: '100100',
      type: '住宿服务;四星级宾馆;宾馆酒店',
      name: `测试酒店${i}`,
      biz_ext: { rating: '4.6', cost: `${300 + i * 100}-${500 + i * 100}`, opentime: '00:00-24:00' },
    });
  } else if (types === '050000') {
    maker = (i) => ({
      typecode: '050100',
      type: '餐饮服务;中餐厅',
      name: `测试餐厅${i}`,
      biz_ext: { rating: '4.3', cost: '80', opentime: '10:00-22:00' },
    });
  } else if (/充电站|充电桩/.test(kw)) {
    maker = (i) => ({ typecode: '010000', type: '汽车服务;充电站', name: `充电站${i}`, biz_ext: { rating: '4.0', cost: null } });
  } else if (/服务区/.test(kw)) {
    maker = (i) => ({ typecode: '010000', type: '汽车服务;服务区', name: `服务区${i}`, biz_ext: { rating: '4.0', cost: null } });
  } else if (/租车/.test(kw)) {
    maker = (i) => ({ typecode: '010000', type: '汽车服务;汽车租赁', name: `租车点${i}`, biz_ext: { rating: '4.2', cost: null } });
  } else {
    maker = (i) => ({
      typecode: '110200',
      type: '风景名胜;风景名胜',
      name: `周边景点${i}`,
      biz_ext: { rating: '4.4', cost: null, opentime: '08:00-18:00' },
    });
  }
  const pois = [];
  for (let i = 0; i < n; i++) {
    poiSeq += 1;
    const m = maker(i + 1);
    pois.push({
      id: `A${poiSeq}`,
      name: m.name,
      location: `${(clng + i * 0.008).toFixed(6)},${(clat + i * 0.008).toFixed(6)}`,
      address: '测试地址',
      cityname: '测试市',
      adname: '测试区',
      typecode: m.typecode,
      type: m.type,
      biz_ext: m.biz_ext,
    });
  }
  return { status: '1', infocode: '10000', count: String(pois.length), pois };
}

/** 按 URL 路径返回 stub 响应体。 */
function stubFor(u) {
  const p = u.pathname;
  if (p === '/v3/geocode/geo') {
    const addr = String(u.searchParams.get('address') || '');
    const [lng, lat] = geoOf(addr);
    return { status: '1', infocode: '10000', geocodes: [{ formatted_address: addr, location: `${lng},${lat}` }] };
  }
  if (p === '/v3/place/text') return textPois(u.searchParams);
  if (p === '/v3/place/around') return aroundPois(u.searchParams);
  if (p === '/v3/direction/driving') {
    return { status: '1', infocode: '10000', route: { paths: [{ duration: '3600', distance: '150000' }] } };
  }
  if (p === '/v3/direction/transit/integrated') {
    return { status: '1', infocode: '10000', route: { transits: [{ duration: '1800', distance: '15000' }] } };
  }
  if (p === '/v3/direction/walking') {
    return { status: '1', infocode: '10000', route: { paths: [{ duration: '720', distance: '900' }] } };
  }
  if (p === '/v3/intercity/transit') {
    return { status: '1', infocode: '10000', data: { transits: [] } };
  }
  return { status: '1', infocode: '10000' };
}

globalThis.fetch = async (url) => {
  const u = new URL(String(url));
  callLog.push(u.pathname);
  const body = stubFor(u);
  return {
    ok: true,
    status: 200,
    text: async () => JSON.stringify(body),
    json: async () => body,
  };
};

// ---------------------------------------------------------------------------
// 2. 用例 A（M1 回归哨兵）：传合法 schedules，必须不崩且返回 200 级结果
// ---------------------------------------------------------------------------
console.log('=== corridor 冒烟测试（T01）===\n');
const START = '2026-10-01';
const baseInput = {
  origin: '北京',
  cities: ['天津', '潍坊'],
  days: 4,
  startDate: START,
  tripMode: 'pureDrive',
  pace: 'normal',
  interests: ['nature', 'culture'],
  adults: 2,
  children: 1,
  rooms: 1,
};

let resA = null;
let errA = null;
try {
  resA = await planCorridor({
    ...baseInput,
    schedules: [
      { from: '北京', to: '天津', vehicle: 'highSpeedTrain', no: 'G123', dep: '09:15', arr: '10:30', price: 268 },
      { from: '天津', to: '潍坊', dep: '25:00', arr: '26:00' }, // 非法时刻 → 应被 parseSchedules 剔除
    ],
  });
} catch (e) {
  errA = e;
}
check('A1 传 schedules 不再 500（M1 TDZ 修复）', errA === null, errA ? `${errA.name}: ${errA.message}` : '');

if (resA) {
  check('A2 返回 trip.days 非空', Array.isArray(resA.trip.days) && resA.trip.days.length > 0,
    `days=${resA.trip.days ? resA.trip.days.length : 'N/A'}`);
  check('A3 days[0].date == startDate', resA.trip.days[0].date === START,
    `days[0].date=${resA.trip.days[0].date}`);

  // FX-01 下游验证：逐日不得跳号（东八区旧实现会整体少一天）
  let seqOk = true;
  let seqBad = '';
  resA.trip.days.forEach((d, i) => {
    const exp = addDays(START, i);
    if (d.date !== exp) { seqOk = false; seqBad = `第${i + 1}天 期望 ${exp} 实际 ${d.date}`; }
  });
  check('A4 逐日日期连续且与 addDays 一致（FX-01 下游）', seqOk, seqBad);

  check('A5 trip.endDate == startDate + days - 1',
    resA.trip.endDate === addDays(START, resA.trip.days.length - 1),
    `endDate=${resA.trip.endDate}`);

  check('A6 stats.cost 存在（客户端 statsCost 取数点）',
    Boolean(resA.stats && resA.stats.cost), JSON.stringify(resA.stats && resA.stats.cost));
  check('A7 stats.cost.total 为数值且 currency=CNY',
    Number.isFinite(resA.stats.cost.total) && resA.stats.cost.currency === 'CNY',
    `total=${resA.stats.cost.total} currency=${resA.stats.cost.currency}`);

  check('A8 班次已被加载（warnings 含"真实班次"）',
    resA.warnings.some((w) => String(w).includes('真实班次')),
    resA.warnings.slice(0, 3).join(' | '));
  check('A9 stats.schedulesLoaded == 1（非法时刻已剔除）',
    resA.stats.schedulesLoaded === 1, `schedulesLoaded=${resA.stats.schedulesLoaded}`);

  // 跨城段：isFixed / price / estimated 三个新字段（T02 Transport 模型的上游）
  const intercity = [];
  for (const d of resA.trip.days) {
    for (const l of d.locations) {
      if (l.transport && l.transport.scope === 'intercity') intercity.push(l.transport);
    }
  }
  check('A10 存在跨城段（scope=intercity）', intercity.length > 0, `count=${intercity.length}`);
  const fixed = intercity.find((t) => t.isFixed === true);
  check('A11 真实班次段 transport.isFixed=true 且 price=268',
    Boolean(fixed) && fixed.price === 268, fixed ? JSON.stringify(fixed) : '未找到');
  check('A12 跨城段 100% 明标 isFixed/estimated（不得两个都缺省）',
    intercity.every((t) => t.isFixed === true || t.estimated === true),
    JSON.stringify(intercity.map((t) => ({ isFixed: t.isFixed, estimated: t.estimated }))));

  // 酒店：hotelCandidates 必须带 cost（当日合计来源 A 的上游）
  const hotels = [];
  for (const d of resA.trip.days) {
    for (const l of d.locations) {
      if (l.type === 'hotel') hotels.push(l);
    }
  }
  check('A13 存在酒店点', hotels.length > 0, `hotels=${hotels.length}`);
  const withCand = hotels.find((h) => Array.isArray(h.hotelCandidates) && h.hotelCandidates.length);
  check('A14 hotelCandidates 带 cost 字段（来源 A 可用）',
    Boolean(withCand) && withCand.hotelCandidates.every((c) => typeof c.cost === 'string'),
    withCand ? JSON.stringify(withCand.hotelCandidates[0]) : '无候选');

  // 【裁 5 上游根治】酒店点自身直接带 cost → 客户端不再依赖"按 name 回匹配 hotelCandidates"
  check('A15 酒店点自身带 cost（非 null，消除 name 回匹配脆弱约定）',
    hotels.every((h) => typeof h.cost === 'string' && h.cost.length > 0),
    JSON.stringify(hotels.map((h) => ({ name: h.name, cost: h.cost }))));
}

// ---------------------------------------------------------------------------
// 3. 用例 B：不传 schedules 的基线也正常（证明 A 的修复没有副作用）
// ---------------------------------------------------------------------------
let resB = null;
let errB = null;
try {
  resB = await planCorridor({ ...baseInput });
} catch (e) {
  errB = e;
}
check('B1 不传 schedules 不崩', errB === null, errB ? `${errB.name}: ${errB.message}` : '');
if (resB) {
  check('B2 days[0].date == startDate', resB.trip.days[0].date === START, resB.trip.days[0].date);
  check('B3 stats.cost 存在', Boolean(resB.stats && resB.stats.cost));
  check('B4 schedulesLoaded == 0', resB.stats.schedulesLoaded === 0, `${resB.stats.schedulesLoaded}`);
}

// 用例 B′：pureTransit 且不传班次 —— 覆盖"估算占位"分支（estimated=true / isFixed=false）
let resT = null;
let errT = null;
try {
  resT = await planCorridor({ ...baseInput, tripMode: 'pureTransit' });
} catch (e) {
  errT = e;
}
check('B5 pureTransit 无班次也不崩', errT === null, errT ? `${errT.name}: ${errT.message}` : '');
if (resT) {
  const icT = [];
  for (const d of resT.trip.days) {
    for (const l of d.locations) {
      if (l.transport && l.transport.scope === 'intercity') icT.push(l.transport);
    }
  }
  check('B6 存在跨城段', icT.length > 0, `count=${icT.length}`);
  check('B7 无班次段 estimated=true / isFixed=false（诚实标注占位）',
    icT.length > 0 && icT.every((t) => t.estimated === true && t.isFixed === false),
    JSON.stringify(icT.map((t) => ({ isFixed: t.isFixed, estimated: t.estimated }))));
  check('B8 days[0].date == startDate', resT.trip.days[0].date === START, resT.trip.days[0].date);
}

// ---------------------------------------------------------------------------
// 4. 用例 C/D：入参上限（M2 止血）
// ---------------------------------------------------------------------------
async function expectHttpError(label, fn, status, mustInclude) {
  try {
    await fn();
    check(label, false, '未抛异常（期望被 400 拦截）');
    return null;
  } catch (e) {
    const ok = e.status === status && String(e.message).includes(mustInclude);
    check(label, ok, `${e.status || '(无 status)'} · ${e.message}`);
    return e;
  }
}

await expectHttpError(
  'C1 cities 超限 → 400 且回显实际数量（100）',
  () => planCorridor({ ...baseInput, cities: Array.from({ length: 100 }, (_, i) => `城市${i}`) }),
  400,
  '100'
);
await expectHttpError(
  'C2 cities 恰好 8 个不拦截（仅校验，不发网络）',
  () => planCorridor({ ...baseInput, cities: Array.from({ length: 8 }, (_, i) => `城市${i}`), origin: '' }),
  400,
  '出发地' // origin 校验先于 cities，走到这里说明 8 个城市没被上限拦
);

const bigDays = Array.from({ length: 6 }, (_, i) => ({
  date: addDays(START, i),
  dayNumber: i + 1,
  locations: Array.from({ length: 10 }, (_, k) => ({
    name: `点${i}-${k}`, latitude: 39.9, longitude: 116.4, city: '北京', type: 'attraction', stayMinutes: 60,
  })),
}));
await expectHttpError(
  'D1 recalc 全行程 locations > 50 → 400 且回显实际数量（60）',
  () => recalcTrip({ trip: { tripMode: 'pureDrive', days: bigDays } }),
  400,
  '60'
);
let recalcOk = false;
try {
  await recalcTrip({ trip: { tripMode: 'pureDrive', days: bigDays.slice(0, 4) } }); // 40 个 → 放行
  recalcOk = true;
} catch (e) {
  recalcOk = false;
  console.log(`       ↳ 40 个点的 recalc 抛错：${e.message}`);
}
check('D2 recalc 40 个点放行（上限不是误伤）', recalcOk);

// ---------------------------------------------------------------------------
// 5. 用例 E：限流（第 6 次 corridor 请求返回 429）—— 走真实 HTTP，验证已挂到路由上
// ---------------------------------------------------------------------------
globalThis.fetch = realFetch; // 恢复真身（本段需要真实 localhost 请求）
const app = express();
app.use(express.json());
registerMultiCityRoutes(app);
app.use((err, req, res, next) => {
  res.status(err.status || 500).json({ error: err.expose ? err.message : '服务内部错误' });
});
const server = app.listen(0, '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const port = server.address().port;
const url = `http://127.0.0.1:${port}/api/planner/corridor`;

const statuses = [];
// 空 body：planCorridor 在第一行就 400（不碰网络），所以 1~5 次应该是 400，第 6 次被限流成 429
for (let i = 1; i <= 6; i++) {
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({}),
  });
  statuses.push(resp.status);
}
check('E1 前 5 次 corridor 未被限流（400 来自参数校验）',
  statuses.slice(0, 5).every((s) => s === 400), `statuses=[${statuses.join(',')}]`);
check('E2 第 6 次 corridor 返回 429（限流生效）',
  statuses[5] === 429, `第6次=${statuses[5]} 全部=[${statuses.join(',')}]`);

// 限流器必须按实例隔离：recalc 不应被 corridor 的计数连坐
const recalcStatuses = [];
for (let i = 1; i <= 5; i++) {
  const resp = await fetch(`http://127.0.0.1:${port}/api/planner/recalc`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({}),
  });
  recalcStatuses.push(resp.status);
}
check('E3 recalc 独立计数，不被 corridor 连坐（前 5 次为 400）',
  recalcStatuses.every((s) => s === 400), `recalc=[${recalcStatuses.join(',')}]`);

server.close();

console.log(`\n（stub 期间共拦截高德调用 ${callLog.length} 次：${[...new Set(callLog)].join(', ')}）`);
console.log(failed ? `\n${failed} test(s) FAILED` : '\nALL TESTS PASSED');
process.exit(failed ? 1 : 0);
