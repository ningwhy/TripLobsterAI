// 后端冒烟测试：注册/登录/同步/代理/天气/AI行程生成 全链路
const BASE = process.env.BASE || 'http://localhost:8787';

async function j(method, path, body, token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const resp = await fetch(BASE + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await resp.json().catch(() => null);
  if (!resp.ok) throw new Error(`${method} ${path} -> ${resp.status} ${JSON.stringify(data)}`);
  return data;
}

const ts = () => Date.now();
let failed = 0;
function check(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ' | ' + extra : ''}`);
  if (!cond) failed++;
}

// 1. auth（重名则走登录）
let auth;
try {
  auth = await j('POST', '/api/auth/register', { username: `tester_${ts()}`, password: 'pass123456' });
} catch {
  auth = await j('POST', '/api/auth/login', { username: 'tester', password: 'pass123456' });
}
check('auth', Boolean(auth?.token));
const token = auth.token;

// 2. sync push/pull + 墓碑删除
const tripId = `trip_${ts()}`;
const push = await j('POST', '/api/sync/push', {
  trips: [{ tripId, data: { id: tripId, name: '冒烟测试行程', days: [] }, updatedAt: ts() }],
  deleted: [],
}, token);
check('sync push', push.applied === 1);
let pull = await j('GET', '/api/sync/pull', null, token);
check('sync pull', pull.trips.some((t) => t.tripId === tripId));
const push2 = await j('POST', '/api/sync/push', {
  trips: [],
  deleted: [{ tripId, deletedAt: ts() + 1000 }],
}, token);
check('sync tombstone push', push2.applied === 1);
pull = await j('GET', '/api/sync/pull', null, token);
check('sync tombstone visible', pull.deleted.some((d) => d.tripId === tripId));

// 3. 高德代理
const poi = await j('GET', '/api/amap/v3/place/text?keywords=%E8%A5%BF%E6%B9%96&city=%E6%9D%AD%E5%B7%9E&offset=5&extensions=all');
check('amap proxy', poi.status === '1' && poi.pois?.length > 0, `count=${poi.count}`);

// 4. 天气
const wx = await j('GET', '/api/weather?lat=30.25&lon=120.15');
check('weather', Array.isArray(wx.daily?.time) && wx.daily.time.length >= 7);

// 5. AI 行程生成（核心）
console.log('...planner generating (3天 杭州 pureTransit)...');
let t0 = Date.now();
const plan = await j('POST', '/api/planner/generate', {
  city: '杭州',
  days: 3,
  startDate: '2026-10-01',
  pace: 'normal',
  interests: ['nature', 'culture', 'museum'],
  tripMode: 'pureTransit',
  description: '带爸妈和孩子的亲子游，想吃本地美食',
  fromCity: '上海',
  mustVisit: ['西湖'],
});
console.log(`planner took ${((Date.now() - t0) / 1000).toFixed(1)}s`);
const daysOk = Array.isArray(plan.trip?.days) && plan.trip.days.length === 3;
check('planner days', daysOk);
const totalLocs = (plan.trip?.days || []).reduce((s, d) => s + d.locations.length, 0);
check('planner locations', totalLocs >= 4, `total=${totalLocs} source=${plan.stats?.source}`);
const day1 = plan.trip?.days?.[0]?.locations?.[0];
check('planner first place has time', Boolean(day1?.arrivalTime), day1 ? `${day1.name} @${day1.arrivalTime}-${day1.leaveTime}` : '');
check('planner mustVisit honored', JSON.stringify(plan.trip).includes('西湖'));
check('planner warnings is array', Array.isArray(plan.warnings));
check('planner tripMode echoed', plan.trip?.tripMode === 'pureTransit', `mode=${plan.trip?.tripMode}`);
check('planner description hints', (plan.stats?.hints?.length ?? 0) >= 2 && plan.trip?.days?.length === 3, `hints=${(plan.stats?.hints || []).join(';')}`);
const allTypes = (plan.trip?.days || []).flatMap((d) => d.locations.map((l) => l.type));
check('planner 六类归类生效', allTypes.includes('restaurant') && allTypes.every((t) => ['attraction','restaurant','hotel','shopping','transport','other'].includes(t)), `types=${[...new Set(allTypes)].join(',')}`);
console.log(JSON.stringify(plan.trip.days.map((d) => ({
  day: d.dayNumber,
  stops: d.locations.map((l) => `${l.name}(${l.arrivalTime}→${l.leaveTime}${l.transportMinutes ? ' 行' + l.transportMinutes + '分' : ''})`),
})), null, 1).slice(0, 2400));
if (plan.warnings.length) console.log('warnings:', plan.warnings.join(' / '));

// 6. 自驾模式（验证 drive 路线 + tripMode 传递）
console.log('...planner generating (2天 杭州 pureDrive)...');
t0 = Date.now();
const drivePlan = await j('POST', '/api/planner/generate', {
  city: '杭州',
  days: 2,
  startDate: '2026-10-01',
  pace: 'normal',
  interests: ['nature'],
  tripMode: 'pureDrive',
});
console.log(`drive planner took ${((Date.now() - t0) / 1000).toFixed(1)}s`);
check('drive tripMode', drivePlan.trip?.tripMode === 'pureDrive');
const driveLocs = (drivePlan.trip?.days || []).flatMap((d) => d.locations);
check('drive locations exist', driveLocs.length >= 3, `total=${driveLocs.length}`);
check('drive 无枢纽点(纯自驾规则)', !driveLocs.some((l) => l.type === 'transport'));

console.log(failed ? `\n${failed} test(s) FAILED` : '\nALL TESTS PASSED');
process.exit(failed ? 1 : 0);
