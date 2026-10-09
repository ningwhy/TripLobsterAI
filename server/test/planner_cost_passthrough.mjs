// SR-02 / SR-04 回归测试（server/src/planner.js）
//
// 背景：FX-06a 真实 AMAP_KEY 探针实测
//   餐饮 biz_ext.cost：18/20 有值（人均，如 "150.00"）
//   酒店 / 景点 biz_ext.cost：**0/20 全空**，且形态是**空数组 []**（JS 里 truthy！）
//
// 本文件断言三件事：
//   SR-02  cost 从 normalizePoi → toLocation 完整透传，且空数组归一为 null
//   SR-04a 推荐理由不再出现悬空的「¥」（旧写法 `if (h.cost)` 被 [] 骗过）
//   SR-04b 预算档在"无价格源"时不至于完全失效（降级到星级档）
//
// 运行：node server/test/planner_cost_passthrough.mjs
process.env.AMAP_KEY = process.env.AMAP_KEY || 'stub-key-for-test';
process.env.TZ = process.env.TZ || 'UTC';

import { normalizePoi, toLocation, findHotels } from '../src/planner.js';

let failed = 0;
function check(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ' | ' + extra : ''}`);
  if (!cond) failed++;
}

// ---------------------------------------------------------------------------
// stub globalThis.fetch：只服务 /v3/place/around（findHotels 用），其余给空响应
// ---------------------------------------------------------------------------
/** 测试可写：下一次 /v3/place/around 返回的 POI 列表 */
let hotelFixture = [];
const aroundCalls = [];

function mkHotel({ id, name, cost, typeText, lng = 116.407, lat = 39.904 }) {
  return {
    id,
    name,
    location: `${lng},${lat}`,
    address: '测试地址',
    cityname: '北京',
    adname: '东城区',
    typecode: '100100',
    rating: '4.6',
    type: typeText,
    biz_ext: { cost, rating: '4.6' },
  };
}

globalThis.fetch = async (url) => {
  const u = new URL(String(url));
  aroundCalls.push(u.pathname);
  let body;
  if (u.pathname.includes('/place/around')) {
    body = { status: '1', infocode: '10000', count: String(hotelFixture.length), pois: hotelFixture };
  } else {
    body = { status: '1', infocode: '10000' };
  }
  return {
    ok: true,
    status: 200,
    text: async () => JSON.stringify(body),
    json: async () => body,
  };
};

// ---------------------------------------------------------------------------
// 1. SR-02：normalizePoi 的 cost 归一
// ---------------------------------------------------------------------------
console.log('--- SR-02 normalizePoi cost 归一 ---');

const base = { location: '116.407,39.904', name: '某店', typecode: '050100' };

check('N1 有值字符串 "150.00" 原样透传',
  normalizePoi({ ...base, biz_ext: { cost: '150.00' } }).cost === '150.00',
  String(normalizePoi({ ...base, biz_ext: { cost: '150.00' } }).cost));

check('N2 空数组 [] → null（关键：[] 在 JS 里 truthy，不能原样透传）',
  normalizePoi({ ...base, biz_ext: { cost: [] } }).cost === null,
  JSON.stringify(normalizePoi({ ...base, biz_ext: { cost: [] } }).cost));

check('N3 无 biz_ext → null', normalizePoi({ ...base }).cost === null);
check('N4 空字符串 → null', normalizePoi({ ...base, biz_ext: { cost: '' } }).cost === null);
check('N5 数值 150 → 字符串 "150"',
  normalizePoi({ ...base, biz_ext: { cost: 150 } }).cost === '150',
  String(normalizePoi({ ...base, biz_ext: { cost: 150 } }).cost));

check('N6 反向证明：若不做归一，[] 会让 if(cost) 判为 true（这就是悬空 ¥ 的根因）',
  Boolean([]) === true && ([] ? 'truthy' : 'falsy') === 'truthy');

// ---------------------------------------------------------------------------
// 2. SR-02：toLocation 透传
// ---------------------------------------------------------------------------
console.log('\n--- SR-02 toLocation 透传 ---');

const meal = normalizePoi({ ...base, biz_ext: { cost: '150.00' } });
const locMeal = toLocation({ ...meal, typecode: '050100' }, 720, 60, null, { isMeal: '午餐' });
check('L1 餐饮 cost 透传到地点层（客户端可离线取，无需联网）',
  locMeal.cost === '150.00', String(locMeal.cost));
check('L2 餐饮 type 仍为 restaurant（isMeal 分支）', locMeal.type === 'restaurant', locMeal.type);

const hotelNoCost = normalizePoi({ ...base, typecode: '100100', biz_ext: { cost: [] } });
const locHotel = toLocation({ ...hotelNoCost, typecode: '100100' }, 1200, 600, null, {});
check('L3 酒店 cost 恒 null（探针 0/20 全空 → 客户端降级为暂无参考价）',
  locHotel.cost === null, JSON.stringify(locHotel.cost));

// ---------------------------------------------------------------------------
// 3. SR-04a：推荐理由不再出现悬空 ¥
// ---------------------------------------------------------------------------
console.log('\n--- SR-04a 悬空 ¥ ---');

const party = { adults: 2, children: 0, rooms: 1, roomType: null };
// 注意：amapProxy 对 /place/ 有内存缓存，cache key 含 location → 每个用例换锚点坐标以绕过
function anchorsAt(lat) {
  return [{ poi: { lng: 116.407, lat }, w: 1 }];
}

// 用例 A：全部酒店 cost 为空数组（探针真实形态）
hotelFixture = [
  mkHotel({ id: 'h1', name: '四星酒店', cost: [], typeText: '住宿服务;四星级宾馆;星级酒店', lat: 39.901 }),
  mkHotel({ id: 'h2', name: '经济酒店', cost: [], typeText: '住宿服务;经济型连锁;连锁酒店', lat: 39.902 }),
  mkHotel({ id: 'h3', name: '五星酒店', cost: [], typeText: '住宿服务;五星级宾馆;星级酒店', lat: 39.903 }),
];
const candsA = await findHotels(anchorsAt(39.901), 'luxury', party);
const reasonsA = candsA.map((c) => c.reason);

check('H1 无价格时推荐理由不含任何「¥」（悬空 ¥ 已修）',
  reasonsA.every((r) => !r.includes('¥')), reasonsA.join(' ‖ '));
check('H2 无价格时不出现连续分隔符「··」',
  reasonsA.every((r) => !r.includes('··')), reasonsA.join(' ‖ '));
check('H3 返回了候选（管线未因缺价而崩）', candsA.length > 0, `${candsA.length} 个`);

// 反向证明：旧写法在这个 fixture 下确实会产出悬空 ¥
const oldBits = [];
const fakeH = { cost: [], rating: '4.6' };
if (fakeH.rating) oldBits.push(`口碑${fakeH.rating}`);
if (fakeH.cost) oldBits.push(`¥${fakeH.cost}`); // ← 旧实现原样
oldBits.push('四星');
check('H4 反向证明：旧实现在此 fixture 下产出悬空 ¥',
  oldBits.join('·').includes('·¥·'), oldBits.join('·'));

// 用例 B：酒店有真实价格 → 应正常展示且区间规范化
hotelFixture = [
  mkHotel({ id: 'p1', name: '有价酒店', cost: '300-500', typeText: '住宿服务;四星级宾馆;星级酒店', lat: 39.911 }),
  mkHotel({ id: 'p2', name: '单值酒店', cost: '400', typeText: '住宿服务;四星级宾馆;星级酒店', lat: 39.912 }),
];
const candsB = await findHotels(anchorsAt(39.911), 'comfort', party);
const priceReasons = candsB.map((c) => c.reason).join(' ‖ ');
check('H5 有价格时正常展示 ¥300-500（区间）', priceReasons.includes('¥300-500'), priceReasons);
check('H6 单值价格展示为 ¥400（不拼成区间）', priceReasons.includes('¥400'), priceReasons);

// ---------------------------------------------------------------------------
// 4. SR-04b：预算档在无价格源时降级到星级档（不再是 100% 失效）
// ---------------------------------------------------------------------------
console.log('\n--- SR-04b 预算档降级 ---');

// 用例 C：luxury 档（BUDGET_STARS.luxury = [4,5]）→ 经济型（2 星）应被排除
hotelFixture = [
  mkHotel({ id: 's1', name: '四星酒店', cost: [], typeText: '住宿服务;四星级宾馆;星级酒店', lat: 39.921 }),
  mkHotel({ id: 's2', name: '经济连锁', cost: [], typeText: '住宿服务;经济型连锁;连锁酒店', lat: 39.922 }),
  mkHotel({ id: 's3', name: '五星酒店', cost: [], typeText: '住宿服务;五星级宾馆;星级酒店', lat: 39.923 }),
];
const candsLux = await findHotels(anchorsAt(39.921), 'luxury', party);
check('B1 luxury 档排除经济型（预算档在有星级时确实生效）',
  !candsLux.some((c) => c.poi.name === '经济连锁'),
  candsLux.map((c) => c.poi.name).join(', '));
check('B2 luxury 档命中高档酒店',
  candsLux.some((c) => c.poi.name === '四星酒店' || c.poi.name === '五星酒店'),
  candsLux.map((c) => c.poi.name).join(', '));
check('B3 诚实降级：理由里明说按星级匹配，不假装按价格选过',
  candsLux.every((c) => c.reason.includes('档位按星级匹配（参考价缺失）')),
  candsLux.map((c) => c.reason).join(' ‖ '));

// 用例 D：economy 档（BUDGET_STARS.economy = [2,3]）→ 五星应被排除
hotelFixture = [
  mkHotel({ id: 'e1', name: '四星酒店', cost: [], typeText: '住宿服务;四星级宾馆;星级酒店', lat: 39.931 }),
  mkHotel({ id: 'e2', name: '经济连锁', cost: [], typeText: '住宿服务;经济型连锁;连锁酒店', lat: 39.932 }),
  mkHotel({ id: 'e3', name: '五星酒店', cost: [], typeText: '住宿服务;五星级宾馆;星级酒店', lat: 39.933 }),
];
// 锚点坐标与用例 C 不同 → 绕过 amapProxy 对 /place/ 的内存缓存
const candsEco = await findHotels([{ poi: { lng: 116.408, lat: 39.931 }, w: 1 }], 'economy', party);
check('B4 economy 档排除五星（预算档反向也成立）',
  !candsEco.some((c) => c.poi.name === '五星酒店'),
  candsEco.map((c) => c.poi.name).join(', '));
check('B5 economy 档命中经济型',
  candsEco.some((c) => c.poi.name === '经济连锁'),
  candsEco.map((c) => c.poi.name).join(', '));

// 用例 E：完全无星级信息 → 优雅降级回全量，且如实标注（不比修复前更差）
hotelFixture = [
  mkHotel({ id: 'n1', name: '无星酒店A', cost: [], typeText: '住宿服务;宾馆', lat: 39.941 }),
  mkHotel({ id: 'n2', name: '无星酒店B', cost: [], typeText: '住宿服务;招待所', lat: 39.942 }),
];
const candsNone = await findHotels([{ poi: { lng: 116.409, lat: 39.941 }, w: 1 }], 'luxury', party);
check('B6 无价格且无星级 → 优雅降级回全量（不比修复前更差）',
  candsNone.length === 2, candsNone.map((c) => c.poi.name).join(', '));
check('B7 降级时如实标注「档位未生效」',
  candsNone.every((c) => c.reason.includes('档位未生效')),
  candsNone.map((c) => c.reason).join(' ‖ '));

// ---------------------------------------------------------------------------
// 5. 回归：加了 cost 字段不影响既有字段
// ---------------------------------------------------------------------------
console.log('\n--- 回归 ---');

const full = normalizePoi({
  ...base,
  id: 'B001',
  address: '测试地址',
  cityname: '北京',
  adname: '东城区',
  rating: '4.6',
  type: '餐饮服务;中餐厅',
  biz_ext: { cost: '150.00' },
});
check('R1 新增 cost 不影响既有字段（id/city/district/typecode 仍在）',
  full.id === 'B001' && full.city === '北京' && full.district === '东城区' &&
      full.typecode === '050100' && full.typeText === '餐饮服务;中餐厅',
  JSON.stringify({ id: full.id, city: full.city, district: full.district, typeText: full.typeText }));
check('R2 name/lat/lng 仍正确',
  full.name === '某店' && full.lat === 39.904 && full.lng === 116.407,
  JSON.stringify({ n: full.name, lat: full.lat, lng: full.lng }));

const loc = toLocation({ ...meal, typecode: '050100' }, 720, 60, null, { isMeal: '午餐' });
check('R3 toLocation 既有字段未被动',
  loc.arrivalTime === '12:00' && loc.leaveTime === '13:00' && loc.mealFor === '午餐',
  `${loc.arrivalTime}/${loc.leaveTime}/${loc.mealFor}`);

console.log(`\n（stub 期间共拦截高德调用 ${aroundCalls.length} 次）`);
console.log('');
if (failed === 0) {
  console.log('ALL TESTS PASSED');
} else {
  console.log(`${failed} CHECK(S) FAILED`);
  process.exit(1);
}
