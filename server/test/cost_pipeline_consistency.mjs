// 两条管线的 `cost` 字段形态一致性验证（**只验证，不改代码**）
//
// 背景：
//   - planner.js 管线（单城生成）：generateTrip → gatherCandidates / findNearbyRestaurant
//     / findHotels → normalizePoi() → toLocation()
//   - multiCity.js 管线（多城走廊）：planCorridor → **复用** planner 的 buildDay /
//     findHotels / toLocation（facade 模式），另有自己的 hotelLoc.cost 赋值
//   ⇒ "共用代码"不等于"共用行为"：multiCity 里有独立的 `hotelLoc.cost = ...` 赋值
//     （:691/:712），可能把归一后的 null 反向覆盖成原始空数组。
//
// ⚠️ 本文件的 stub **按 FX-06a 真实探针的形态构造**，不是理想化数据：
//     餐饮 biz_ext.cost = "150.00"（18/20 有值）
//     酒店 biz_ext.cost = []      （0/20 全空，**空数组而非 null/空串**）
//     景点 biz_ext.cost = []      （0/20 全空）
//
// 运行：node server/test/cost_pipeline_consistency.mjs
process.env.AMAP_KEY = process.env.AMAP_KEY || 'stub-key-for-test';
process.env.TZ = process.env.TZ || 'UTC';

import { generateTrip, costOf, costText, parseCost } from '../src/planner.js';
import { planCorridor } from '../src/multiCity.js';

