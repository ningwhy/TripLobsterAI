// 多城走廊管线 · 纯逻辑单测（不依赖高德 Key / 网络）
// 覆盖：S3 城市排序、S3.5 天数分配、S6 编辑重算（时刻表传播 + 打烊提示）
// 运行：node test/multicity.mjs
import { orderCities, allocateCityDays, recalcTrip, legStopCount } from '../src/multiCity.js';

let failed = 0;
function check(name, cond, extra = '') {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra ? ' | ' + extra : ''}`);
  if (!cond) failed++;
}

// ---------- 1. S3 城市排序（北京环线：天津/潍坊/威海/烟台，对标真实自驾样本） ----------
const origin = { name: '北京', lng: 116.407, lat: 39.904 };
const cities = [
  { name: '威海', lng: 122.116, lat: 37.509 },
  { name: '烟台', lng: 121.39, lat: 37.536 },
  { name: '天津', lng: 117.201, lat: 39.085 },
  { name: '潍坊', lng: 119.161, lat: 36.706 },
];
const { order, legs } = orderCities(cities, { origin, roundTrip: true });
check('S3 全部城市保留', order.length === 4, order.map((c) => c.name).join('→'));
check('S3 首站是距出发地最近的城市', order[0].name === '天津', `首站=${order[0].name}`);
check('S3 环线含返程腿', legs.length === 5 && legs[legs.length - 1].isReturn === true, `legs=${legs.length}`);
check('S3 返程腿回到出发地', legs[legs.length - 1].to.name === '北京');
check('S3 邻接腿不交叉（天津→潍坊→威海/烟台）', order[1].name === '潍坊', `第2站=${order[1].name}`);
// 开放路径（不环线）
const open = orderCities(cities, { origin, roundTrip: false });
check('S3 开放路径无返程腿', open.legs.length === 4 && !open.legs.some((l) => l.isReturn));
// 无 origin：纯开放排序不崩溃
const noOrigin = orderCities(cities, { origin: null, roundTrip: false });
check('S3 无出发地也能排', noOrigin.order.length === 4);

// ---------- 2. S3.5 天数分配（对标 7 天北京-威海样本） ----------
// 7天：北京→天津1.5h、天津→潍坊4.5h、潍坊→威海2.5h、威海→烟台1h、烟台→东营3h、东营→北京6.5h
const legHours = [1.5, 4.5, 2.5, 1.0, 3.0, 6.5];
const alloc = allocateCityDays(7, 6, legHours, null);
check('S3.5 天卡总数=请求天数（腿被天卡吸收）', alloc.days.reduce((a, b) => a + b, 0) === 7,
  `days=[${alloc.days.join(',')}] legSum=${alloc.legSum}`);
check('S3.5 每城至少1天', alloc.days.every((d) => d >= 1));
// 权重分配：威海 stayDays=3 应比天津(1)分得多
const alloc2 = allocateCityDays(7, 3, [1.5, 4.5, 2.5, 6.5], [1, 3, 1]);
check('S3.5 权重生效（高权重城 ≥ 低权重城）', alloc2.days[1] >= alloc2.days[0] && alloc2.days[1] >= alloc2.days[2],
  `days=[${alloc2.days.join(',')}]`);
// 城市多于天数：每城保底1天（天卡超发，由 planCorridor 出警告）
const tight = allocateCityDays(2, 3, [1, 1, 1, 1]);
check('S3.5 极紧预算每城保底1天', tight.days.every((d) => d >= 1), `days=[${tight.days.join(',')}]`);

// ---------- 3. S6 编辑重算 ----------
const mockTrip = {
  trip: {
    tripMode: 'pureDrive',
    days: [
      {
        date: '2026-10-02', dayNumber: 1,
        locations: [
          { name: 'A景区', latitude: 37.51, longitude: 122.11, city: '威海', type: 'attraction', stayMinutes: 120, arrivalTime: '09:00', leaveTime: '11:00' },
          { name: 'B餐厅', latitude: 37.53, longitude: 122.15, city: '威海', type: 'restaurant', stayMinutes: 60, arrivalTime: '00:00', leaveTime: '00:00' },
          { name: 'C景点', latitude: 37.30, longitude: 122.40, city: '威海', type: 'attraction', stayMinutes: 90, closeTime: '12:00', arrivalTime: '00:00', leaveTime: '00:00' },
        ],
      },
    ],
  },
};
const fixedTravel = async () => ({ minutes: 40, km: 30, mode: 'drive' });
const recalc = await recalcTrip(mockTrip, { travelFn: fixedTravel });
const locs = recalc.trip.days[0].locations;
check('S6 首站保留用户到达时间', locs[0].arrivalTime === '09:00' && locs[0].leaveTime === '11:00', `${locs[0].arrivalTime}-${locs[0].leaveTime}`);
check('S6 次站=上站离开+交通', locs[1].arrivalTime === '11:40' && locs[1].leaveTime === '12:40', `${locs[1].arrivalTime}-${locs[1].leaveTime}`);
check('S6 交通字段已回填', locs[1].transportMinutes === 40 && locs[1].transport?.scope === 'intraCity', JSON.stringify(locs[1].transport || {}));
check('S6 三站时间链传播', locs[2].arrivalTime === '13:20' && locs[2].leaveTime === '14:50', `${locs[2].arrivalTime}-${locs[2].leaveTime}`);
check('S6 打烊冲突只提示不擅改', recalc.warnings.some((w) => w.includes('C景点') && w.includes('打烊')), recalc.warnings.join(' | '));
check('S6 不删用户数据', locs.length === 3);
// 跨城枢纽块不被重算打乱
const hubTrip = {
  trip: {
    tripMode: 'pureTransit',
    days: [{ date: '2026-10-01', dayNumber: 1, locations: [
      { name: '北京南站', type: 'transport', _intercity: { kind: 'dep' }, arrivalTime: '08:00', leaveTime: '09:00' },
      { name: '潍坊站', type: 'transport', _intercity: { kind: 'arr' }, arrivalTime: '12:00', leaveTime: '12:45' },
      { name: '十笏园', latitude: 36.717, longitude: 119.105, city: '潍坊', type: 'attraction', stayMinutes: 90, arrivalTime: '00:00', leaveTime: '00:00' },
    ] }],
  },
};
const hubRecalc = await recalcTrip(hubTrip, { travelFn: fixedTravel });
const hubLocs = hubRecalc.trip.days[0].locations;
check('S6 跨城枢纽块保持原时间', hubLocs[0].arrivalTime === '08:00' && hubLocs[1].arrivalTime === '12:00');
check('S6 枢纽后首站接续到达枢纽', hubLocs[2].arrivalTime === '13:25', hubLocs[2].arrivalTime);

// ---------- 4. P1-11/16 走廊停靠节奏（纯函数） ----------
check('P1 EV 800km→3次充电(每250km)', legStopCount(800, true) === 3, `n=${legStopCount(800, true)}`);
check('P1 油车 800km→4次休息(封顶)', legStopCount(800, false) === 4, `n=${legStopCount(800, false)}`);
check('P1 140km 内不停', legStopCount(140, false) === 0 && legStopCount(140, true) === 0);
check('P1 EV 300km→1次', legStopCount(300, true) === 1);
check('P1 油车 300km→2次', legStopCount(300, false) === 2);

// ---------- 5. P1-13 recalc scope=trip 跨天衔接（次晨从酒店9:00出发） ----------
// 注意：recalcTrip 会原地修改 trip，每个用例用工厂函数拿全新数据
const mkTrip2 = () => ({
  scope: 'trip',
  trip: {
    tripMode: 'pureDrive',
    days: [
      { date: '2026-10-02', dayNumber: 1, locations: [
        { name: 'A景区', latitude: 37.5, longitude: 122.5, city: '威海', type: 'attraction', stayMinutes: 120, arrivalTime: '09:00' },
        { name: '威海酒店', latitude: 37.52, longitude: 122.3, city: '威海', type: 'hotel', stayMinutes: 600, arrivalTime: '00:00' },
      ] },
      { date: '2026-10-03', dayNumber: 2, locations: [
        { name: 'B景区', latitude: 37.4, longitude: 122.6, city: '威海', type: 'attraction', stayMinutes: 90, arrivalTime: '00:00' },
      ] },
    ],
  },
});
const t2 = await recalcTrip(mkTrip2(), { travelFn: fixedTravel });
const day2First = t2.trip.days[1].locations[0];
check('S6/trip 次晨按9:00从酒店出发衔接', day2First.transportMinutes === 40 && day2First.arrivalTime === '09:40' && day2First.leaveTime === '11:10',
  `${day2First.arrivalTime}-${day2First.leaveTime} 行${day2First.transportMinutes}分`);
check('S6/trip 首天不受跨天逻辑影响', t2.trip.days[0].locations[0].arrivalTime === '09:00');
check('S6/trip 提示已注明衔接规则', t2.warnings.some((w) => w.includes('scope=trip')));

// scope=day（默认）不做跨天衔接，首站占位时间 '00:00' 视为未设 → 默认 9:00
const dayScopeInput = mkTrip2(); delete dayScopeInput.scope;
const t3 = await recalcTrip(dayScopeInput, { travelFn: fixedTravel });
check('S6/day 默认不跨天衔接且占位时间归位', t3.trip.days[1].locations[0].arrivalTime === '09:00', t3.trip.days[1].locations[0].arrivalTime);

console.log(failed ? `\n${failed} test(s) FAILED` : '\nALL TESTS PASSED');
process.exit(failed ? 1 : 0);