let failed = 0;
function check(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ' | ' + extra : ''}`);
  if (!cond) failed++;
}

// ---------------------------------------------------------------------------
// stub：形态严格对齐探针（酒店/景点 = []，餐饮 = "150.00"）
// ---------------------------------------------------------------------------
// 青岛：**只给第 5 段反向证明用**，坐标必须唯一 —— amapProxy 对 /place/ 有内存缓存
// （key = path + 全量 query），复用同一城市的坐标会命中前面用例的缓存，导致反向证明失真。
const CITY_GEO = {
  北京: [116.407, 39.904],
  天津: [117.201, 39.085],
  潍坊: [119.161, 36.706],
  青岛: [120.383, 36.067],
  烟台: [121.391, 37.539],
};
let poiSeq = 0;
function geoOf(c) { return CITY_GEO[c] || [116.407, 39.904]; }

function mkPoi({ id, name, lng, lat, typecode, type, city, cost }) {
  return {
    id, name,
    location: `${lng.toFixed(6)},${lat.toFixed(6)}`,
    address: '测试地址',
    cityname: city,
    adname: `${city}某区`,
    typecode,
    type,
    biz_ext: { rating: '4.5', cost, opentime: '08:00-18:00' },
  };
}

function textPois(params) {
  const city = String(params.get('city') || '');
  const kw = String(params.get('keywords') || '');
  const [clng, clat] = geoOf(city);
  const isStation = /火车站|高铁站/.test(kw);
  const isAirport = /机场/.test(kw);
  const pois = [];
  for (let i = 0; i < 6; i++) {
    poiSeq += 1;
    pois.push(mkPoi({
      id: `P${poiSeq}`,
      name: isStation ? `${city}火车站` : isAirport ? `${city}机场` : `${city}景点${poiSeq}`,
      lng: clng + i * 0.012, lat: clat + i * 0.012,
      typecode: isStation ? '150200' : isAirport ? '150100' : '110200',
      type: isStation ? '交通设施服务;火车站' : isAirport ? '交通设施服务;机场' : '风景名胜;风景名胜',
      city,
      cost: [], // ← 探针实测：景点 0/20 全空，形态是空数组
    }));
  }
  return { status: '1', infocode: '10000', count: String(pois.length), pois };
}

function aroundPois(params) {
  const types = String(params.get('types') || '');
  const kw = String(params.get('keywords') || '');
  const location = String(params.get('location') || '116.407,39.904');
  const [clng, clat] = location.split(',').map(Number);
  let maker;
  if (types === '100000') {
    // 酒店：探针实测 0/20 全空，形态是空数组
    maker = (i) => ({ typecode: '100100', type: '住宿服务;四星级宾馆;宾馆酒店', name: `测试酒店${i}`, cost: [] });
  } else if (types === '050000') {
    // 餐饮：探针实测 18/20 有值，人均字符串
    maker = (i) => ({ typecode: '050100', type: '餐饮服务;中餐厅', name: `测试餐厅${i}`, cost: '150.00' });
  } else if (/充电站|充电桩|服务区|租车/.test(kw)) {
    maker = (i) => ({ typecode: '010000', type: '汽车服务', name: `汽车服务${i}`, cost: [] });
  } else {
    maker = (i) => ({ typecode: '110200', type: '风景名胜;风景名胜', name: `周边景点${i}`, cost: [] });
  }
  const pois = [];
  for (let i = 0; i < 3; i++) {
    poiSeq += 1;
    const m = maker(i + 1);
    pois.push(mkPoi({ id: `A${poiSeq}`, name: m.name, lng: clng + i * 0.008, lat: clat + i * 0.008, typecode: m.typecode, type: m.type, city: '测试市', cost: m.cost }));
  }
  return { status: '1', infocode: '10000', count: String(pois.length), pois };
}

function stubFor(u) {
  const p = u.pathname;
  if (p === '/v3/geocode/geo') {
    const addr = String(u.searchParams.get('address') || '');
    const [lng, lat] = geoOf(addr);
    return { status: '1', infocode: '10000', geocodes: [{ formatted_address: addr, location: `${lng},${lat}` }] };
  }
  if (p === '/v3/place/text') return textPois(u.searchParams);
  if (p === '/v3/place/around') return aroundPois(u.searchParams);
  if (p === '/v3/direction/driving') return { status: '1', infocode: '10000', route: { paths: [{ duration: '3600', distance: '150000' }] } };
  if (p === '/v3/direction/transit/integrated') return { status: '1', infocode: '10000', route: { transits: [{ duration: '1800', distance: '15000' }] } };
  if (p === '/v3/direction/walking') return { status: '1', infocode: '10000', route: { paths: [{ duration: '720', distance: '900' }] } };
  if (p === '/v3/intercity/transit') return { status: '1', infocode: '10000', data: { transits: [] } };
  return { status: '1', infocode: '10000' };
}

globalThis.fetch = async (url) => {
  const u = new URL(String(url));
  const body = stubFor(u);
  return { ok: true, status: 200, text: async () => JSON.stringify(body), json: async () => body };
};

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------
/** 客户端 `_costString()`（ai_plan_page.dart:130）的等价实现，用于验证两端兼容。 */
function costStringClient(raw) {
  if (typeof raw === 'string') return raw === '' ? null : raw;
  if (typeof raw === 'number') return String(raw);
  return null; // 含空数组、null、undefined
}

function shapeOf(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  return typeof v;
}

/** 收集一条管线里所有 location 的 cost 形态分布 */
function scanLocations(days, label) {
  const stats = { total: 0, byShape: {}, hotels: [], meals: [], candidates: [] };
  for (const d of days || []) {
    for (const l of d.locations || []) {
      stats.total += 1;
      const s = shapeOf(l.cost);
      stats.byShape[s] = (stats.byShape[s] || 0) + 1;
      if (l.type === 'hotel') stats.hotels.push({ name: l.name, cost: l.cost, shape: s });
      if (l.type === 'restaurant') stats.meals.push({ name: l.name, cost: l.cost, shape: s });
      for (const c of l.hotelCandidates || []) {
        stats.candidates.push({ name: c.name, cost: c.cost, shape: shapeOf(c.cost) });
      }
    }
  }
  console.log(`\n[${label}] 共 ${stats.total} 个 location，cost 形态分布：${JSON.stringify(stats.byShape)}`);
  if (stats.hotels.length) {
    console.log(`  酒店(${stats.hotels.length})：${stats.hotels.slice(0, 3).map((h) => `${h.name}=${JSON.stringify(h.cost)}(${h.shape})`).join(' , ')}`);
  }
  if (stats.meals.length) {
    console.log(`  餐饮(${stats.meals.length})：${stats.meals.slice(0, 3).map((h) => `${h.name}=${JSON.stringify(h.cost)}(${h.shape})`).join(' , ')}`);
  }
  if (stats.candidates.length) {
    console.log(`  hotelCandidates(${stats.candidates.length})：${stats.candidates.slice(0, 3).map((h) => `${h.name}=${JSON.stringify(h.cost)}(${h.shape})`).join(' , ')}`);
  }
  return stats;
}

// ---------------------------------------------------------------------------
console.log('=== 两条管线 cost 形态一致性验证 ===\n');

// ---- 0. 归一函数与展示函数的单元行为 ----
console.log('--- 0. costOf / costText 单元 ---');
check('U1 costOf([]) → null（空数组必须归一，不能原样透传）', costOf({ biz_ext: { cost: [] } }) === null);
check('U2 costOf("150.00") → "150.00"', costOf({ biz_ext: { cost: '150.00' } }) === '150.00');
check('U3 costText([]) → null（不产出悬空 ¥）', costText([]) === null);
check('U4 costText("300-500") → "¥300-500"', costText('300-500') === '¥300-500');
check('U5 costText("400") → "¥400"', costText('400') === '¥400');
check('U6 parseCost 是 costText 的唯一判空入口（同源）',
  (costText('300-500') !== null) === (parseCost('300-500') !== null));

// ---- 1. planner 管线（单城生成） ----
const gen = await generateTrip({
  city: '北京', days: 3, startDate: '2026-10-01', pace: 'normal',
  interests: ['nature', 'culture'], tripMode: 'pureTransit', budget: 'comfort',
  adults: 2, children: 1, rooms: 1,
});
const genStats = scanLocations(gen.trip?.days, 'planner / generateTrip');

// ---- 2. multiCity 管线（多城走廊） ----
const cor = await planCorridor({
  origin: '北京', cities: ['天津', '潍坊'], days: 4, startDate: '2026-10-01',
  tripMode: 'pureDrive', pace: 'normal', interests: ['nature', 'culture'],
  adults: 2, children: 1, rooms: 1,
});
const corStats = scanLocations(cor.trip?.days, 'multiCity / planCorridor');

// ---- 3. 一致性断言 ----
console.log('\n--- 3. 一致性断言 ---');

const allShapes = [...Object.keys(genStats.byShape), ...Object.keys(corStats.byShape)];
check('C1 两条管线都不产出**数组**形态的 cost（空数组不得泄漏到客户端）',
  !allShapes.includes('array'), allShapes.join(', '));

check('C2 两条管线都只有 string / null 两种形态',
  allShapes.every((s) => s === 'string' || s === 'null'), allShapes.join(', '));

// 酒店：探针实测 0/20 全空 → 两条管线都应恒 null
const genHotelShapes = [...new Set(genStats.hotels.map((h) => h.shape))];
const corHotelShapes = [...new Set(corStats.hotels.map((h) => h.shape))];
check('C3 planner 管线：酒店 cost 恒 null（探针实测 0/20 全空）',
  genStats.hotels.length === 0 || genHotelShapes.every((s) => s === 'null'),
  `n=${genStats.hotels.length} shapes=${genHotelShapes.join(',')}`);
check('C4 multiCity 管线：酒店 cost 恒 null（**重点**：验证 :691/:712 没把 [] 覆盖回去）',
  corStats.hotels.length === 0 || corHotelShapes.every((s) => s === 'null'),
  `n=${corStats.hotels.length} shapes=${corHotelShapes.join(',')}`);

// 两条管线的形态集合必须相同（不能一条给 "300-500"、另一条给 null）
const genSet = [...new Set(genStats.hotels.map((h) => h.shape))].sort().join('|');
const corSet = [...new Set(corStats.hotels.map((h) => h.shape))].sort().join('|');
check('C5 两条管线的**酒店** cost 形态集合一致', genSet === corSet, `planner=${genSet} multiCity=${corSet}`);

const genMealSet = [...new Set(genStats.meals.map((h) => h.shape))].sort().join('|');
const corMealSet = [...new Set(corStats.meals.map((h) => h.shape))].sort().join('|');
check('C6 两条管线的**餐饮** cost 形态集合一致', genMealSet === corMealSet,
  `planner=${genMealSet} multiCity=${corMealSet}`);

// hotelCandidates[].cost 也不能是数组
const candArray = [...genStats.candidates, ...corStats.candidates].filter((c) => c.shape === 'array');
check('C7 hotelCandidates[].cost 不含数组形态', candArray.length === 0,
  candArray.slice(0, 3).map((c) => `${c.name}=${JSON.stringify(c.cost)}`).join(' , '));

// ---- 4. 客户端 _costString() 对两条管线输出都能正确解析 ----
console.log('\n--- 4. 客户端 _costString() 兼容性 ---');
const allCosts = [
  ...genStats.hotels.map((h) => h.cost), ...corStats.hotels.map((h) => h.cost),
  ...genStats.meals.map((h) => h.cost), ...corStats.meals.map((h) => h.cost),
  ...genStats.candidates.map((h) => h.cost), ...corStats.candidates.map((h) => h.cost),
];
const parsed = allCosts.map(costStringClient);
check('D1 所有 cost 都能被 _costString() 处理且不抛异常', parsed.length === allCosts.length);
check('D2 null → null（不产生空串 / "null"）',
  allCosts.every((c, i) => (c === null ? parsed[i] === null : true)));
check('D3 字符串原样返回（"150.00" 不被截断）',
  allCosts.every((c, i) => (typeof c === 'string' ? parsed[i] === c : true)));
check('D4 若真有数组泄漏，_costString 会返回 null 而非把 [] 当价格（已由 C1 保证不发生）',
  costStringClient([]) === null);

// ---- 5. 反向证明：如果 stub 给酒店真值，两条管线应当同时拿到 string ----
console.log('\n--- 5. 反向证明（把 stub 改成"酒店有价"，确认管线能透传）---');
// ⚠️ amapProxy 对 `/place/` 有内存缓存（key = path + 全量 query，见 amapProxy.js:62-79）。
//    第 1/2 段已经把 北京/天津/潍坊 的酒店查询缓存住了；反向证明若复用这些坐标，
//    `globalThis.fetch` **根本不会被调用** → 断言必失败，而失败原因在测试脚手架、
//    不在产品代码（我第一次跑就踩了这个坑，误判成 multiCity 透传断裂）。
//    ⇒ 这里改用此前从未出现过的城市 青岛/烟台，保证一定发真实请求。
const baseFetch = globalThis.fetch;
globalThis.fetch = async (url) => {
  const u = new URL(String(url));
  let body = stubFor(u);
  if (u.pathname === '/v3/place/around' && String(u.searchParams.get('types') || '') === '100000') {
    const [clng, clat] = String(u.searchParams.get('location') || '116.407,39.904').split(',').map(Number);
    body = {
      status: '1', infocode: '10000', count: '3',
      pois: [1, 2, 3].map((i) => mkPoi({
        id: `H${i}`, name: `有价酒店${i}`, lng: clng + i * 0.008, lat: clat + i * 0.008,
        typecode: '100100', type: '住宿服务;四星级宾馆;宾馆酒店', city: '青岛', cost: '300-500',
      })),
    };
  }
  return { ok: true, status: 200, text: async () => JSON.stringify(body), json: async () => body };
};
const cor2 = await planCorridor({
  origin: '青岛', cities: ['烟台'], days: 2, startDate: '2026-10-01',
  tripMode: 'pureDrive', pace: 'normal', interests: ['nature'], adults: 2, children: 0, rooms: 1,
});
globalThis.fetch = baseFetch;
const hotels2 = (cor2.trip?.days || []).flatMap((d) => (d.locations || []).filter((l) => l.type === 'hotel'));
check('E1 stub 给酒店真值时，multiCity 管线能透传 string（证明链路没断，只是源头无数据）',
  hotels2.length > 0 && hotels2.every((h) => typeof h.cost === 'string'),
  `n=${hotels2.length} 样例=${JSON.stringify(hotels2[0]?.cost)}`);
check('E2 透传的值可被 costText 格式化（无悬空 ¥）',
  hotels2.every((h) => costText(h.cost) !== null), JSON.stringify(hotels2[0]?.cost));
check('E2b 有价时 hotelCandidates[].cost 也是 string（客户端"换住"卡片同样有价）',
  hotels2.every((h) => (h.hotelCandidates || []).every((c) => typeof c.cost === 'string')));
// 反向证明的另一半：有价时 SR-04b 的"按星级兜底"**不应该**触发
const warn2 = (cor2.warnings || []).join(' | ');
check('E3 有价时预算档按价格生效 → 推荐理由里出现 ¥，且不出现"按星级匹配"降级文案',
  /¥300-500/.test(warn2) && !/档位按星级匹配/.test(warn2),
  warn2.slice(0, 160));

// ---- 6. 字段存在性：两条管线都必须**带** cost 键，且不能出现第三种形态 ----
console.log('\n--- 6. 字段存在性与形态封闭性 ---');
const allLocs = [
  ...(gen.trip?.days || []).flatMap((d) => d.locations || []),
  ...(cor.trip?.days || []).flatMap((d) => d.locations || []),
];
const missingKey = allLocs.filter((l) => !('cost' in l));
check('F1 两条管线的每个 location 都带 cost 键（JSON 序列化后客户端不会遇到缺键）',
  missingKey.length === 0, `缺键 ${missingKey.length} 个：${missingKey.slice(0, 3).map((l) => l.name).join(' , ')}`);
const badShape = allLocs.filter((l) => ['undefined', 'array', 'object', 'boolean'].includes(shapeOf(l.cost)));
check('F2 不存在 undefined / array / object / boolean 第三形态',
  badShape.length === 0, badShape.slice(0, 3).map((l) => `${l.name}=${JSON.stringify(l.cost)}`).join(' , '));
const emptyStr = allLocs.filter((l) => l.cost === '');
check('F3 不存在空串形态（空串会变成悬空 ¥ 的另一种入口）',
  emptyStr.length === 0, emptyStr.slice(0, 3).map((l) => l.name).join(' , '));

console.log('');
if (failed === 0) console.log('ALL TESTS PASSED');
else { console.log(`${failed} CHECK(S) FAILED`); process.exit(1); }
