// 多城走廊规划管线（P0-2 升级：点状单城 → 线状走廊）
//
// 用户管线规格（2026-09-24）：
//   S1 AI 研究游记攻略 → S2 按需求+时长选停留城市 → S3 按城市坐标排先后顺序 →
//   S4 城内找高价值吃玩住娱 POI → S5 高德按用户出行方式串联 →
//   S6 用户增删改查/排序后自动重算 → S7 实时拉取 POI 价格
//
// 铁律不变：AI 只做编排，所有地点/路线/时间来自高德真实数据；建议不决策，可回退。
import { amapCall } from './amapProxy.js';
import { isLlmEnabled, llmChat } from './llm.js';
import { makeCache, makeRateLimit } from './util.js';
import {
  gatherCandidates, geocodeCity, haversineKm, clusterByDay, buildDay,
  findHotels, segmentMinutes, findRentalHub, toLocation, fmt, toMin, addDays,
  extractHints, queryPois, normalizePoi,
  INTERESTS, PER_DAY_CAP, START_CLOCK, STAY_FACTOR, VEHICLE_CONF,
} from './planner.js';

// ---------- M2 止血（防 DoS / 防高德配额被放大） ----------
// 入参上限：超限在进入高德前直接 400，错误信息回显实际数量，方便客户端定位
const MAX_CITIES = 8;              // 单次 corridor 最多城市数
const MAX_TOTAL_LOCATIONS = 50;    // 单次 recalc 全行程最多地点数
// 限流：corridor / recalc 各自独立 5 次/分/IP（复用 util.js 的 makeRateLimit，零新依赖）
const MULTICITY_RATE = { windowMs: 60_000, max: 5 };

// ---------- S3 城市排序（纯函数，可单测） ----------
// 最近邻 + 2-opt。优化用直线距离（便宜），最终段间耗时再用高德真实路网算。
export function orderCities(cities, { origin = null, roundTrip = true, distFn = haversineKm } = {}) {
  const pts = cities.filter((c) => Number.isFinite(c.lat) && Number.isFinite(c.lng));
  if (!pts.length) return { order: [], legs: [] };
  const anchor = origin && Number.isFinite(origin.lat) ? origin : null;
  const pool = pts.slice();
  const order = [];
  let cur = anchor || pool.shift();
  if (!anchor) order.push(cur);
  while (pool.length) {
    let bi = 0, bd = Infinity;
    pool.forEach((p, i) => {
      const d = distFn(cur, p);
      if (d < bd) { bd = d; bi = i; }
    });
    cur = pool.splice(bi, 1)[0];
    order.push(cur);
  }
  // 2-opt：开放路径固定首站；环线把"回到出发点"计入成本
  const cost = (arr) => {
    let s = 0;
    const seq = anchor ? [anchor, ...arr] : arr;
    for (let i = 0; i < seq.length - 1; i++) s += distFn(seq[i], seq[i + 1]);
    if (anchor && roundTrip) s += distFn(seq[seq.length - 1], anchor);
    return s;
  };
  let improved = true, guard = 0;
  while (improved && guard++ < 30) {
    improved = false;
    for (let i = 0; i < order.length - 1; i++) {
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
  // 生成腿：origin(或首城) → … → 尾城 (→ origin)
  const legs = [];
  const seq = anchor ? [anchor, ...order] : order;
  for (let i = 0; i < seq.length - 1; i++) {
    legs.push({ from: seq[i], to: seq[i + 1], km: distFn(seq[i], seq[i + 1]) });
  }
  if (anchor && roundTrip && order.length) {
    legs.push({ from: order[order.length - 1], to: anchor, km: distFn(order[order.length - 1], anchor), isReturn: true });
  }
  return { order, legs };
}

// ---------- 天数分配（纯函数，可单测） ----------
// 赶路腿不单独占天卡：≤45min 可忽略，≤6h 记 0.5（到达后还能玩半天），>6h 记 1（整日赶路）
// 全部腿都被吸收进当天的天卡（由 pts 收紧 + startClock 后移实现），
// 因此预算 = 总天数按权重分配到各城（每城保底 1 天）；legSum 仅用于"赶路过重"提示。
export function allocateCityDays(totalDays, cityCount, legHours = [], weights = null) {
  const legCost = (legHours || []).map((h) => (h <= 0.75 ? 0 : h <= 6 ? 0.5 : 1));
  const legSum = legCost.reduce((a, b) => a + b, 0);
  const budget = Math.max(cityCount, totalDays);
  const wSum0 = (weights || []).reduce((a, b) => a + (b > 0 ? b : 0), 0);
  const w = wSum0 > 0 ? weights.map((x) => (x > 0 ? x : 0)) : Array(cityCount).fill(1);
  const wSum = w.reduce((a, b) => a + b, 0) || cityCount;
  const raw = w.map((x) => (budget * x) / wSum);
  const days = raw.map((x) => Math.max(1, Math.floor(x + 1e-9)));
  let used = days.reduce((a, b) => a + b, 0);
  // 小数部分大的城市优先补齐
  const fracOrder = raw.map((x, i) => [x - Math.floor(x + 1e-9), i]).sort((a, b) => b[0] - a[0]);
  let gi = 0;
  while (used < budget && gi < budget * 2 + cityCount) { days[fracOrder[gi % cityCount][1]] += 1; used++; gi++; }
  // 超预算时从天数最多的城市回收（每城保底 1 天）
  let ri = 0;
  while (used > budget && ri < budget * 2 + cityCount) {
    let mi = 0;
    days.forEach((d, i) => { if (d > days[mi]) mi = i; });
    if (days[mi] <= 1) break;
    days[mi] -= 1; used--; ri++;
  }
  return { days, legCost, legSum, budget };
}

// ---------- S1/S2 城市推荐（LLM，失败必须显式报错而不是编数据） ----------
async function llmSuggestCities({ origin, days, tripMode, interestLabels, desc, party = null, budget = null }) {
  const modeText = { pureDrive: '自驾（每日驾驶建议不超过6小时）', pureTransit: '公共交通', transitPlusRental: '公共交通+落地租车' }[tripMode] || tripMode;
  try {
    const content = await llmChat(
      [
        { role: 'system', content: '你是资深旅行规划师。根据出发地、总天数、出行方式、同行人员和偏好，推荐真实存在、适合该行程的中途停留或深度游玩城市（不要推荐出发地本身）。同行有老人小孩时优先亲子友好、车程友好的城市，避免高海拔/高强度目的地。输出JSON：{"cities":[{"name":"城市名","stayDays":2,"reason":"一句话理由"}]}。城市数2-6个，各城stayDays之和加上路途时间约等于总天数。' },
        { role: 'user', content: JSON.stringify({ origin, days, mode: modeText, interests: interestLabels, 出行人员: party, 预算档: budget, 用户描述: desc || '无' }) },
      ],
      { jsonMode: true, timeoutMs: 45000 }
    );
    if (!content) return null;
    const parsed = JSON.parse(content);
    if (!Array.isArray(parsed.cities)) return null;
    const out = parsed.cities
      .filter((c) => c && typeof c.name === 'string' && c.name.trim())
      .slice(0, 6)
      .map((c) => ({ name: c.name.trim().replace(/(市|地区|自治州)$/, ''), stayDays: Math.max(1, parseInt(c.stayDays, 10) || 1), reason: String(c.reason || '') }));
    return out.length ? out : null;
  } catch {
    return null;
  }
}

// ---------- S5 段间真实耗时 ----------
async function legTime(from, to, { mode = 'drive', vehicle: veh = 'highSpeedTrain', schedule = null } = {}) {
  const km = haversineKm(from, to);
  if (mode === 'transit') {
    if (schedule) return { minutes: toMin(schedule.arr) - toMin(schedule.dep), km, scheduled: true }; // 真实班次时长
    const conf = VEHICLE_CONF[veh] || VEHICLE_CONF.highSpeedTrain;
    return { minutes: Math.max(30, Math.round((km / conf.speedKmh) * 60 + conf.prep)), km, estimated: true };
  }
  try {
    const data = await amapCall('/v3/direction/driving', {
      origin: `${from.lng},${from.lat}`,
      destination: `${to.lng},${to.lat}`,
      strategy: '0',
      extensions: 'base',
    });
    const p = data?.route?.paths?.[0];
    const t = parseInt(p?.duration, 10);
    const d = parseFloat(p?.distance);
    return { minutes: Math.max(20, Math.round(t / 60)), km: Number.isFinite(d) ? d / 1000 : km };
  } catch { /* 估算兜底 */ }
  return { minutes: Math.max(20, Math.round((km / 80) * 60 + 15)), km };
}

// 公共交通跨城：枢纽对（无真实班次，时长估算，诚实提示）
async function findHub(cityName, vehicle) {
  const conf = VEHICLE_CONF[vehicle] || VEHICLE_CONF.highSpeedTrain;
  const pois = await queryPois(cityName, { keywords: conf.hubKw }, 1);
  const poi = pois.map(normalizePoi).find(Boolean);
  return poi || { name: `${cityName}${conf.hubKw}`, city: cityName, typecode: conf.fallbackCode, lng: null, lat: null, address: cityName };
}

// ---------- 走廊长腿中途停靠节奏（P1-11/16：家庭 2-2.5h 一停；EV 按补能半径） ----------
export function legStopCount(km, ev = false) {
  const interval = ev ? 250 : 150;
  if (km < interval) return 0;
  return Math.min(4, Math.floor(km / interval)); // 单腿封顶 4 个，防极端
}

async function findLegPoi(center, keywords, radius) {
  try {
    const data = await amapCall('/v3/place/around', {
      location: `${center.lng.toFixed(5)},${center.lat.toFixed(5)}`,
      keywords,
      radius: String(radius),
      offset: '5',
      page: '1',
      extensions: 'base',
      sortrule: 'distance',
    });
    const pois = (data?.pois || []).map(normalizePoi).filter(Boolean);
    return pois[0] || null;
  } catch {
    return null;
  }
}

// 沿腿均匀取停靠点：油车服务区休息（baseStay 20min）；EV 充电站补能（typecode=evcharge → 40min）
async function planLegStops(from, to, { ev = false, km = null } = {}) {
  const totalKm = km ?? haversineKm(from, to);
  const n = legStopCount(totalKm, ev);
  const stops = [];
  for (let i = 1; i <= n; i++) {
    const f = Math.min(0.92, (i * (ev ? 250 : 150)) / totalKm);
    const mid = { lng: from.lng + (to.lng - from.lng) * f, lat: from.lat + (to.lat - from.lat) * f };
    const poi = await findLegPoi(mid, ev ? '充电站' : '服务区', ev ? 10000 : 30000);
    if (poi && !stops.some((s) => s.id === poi.id)) {
      if (ev) poi.typecode = 'evcharge'; // planner.baseStay 识别为 40min 补能停留
      stops.push(poi);
    }
  }
  return stops;
}

// ---------- 班次锚（数据模型第6类：交通枢纽跟着班次走，班次时间固定，相邻行程段只能前后推） ----------
// 用户在 12306/航司查好班次后经 schedules 传入 → 真实固定时刻；未提供的腿按典型时长估算占位（诚实提示）
export function parseSchedules(raw) {
  return (Array.isArray(raw) ? raw : [])
    .map((s) => ({
      from: String(s.from || '').trim().replace(/(市|地区|自治州)$/, ''),
      to: String(s.to || '').trim().replace(/(市|地区|自治州)$/, ''),
      vehicle: ['flight', 'highSpeedTrain', 'train', 'bus', 'ship'].includes(s.vehicle) ? s.vehicle : 'highSpeedTrain',
      no: String(s.no || '').trim(),
      depHubName: String(s.depHub || s.depHubName || '').trim() || null,
      arrHubName: String(s.arrHub || s.arrHubName || '').trim() || null,
      dep: /^\d{1,2}:\d{2}$/.test(String(s.dep || '')) ? String(s.dep).padStart(5, '0') : null,
      arr: /^\d{1,2}:\d{2}$/.test(String(s.arr || '')) ? String(s.arr).padStart(5, '0') : null,
      price: Number.isFinite(parseFloat(s.price)) ? parseFloat(s.price) : null,
    }))
    // 合法钟表时刻（00:00–23:59）且 到达晚于出发，才可作为固定班次锚
    .filter((s) => {
      if (!s.from || !s.to || !s.dep || !s.arr || toMin(s.arr) <= toMin(s.dep)) return false;
      const [dh, dm] = s.dep.split(':').map(Number);
      const [ah, am] = s.arr.split(':').map(Number);
      return dh <= 23 && dm <= 59 && ah <= 23 && am <= 59;
    });
}

export function matchSchedule(schedules, fromName, toName) {
  const f = String(fromName || '').replace(/(市|地区|自治州)$/, '');
  const t = String(toName || '').replace(/(市|地区|自治州)$/, '');
  return (schedules || []).find((s) => s.from === f && s.to === t) || null;
}

// 混合模式：落地租车/包车的城市下标（默认落地第一站）
export function resolveRentalAtIdx(orderNames, wanted) {
  const w = String(wanted || '').trim().replace(/(市|地区|自治州)$/, '');
  if (w) {
    const idx = orderNames.findIndex((n) => n === w);
    if (idx >= 0) return idx;
  }
  return 0;
}

// 班次锚时间：有真实班次用真实时刻（固定锚）；否则按出发钟点+prep+典型时长估算占位
export function buildAnchorTimes({ schedule = null, prep, startClock, legMinutes }) {
  if (schedule) {
    return { depMin: toMin(schedule.dep), arrMin: toMin(schedule.arr), fixed: true };
  }
  return { depMin: startClock + prep, arrMin: startClock + prep + legMinutes, fixed: false };
}

// 早场窗口：出发前能否塞一个景点（班次晚点才有空间；锚固定 → 相邻段只能往前推=压缩游玩时间）
export function morningWindow({ depMin, prep, t2hubMin, startClock }) {
  const hubArr = depMin - prep; // 必须此刻到达出发枢纽（固定锚）
  const endMin = hubArr - t2hubMin; // 早场景点最晚离开时刻
  return { hubArr, endMin, ok: endMin >= startClock + 90 }; // 至少 1.5h 游玩窗口才值得排
}

// ---------- 主管线：多城走廊规划 ----------
export async function planCorridor(input) {
  const originName = String(input.origin || input.fromCity || '').trim();
  if (!originName) { const e = new Error('请填写出发地 origin（如：北京）'); e.status = 400; e.expose = true; throw e; }
  // M2：城市数上限（在任何 await / 高德调用之前拦截，超限不烧配额）
  const rawCities = Array.isArray(input.cities) ? input.cities : [];
  if (rawCities.length > MAX_CITIES) {
    const e = new Error(`城市数量过多：收到 ${rawCities.length} 个，单次最多支持 ${MAX_CITIES} 个`);
    e.status = 400; e.expose = true; throw e;
  }
  const days = Math.min(15, Math.max(2, parseInt(input.days, 10) || 5));
  const tripMode = ['pureDrive', 'pureTransit', 'transitPlusRental'].includes(input.tripMode) ? input.tripMode : 'pureDrive';
  const roundTrip = input.roundTrip !== false;
  const vehicle = ['flight', 'highSpeedTrain', 'train', 'bus', 'ship'].includes(input.intercityVehicle) ? input.intercityVehicle : 'highSpeedTrain';
  // M1（TDZ 修复）：warnings 必须先声明再使用。
  // 旧代码把 `const warnings = []` 写在 schedules 之后，而下一行就 push → 只要传了 schedules，
  // 请求必抛 ReferenceError: Cannot access 'warnings' before initialization → 100% 500。
  const warnings = [];
  const suggestions = []; // 被收紧/裁剪的 POI（可手动加回 —— 铁律：默认可撤销）
  // 班次锚：用户传入的真实班次（时间固定）；混合模式落地方式：租车/包车
  const schedules = parseSchedules(input.schedules);
  if (schedules.length) warnings.push(`已加载 ${schedules.length} 个真实班次（时间固定，前后行程按班次锚定，只能前后推）`);
  const groundMode = input.groundMode === 'charter' ? 'charter' : 'rental';

  const hints = extractHints(String(input.description || '').trim());
  let pace = ['relaxed', 'normal', 'packed'].includes(input.pace) ? input.pace : 'normal';
  let interestKeys = (Array.isArray(input.interests) && input.interests.filter((k) => INTERESTS[k]).length
    ? input.interests.filter((k) => INTERESTS[k])
    : ['nature', 'culture']);
  for (const k of hints.interests) if (!interestKeys.includes(k)) interestKeys.push(k);
  if (hints.pace && hints.pace !== pace) { warnings.push(`根据描述，节奏已调整为「${{ relaxed: '轻松', normal: '标准', packed: '特种兵' }[hints.pace]}」`); pace = hints.pace; }
  for (const n of hints.notes) warnings.push(n);

  const startDate = /^\d{4}-\d{2}-\d{2}$/.test(input.startDate || '') ? input.startDate : addDays(new Date().toISOString().slice(0, 10), 14);
  const party = {
    adults: Math.max(1, parseInt(input.adults, 10) || 2),
    children: Math.max(0, parseInt(input.children, 10) || 0),
    rooms: Math.max(1, parseInt(input.rooms, 10) || 1),
    roomType: ['twin', 'family', 'king'].includes(input.roomType) ? input.roomType : null,
  };
  const budgetKey = ['economy', 'comfort', 'luxury'].includes(input.budget) ? input.budget : 'comfort';
  const driveMode = tripMode !== 'pureTransit';
  // P1-11：EV 模式（显式 ev:true，或从描述识别电车）
  const ev = input.ev === true || /电动车|纯电|特斯拉|model\s*[3xy]/i.test(String(input.description || ''));
  if (ev && driveMode) warnings.push('已按 EV 模式规划：约每 250km 插入一次充电停留（40分钟）');
  const cap = PER_DAY_CAP[pace];

  // 出发地定位
  const originGeo = await geocodeCity(originName);
  if (!originGeo) { const e = new Error(`无法定位出发地「${originName}」`); e.status = 404; e.expose = true; throw e; }

  // S1/S2：城市集合 —— 用户显式给定，或 LLM 按攻略式推荐（失败报错，不编数据）
  let cityInputs = (Array.isArray(input.cities) ? input.cities : [])
    .map((c) => (typeof c === 'string' ? { name: c } : c))
    .filter((c) => c && typeof c.name === 'string' && c.name.trim())
    .map((c) => ({ name: c.name.trim().replace(/(市|地区|自治州)$/, ''), stayDays: Math.max(0, parseInt(c.stayDays, 10) || 0), reason: String(c.reason || ''), stopType: c.stopType === 'waypoint' ? 'waypoint' : 'overnight', vehicle: ['flight', 'highSpeedTrain', 'train', 'bus', 'ship'].includes(c.vehicle) ? c.vehicle : null }));
  let source = 'rule';
  if (!cityInputs.length) {
    if (!isLlmEnabled()) {
      const e = new Error('请提供想去的城市列表 cities（如 ["天津","潍坊","威海"]），或在服务端配置 LLM 后由 AI 按攻略自动推荐');
      e.status = 400; e.expose = true; throw e;
    }
    const suggested = await llmSuggestCities({ origin: originName, days, tripMode, interestLabels: interestKeys.map((k) => INTERESTS[k].label), desc: String(input.description || '').trim(), party, budget: budgetKey });
    if (!suggested) {
      const e = new Error('AI 城市推荐失败（LLM 无响应或输出异常），请显式传入 cities 重试');
      e.status = 502; e.expose = true; throw e;
    }
    cityInputs = suggested;
    source = 'llm+rule';
    warnings.push(`AI 根据你的需求推荐停留：${suggested.map((c) => `${c.name}(${c.stayDays}天)`).join('、')}`);
  }

  // 城市定位校验（剔除无效/与出发地同名）
  const cities = [];
  for (const c of cityInputs) {
    if (c.name.replace(/(市|地区|自治州)$/, '') === originName.replace(/(市|地区|自治州)$/, '')) {
      warnings.push(`「${c.name}」即出发地，已跳过`);
      continue;
    }
    const g = await geocodeCity(c.name);
    if (!g) { warnings.push(`无法定位城市「${c.name}」，已跳过`); continue; }
    cities.push({ ...c, lat: g.lat, lng: g.lng });
  }
  if (!cities.length) { const e = new Error('所给城市均无法定位，请检查城市名'); e.status = 404; e.expose = true; throw e; }

  // S3：城市排序 + 段间真实耗时
  const { order, legs } = orderCities(cities, { origin: originGeo, roundTrip });
  if (order.map((c) => c.name).join() !== cities.map((c) => c.name).join()) {
    warnings.push(`已按地理位置优化城市顺序：${order.map((c) => c.name).join(' → ')}${roundTrip ? ' → ' + originName : ''}`);
  }
  // 混合模式（transitPlusRental）：落地租车/包车的城市（默认落地第一站），其后的城际腿改为自驾
  const isRentalTrip = tripMode === 'transitPlusRental';
  const rentalAtIdx = isRentalTrip ? resolveRentalAtIdx(order.map((c) => c.name), input.rentalAt) : -1;
  if (isRentalTrip) {
    const vehLabel = { flight: '飞机', highSpeedTrain: '高铁/火车', train: '火车', bus: '大巴', ship: '轮船' }[vehicle] || vehicle;
    warnings.push(`混合模式：出发地→${order[rentalAtIdx].name} 乘${vehLabel}（含枢纽接驳），落地${order[rentalAtIdx].name}后${groundMode === 'charter' ? '包车' : '租车'}自驾游玩并前往后续城市`);
  }

  // 逐腿定型：纯公共交通全程；混合模式到取车城为止；用户给定班次的腿强制按公共交通
  for (let i = 0; i < legs.length; i++) {
    const leg = legs[i];
    leg.schedule = matchSchedule(schedules, leg.from.name || originName, leg.to.name || originName);
    leg.isTransit = tripMode === 'pureTransit' || (isRentalTrip && i <= rentalAtIdx) || Boolean(leg.schedule);
    if (leg.schedule && tripMode === 'pureDrive') warnings.push(`「${leg.from.name || originName}→${leg.to.name || originName}」提供了班次，已按公共交通段处理`);
    leg.vehicle = (leg.schedule && leg.schedule.vehicle) || (leg.isTransit && order[i] && order[i].vehicle) || vehicle;
    const t = await legTime(leg.from, leg.to, { mode: leg.isTransit ? 'transit' : 'drive', vehicle: leg.vehicle, schedule: leg.schedule });
    leg.minutes = t.minutes;
    leg.km = Math.round(t.km * 10) / 10;
    leg.estimated = Boolean(t.estimated);
  }
  const legToCity = order.map((c, i) => legs[i]); // legs[0]=origin→c0, legs[i]=c(i-1)→ci（环线最后一条是返程）
  const legHours = legs.map((l) => l.minutes / 60);

  // S3.5：天数分配
  const weights = order.map((c) => c.stayDays || 0);
  const { days: cityDays, legSum } = allocateCityDays(days, order.length, legHours, weights);
  // 过路城（waypoint）：不设酒店顺路游，强制 1 天，回收天数给权重最高的过夜城（P1-12）
  const wpIdx = [];
  let freedDays = 0;
  order.forEach((c, i) => {
    if (c.stopType === 'waypoint') {
      wpIdx.push(i);
      if (cityDays[i] > 1) { freedDays += cityDays[i] - 1; cityDays[i] = 1; }
    }
  });
  if (freedDays > 0) {
    let mi = -1, mv = -1;
    order.forEach((c, i) => { if (c.stopType !== 'waypoint' && cityDays[i] > mv) { mv = cityDays[i]; mi = i; } });
    if (mi >= 0) cityDays[mi] += freedDays;
    warnings.push(`过路城不设酒店：${wpIdx.map((i) => order[i].name).join('、')} 各安排 1 天顺路游，回收的 ${freedDays} 天已加给「${order[mi].name}」`);
  }
  const sumCityDays = cityDays.reduce((a, b) => a + b, 0);
  const totalLegH = legHours.reduce((a, b) => a + b, 0);
  if (totalLegH > days * 7) {
    warnings.push(`赶路过重：全程车程约${totalLegH.toFixed(1)}小时，平均每天${(totalLegH / days).toFixed(1)}小时，建议减少城市或增加天数`);
  } else if (sumCityDays > days) {
    warnings.push(`城市数（${order.length}）多于天数（${days}），部分城市只能安排路过式短停留`);
  }
  const returnLeg = roundTrip ? legs[legs.length - 1] : null;

  // 必去点：逐城解析，落在找到它的城市
  const mustPois = [];
  for (const kw of (Array.isArray(input.mustVisit) ? input.mustVisit.slice(0, 5) : [])) {
    const name = String(kw).trim();
    if (!name) continue;
    let placed = false;
    for (let ci = 0; ci < order.length && !placed; ci++) {
      const pois = await queryPois(order[ci].name, { keywords: name }, 1);
      const poi = pois.map(normalizePoi).find(Boolean);
      if (poi) { mustPois.push({ cityIdx: ci, poi }); placed = true; }
    }
    if (!placed) warnings.push(`未找到必去点「${name}」，已忽略`);
  }

  // S4+S5：逐城 → 逐天构建
  const tripDays = [];
  let prevPoint = { ...originGeo, name: originName, city: originName }; // 上一夜落点（酒店/末站/出发地）
  let prevHotel = null; // 连住支持：记住上一晚酒店
  let dayIdx = 0;

  for (let ci = 0; ci < order.length; ci++) {
    const city = order[ci];
    const nDays = cityDays[ci];
    const need = nDays * cap;
    let candidates = await gatherCandidates(city.name, interestKeys, need);
    for (const m of mustPois.filter((m) => m.cityIdx === ci)) {
      if (!candidates.some((c) => c.id === m.poi.id)) candidates.unshift(m.poi);
    }
    if (!candidates.length) warnings.push(`「${city.name}」未搜到候选景点，该城只安排食宿与赶路`);
    candidates.sort((a, b) => (b.rating || 0) - (a.rating || 0));
    const mustIds = new Set(mustPois.filter((m) => m.cityIdx === ci).map((m) => m.poi.id));
    // 必去点保证入选：先拼必去再补评分候选（否则低分/无评分的必去会被 slice 截掉 —— 用户显式需求 > 算法）
    const cityMusts = mustPois.filter((m) => m.cityIdx === ci).map((m) => m.poi);
    const selected = [...cityMusts, ...candidates.filter((c) => !mustIds.has(c.id))].slice(0, need);
    const groups = clusterByDay(selected, nDays, cap);

    const arriveLeg = legToCity[ci];
    // 收紧当天景点量：必去点永不裁剪，其余进 suggestions（可手动加回）
    const tightenDay = (arr, capN) => {
      const must = arr.filter((p) => p._must);
      const rest = arr.filter((p) => !p._must);
      const kept = [...must, ...rest].slice(0, Math.max(capN, must.length));
      for (const p of arr) {
        if (!kept.includes(p)) suggestions.push({ name: p.name, city: city.name, reason: `因赶路/返程时间收紧，未排入第${dayIdx + 1}天，可手动加回` });
      }
      return kept;
    };
    for (let d = 0; d < nDays; d++) {
      const isTripLastDay = ci === order.length - 1 && d === nDays - 1;
      let pts = groups[d].map((p) => ({ ...p, _must: mustIds.has(p.id) }));
      let startClock = null;
      let origin = prevPoint;

      // 赶路日收紧当天景点量 + 长驾驶日早出发（旅行实务：>4h 车程 8:00 出发）
      if (d === 0 && arriveLeg) {
        const h = arriveLeg.minutes / 60;
        if (h > 6) {
          pts = tightenDay(pts, 1);
          startClock = 480;
          warnings.push(`第${dayIdx + 1}天赶路 ${arriveLeg.km}km（约${h.toFixed(1)}小时），已按 8:00 早出发，当天只保留 1 个景点`);
        } else if (h > 4) {
          pts = tightenDay(pts, 2);
          startClock = 480;
          warnings.push(`第${dayIdx + 1}天赶路 ${arriveLeg.km}km（约${h.toFixed(1)}小时），已按 8:00 早出发`);
        } else if (h > 3) {
          pts = tightenDay(pts, 2);
        }
        if (arriveLeg.km > 600) {
          warnings.push(`单日 ${arriveLeg.km}km 超过家庭自驾安全线（约600km/天），强烈建议在中途城市加一晚过夜（可在 cities 中加入中点城市重新规划）`);
        }
      }

      // 返程日：给回家路上预留时间（反向收紧，避免最后一天排满+开夜路/误车）
      let returnTail = null; // 固定返程班次：当天尾部追加返程枢纽对（游玩被锚往前推）
      if (isTripLastDay && returnLeg) {
        if (returnLeg.schedule) {
          // 班次锚（固定）：当天游玩窗口 = 发车时刻 - 候车 - 去站时间
          const conf2 = VEHICLE_CONF[returnLeg.vehicle] || VEHICLE_CONF.highSpeedTrain;
          const sch2 = returnLeg.schedule;
          const depMin2 = toMin(sch2.dep);
          const arrMin2 = toMin(sch2.arr);
          const retDepHub = sch2.depHubName ? { name: sch2.depHubName, city: city.name, lng: null, lat: null, address: city.name } : await findHub(city.name, returnLeg.vehicle);
          const retArrHub = sch2.arrHubName ? { name: sch2.arrHubName, city: originName, lng: null, lat: null, address: originName } : await findHub(originName, returnLeg.vehicle);
          const playMin = depMin2 - conf2.prep - 40 - START_CLOCK[pace]; // 预留 40min 从末站去车站（尾段精算）
          const capN = Math.max(0, Math.min(2, Math.floor(playMin / 150))); // 每站约 2.5h
          if (capN === 0) {
            suggestions.push(...pts.map((p) => ({ name: p.name, city: city.name, reason: `返程班次 ${sch2.no || ''} ${sch2.dep} 固定，当天无游玩窗口，可改签或加天` })));
            pts = [];
            warnings.push(`返程班次 ${sch2.no || conf2.label} ${sch2.dep} 固定，最后一天全天赶路`);
          } else {
            pts = tightenDay(pts, capN);
            warnings.push(`返程班次 ${sch2.no || conf2.label} ${sch2.dep} 固定，最后一天只保留 ${capN} 个景点，须在 ${fmt(depMin2 - conf2.prep - 40)} 前结束游玩`);
          }
          returnTail = { conf: conf2, sch: sch2, depMin: depMin2, arrMin: arrMin2, retDepHub, retArrHub };
        } else {
          const rh = returnLeg.minutes / 60;
          if (rh > 7) {
            suggestions.push(...pts.map((p) => ({ name: p.name, city: city.name, reason: `返程需 ${rh.toFixed(1)} 小时建议全天赶路，未排入最后一天` })));
            pts = [];
            warnings.push(`最后一天全程返程（${returnLeg.km}km / ${rh.toFixed(1)}h），未安排景点；若想再玩半天，请增加总天数或压缩前面城市`);
          } else if (rh > 4) {
            pts = tightenDay(pts, 1);
            startClock = 480;
            warnings.push(`最后一天需预留返程 ${returnLeg.km}km / ${rh.toFixed(1)}h，只保留 1 个景点并 8:00 早出发`);
          }
        }
      }

      // 过路城：顺路停留不设酒店，按"到达+出发"总车程收紧到 1-2 站（P1-12）
      const isWaypoint = city.stopType === 'waypoint';
      const nextLeg = legs[ci + 1] && !legs[ci + 1].isReturn ? legs[ci + 1] : null;
      if (isWaypoint && d === 0) {
        const totalH = (arriveLeg ? arriveLeg.minutes / 60 : 0) + (nextLeg ? nextLeg.minutes / 60 : 0);
        pts = tightenDay(pts, totalH > 6 ? 1 : 2);
        warnings.push(`「${city.name}」为过路城：顺路游后继续前往${nextLeg ? nextLeg.to.name : '下一站'}，不安排住宿`);
      }

      // 走廊长腿中途停靠（仅自驾腿）：油车约每150km服务区休息，EV约每250km充电（P1-11/16，家庭自驾实务节奏）
      if (d === 0 && driveMode && arriveLeg && !arriveLeg.isTransit && pts.length) {
        const stops = await planLegStops(prevPoint, pts[0], { ev: ev && driveMode, km: arriveLeg.km });
        if (stops.length) {
          pts = [...stops, ...pts]; // 沿路线顺序铺在景点前，buildDay 逐段真实算路
          warnings.push(`第${dayIdx + 1}天已按${ev ? 'EV补能' : '家庭节奏'}插入 ${stops.length} 个中途停留点：${stops.map((s) => s.name).join('、')}`);
        }
      }

      // 跨城公共交通（pureTransit 全程 / 混合模式落地前）：枢纽对 + 班次锚
      // 班次时间固定 → 之前的行程段只能往前推（压缩/舍弃），之后的段从到达枢纽顺推
      let headLocs = []; // 枢纽对(+取车点)，插在当天头部
      let morningDay = null; // 早场（晚班次时出发前塞 1 个景点）
      let afternoonPts = pts;
      let afternoonStart = startClock;
      let afternoonOrigin = origin;
      if (d === 0 && arriveLeg && arriveLeg.isTransit) {
        const conf = VEHICLE_CONF[arriveLeg.vehicle] || VEHICLE_CONF.highSpeedTrain;
        const fromName = arriveLeg.from.name || originName;
        const sch = arriveLeg.schedule;
        const depHub = sch && sch.depHubName ? { name: sch.depHubName, city: fromName, lng: null, lat: null, address: fromName } : await findHub(fromName, arriveLeg.vehicle);
        const arrHub = sch && sch.arrHubName ? { name: sch.arrHubName, city: city.name, lng: null, lat: null, address: city.name } : await findHub(city.name, arriveLeg.vehicle);
        const anchor = buildAnchorTimes({ schedule: sch, prep: conf.prep, startClock: START_CLOCK[pace], legMinutes: arriveLeg.minutes });

        // 上一夜落点（酒店/家）→ 出发枢纽（打车/公交，真实算路）
        const depHubGeo = Number.isFinite(depHub.lng) ? depHub : null;
        const t2hub = depHubGeo
          ? await segmentMinutes({ lng: prevPoint.lng, lat: prevPoint.lat, city: fromName }, depHubGeo, fromName, 'transit')
          : null;

        // 早场窗口：仅固定班次且发车晚时才有空间；放不下只能舍弃（锚固定，只能往前推）
        const mw = morningWindow({ depMin: anchor.depMin, prep: conf.prep, t2hubMin: t2hub ? t2hub.minutes : 30, startClock: START_CLOCK[pace] });
        if (mw.ok && pts.length) {
          const mi = pts.findIndex((p) => p._must);
          const morningPoi = pts.splice(mi >= 0 ? mi : 0, 1)[0];
          morningDay = await buildDay(dayIdx, addDays(startDate, dayIdx), [morningPoi], { pace, city: city.name, warnings, tripMode, startClock: START_CLOCK[pace], origin: prevPoint });
          const mLast = morningDay.locations[morningDay.locations.length - 1];
          const t2hub2 = mLast && Number.isFinite(mLast.longitude) && depHubGeo
            ? await segmentMinutes({ lng: mLast.longitude, lat: mLast.latitude, city: fromName }, depHubGeo, fromName, 'transit')
            : t2hub;
          if (toMin(mLast.leaveTime) + (t2hub2 ? t2hub2.minutes : 30) > mw.hubArr) {
            suggestions.push({ name: mLast.name, city: city.name, reason: `班次 ${sch ? sch.no + ' ' : ''}${sch ? sch.dep : fmt(anchor.depMin)} 出发，早场放不下（赶去车站时间不够），可手动加回` });
            morningDay = null;
            pts.unshift(morningPoi); // 归还到下午池
          }
        }
        afternoonPts = pts;

        // 枢纽对（第6类 POI）：到达出发枢纽时刻、发车/到达时刻均为固定锚
        const depLoc = {
          name: depHub.name, address: depHub.address || '', latitude: depHub.lng ? depHub.lat : null, longitude: depHub.lng || null,
          city: depHub.city || fromName, type: 'transport', hubKind: conf.hubKind,
          stayMinutes: conf.prep,
          transportMinutes: t2hub ? t2hub.minutes : null, transportMode: t2hub ? 'taxi' : null,
          transport: t2hub ? { type: 'taxi', scope: 'intraCity', durationMinutes: t2hub.minutes, distance: Math.round((t2hub.km || 0) * 1000) } : null,
          arrivalTime: fmt(mw.hubArr), leaveTime: fmt(anchor.depMin),
          _intercity: { kind: 'dep' },
        };
        const arrLoc = {
          name: arrHub.name, address: arrHub.address || '', latitude: arrHub.lng ? arrHub.lat : null, longitude: arrHub.lng || null,
          city: arrHub.city || city.name, type: 'transport', hubKind: conf.hubKind,
          stayMinutes: 45,
          transportMinutes: anchor.arrMin - anchor.depMin, transportMode: arriveLeg.vehicle,
          transport: {
            type: arriveLeg.vehicle, scope: 'intercity', durationMinutes: anchor.arrMin - anchor.depMin,
            distance: Math.round((arriveLeg.km || 0) * 1000),
            flightNumber: sch ? sch.no || null : null, departureTime: fmt(anchor.depMin), arrivalTime: fmt(anchor.arrMin),
            price: sch ? sch.price : null, isFixed: Boolean(sch), estimated: !sch,
          },
          arrivalTime: fmt(anchor.arrMin), leaveTime: fmt(anchor.arrMin + 45),
          _intercity: { kind: 'arr' },
        };
        headLocs = [depLoc, arrLoc];
        if (sch) {
          warnings.push(`${conf.emoji} ${sch.no || conf.label} ${fromName} ${sch.dep} → ${city.name} ${sch.arr}（班次时间固定，前后行程已按此锚定）`);
        } else {
          warnings.push(`${fromName}→${city.name} 跨城班次实时查询需高德企业认证，已按${conf.label}典型时长${arriveLeg.minutes}分钟占位（可在 schedules 传入真实班次完成锚定）`);
        }

        // 混合模式：取车城落地插租车点（包车不插，师傅到达口接）
        if (isRentalTrip && ci === rentalAtIdx) {
          if (groundMode === 'rental') {
            const rentalPoi = await findRentalHub(city.name, Number.isFinite(arrHub.lng) ? arrHub : city);
            if (rentalPoi) {
              const t2rental = Number.isFinite(arrHub.lng) && Number.isFinite(rentalPoi.lng)
                ? await segmentMinutes({ lng: arrHub.lng, lat: arrHub.lat, city: city.name }, rentalPoi, city.name, 'transit')
                : null;
              const rArr = anchor.arrMin + 45 + (t2rental ? t2rental.minutes : 15);
              const rentalLoc = toLocation({ ...rentalPoi, typecode: 'rental' }, rArr, 30, t2rental ? { minutes: t2rental.minutes, mode: 'transit', km: t2rental.km } : null, {});
              rentalLoc.hubKind = 'rental';
              headLocs.push(rentalLoc);
              afternoonStart = rArr + 30;
              if (Number.isFinite(rentalPoi.lng)) afternoonOrigin = { lng: rentalPoi.lng, lat: rentalPoi.lat, name: rentalPoi.name, city: city.name };
              warnings.push(`已插入取车点「${rentalPoi.name}」，此后行程按自驾计算（里程/充电/费用均切自驾口径）`);
            } else {
              afternoonStart = anchor.arrMin + 45;
              warnings.push('未找到合适租车点，请到达后自行安排取车');
            }
          } else {
            afternoonStart = anchor.arrMin + 45;
            warnings.push(`包车模式：师傅在「${arrHub.name}」到达口接站，行程按包车自驾计算`);
          }
        } else {
          afternoonStart = anchor.arrMin + 45;
        }
        if (!(Number.isFinite(afternoonOrigin?.lng) && afternoonOrigin !== prevPoint)) {
          afternoonOrigin = Number.isFinite(arrHub.lng)
            ? { lng: arrHub.lng, lat: arrHub.lat, name: arrHub.name, city: arrHub.city }
            : { lng: city.lng, lat: city.lat, name: city.name, city: city.name };
        }
      }

      // 组装当天：早场（可选）+ 头部枢纽块 + 下午主体；返程固定班次再追加尾部枢纽对
      let day;
      if (morningDay) {
        const afternoonDay = await buildDay(dayIdx, addDays(startDate, dayIdx), afternoonPts, { pace, city: city.name, warnings, tripMode, startClock: afternoonStart, origin: afternoonOrigin });
        day = { date: addDays(startDate, dayIdx), dayNumber: dayIdx + 1, locations: [...morningDay.locations, ...headLocs, ...afternoonDay.locations] };
      } else {
        const mainDay = await buildDay(dayIdx, addDays(startDate, dayIdx), afternoonPts, { pace, city: city.name, warnings, tripMode, startClock: afternoonStart, origin: afternoonOrigin });
        day = { ...mainDay, locations: headLocs.length ? [...headLocs, ...mainDay.locations] : mainDay.locations };
      }

      // 返程固定班次：尾部枢纽对（游玩锚定在发车前结束）
      if (returnTail) {
        const { conf, sch, depMin, arrMin, retDepHub, retArrHub } = returnTail;
        const lastAct = [...day.locations].reverse().find((l) => l.type !== 'transport' && Number.isFinite(l.longitude));
        const t2hub = lastAct && Number.isFinite(retDepHub.lng)
          ? await segmentMinutes({ lng: lastAct.longitude, lat: lastAct.latitude, city: city.name }, retDepHub, city.name, 'transit')
          : null;
        const depLoc = {
          name: retDepHub.name, address: retDepHub.address || '', latitude: retDepHub.lng ? retDepHub.lat : null, longitude: retDepHub.lng || null,
          city: retDepHub.city || city.name, type: 'transport', hubKind: conf.hubKind,
          stayMinutes: conf.prep,
          transportMinutes: t2hub ? t2hub.minutes : null, transportMode: t2hub ? 'taxi' : null,
          transport: t2hub ? { type: 'taxi', scope: 'intraCity', durationMinutes: t2hub.minutes, distance: Math.round((t2hub.km || 0) * 1000) } : null,
          arrivalTime: fmt(depMin - conf.prep), leaveTime: fmt(depMin),
          _intercity: { kind: 'dep' },
        };
        const arrLoc = {
          name: retArrHub.name, address: retArrHub.address || '', latitude: retArrHub.lng ? retArrHub.lat : null, longitude: retArrHub.lng || null,
          city: retArrHub.city || originName, type: 'transport', hubKind: conf.hubKind,
          stayMinutes: 45,
          transportMinutes: arrMin - depMin, transportMode: returnLeg.vehicle,
          transport: { type: returnLeg.vehicle, scope: 'intercity', durationMinutes: arrMin - depMin, flightNumber: sch.no || null, departureTime: sch.dep, arrivalTime: sch.arr, price: sch.price, isFixed: true },
          arrivalTime: fmt(arrMin), leaveTime: fmt(arrMin + 45),
          _intercity: { kind: 'arr' },
        };
        day.locations.push(depLoc, arrLoc);
        warnings.push(`返程 ${conf.emoji} ${sch.no || ''} ${city.name} ${sch.dep} → ${originName} ${sch.arr}（班次固定，当天行程已按此锚定）`);
      }

      // 每晚酒店（全程最后一天/过路城不排：返程到家、过路城顺路游）
      let lastLoc = day.locations[day.locations.length - 1];
      if (!isTripLastDay && !isWaypoint) {
        if (!lastLoc) warnings.push(`第${dayIdx + 1}天「${city.name}」无候选景点，仅安排住宿休整`);
        const anchorPoi = lastLoc && Number.isFinite(lastLoc.longitude) ? { lng: lastLoc.longitude, lat: lastLoc.latitude } : { lng: city.lng, lat: city.lat };
        // 选址兼顾两头：今晚末站(0.7) + 次日首站/下一城方向(0.6/0.4) —— 避免酒店扎堆在今晚景点旁、明早绕远路
        const anchors = [{ poi: anchorPoi, w: lastLoc ? 0.7 : 1 }];
        const nextPts = (groups[d + 1] || []).filter((p) => p.lat && p.lng).slice(0, 2);
        for (const np of nextPts) anchors.push({ poi: np, w: 0.6 });
        if (!nextPts.length && ci + 1 < order.length) anchors.push({ poi: { lng: order[ci + 1].lng, lat: order[ci + 1].lat }, w: 0.4 });
        const cands = await findHotels(anchors, budgetKey, party);
        const cityKey = city.name.replace(/(市|地区|自治州)$/, '');
        const sameCityStay = prevHotel && String(prevHotel.city || '').replace(/(市|地区|自治州)$/, '') === cityKey;
        if (sameCityStay) {
          // 连住默认（免每天打包搬行李，旅行者真实习惯）；更优者列为"可换"候选 —— 建议不决策
          const base = lastLoc && toMin(lastLoc.leaveTime) ? toMin(lastLoc.leaveTime) : (afternoonStart ?? startClock ?? START_CLOCK[pace]);
          const travel = lastLoc && Number.isFinite(lastLoc.longitude)
            ? await segmentMinutes({ lng: lastLoc.longitude, lat: lastLoc.latitude, city: city.name }, prevHotel, city.name, driveMode ? 'drive' : 'transit')
            : null;
          const arrival = base + (travel ? travel.minutes : 15);
          const hotelLoc = toLocation({ ...prevHotel, typecode: '100100' }, arrival, 600, travel, {});
          hotelLoc.stayNote = '连住';
          // 【裁 5 上游根治】酒店点自身直接带 cost（高德 biz_ext.cost 原串，如 "300-500"）。
          // 旧做法只有 hotelCandidates 里有价，客户端必须"按 name 回匹配自己"才能取到，
          // 用户改名 / 服务端不返回自身候选时就会永远取不到 —— 这里从根上消除该脆弱约定。
          hotelLoc.cost = prevHotel.cost || null;
          const alts = cands.filter((cd) => cd.poi.name !== prevHotel.name).slice(0, 3);
          if (alts.length) {
            hotelLoc.hotelCandidates = alts.map((cd) => ({
              name: cd.poi.name, address: cd.poi.address, latitude: cd.poi.lat, longitude: cd.poi.lng,
              rating: cd.poi.rating || null, cost: cd.poi.cost || null, reason: `${cd.reason}（若想换住）`,
            }));
          }
          day.locations.push(hotelLoc);
          lastLoc = hotelLoc;
        } else if (cands.length) {
          const best = cands[0];
          const base = lastLoc && toMin(lastLoc.leaveTime) ? toMin(lastLoc.leaveTime) : (afternoonStart ?? startClock ?? START_CLOCK[pace]);
          const travel = lastLoc && Number.isFinite(lastLoc.longitude)
            ? await segmentMinutes({ lng: lastLoc.longitude, lat: lastLoc.latitude, city: city.name }, best.poi, city.name, driveMode ? 'drive' : 'transit')
            : null;
          const arrival = base + (travel ? travel.minutes : 15);
          const hotelLoc = toLocation({ ...best.poi, typecode: '100100' }, arrival, 600, travel, {});
          // 【裁 5 上游根治】同上：酒店点自身带 cost，客户端不再依赖 name 回匹配
          hotelLoc.cost = best.poi.cost || null;
          hotelLoc.hotelCandidates = cands.map((cd) => ({
            name: cd.poi.name, address: cd.poi.address, latitude: cd.poi.lat, longitude: cd.poi.lng,
            rating: cd.poi.rating || null, cost: cd.poi.cost || null, reason: cd.reason,
          }));
          day.locations.push(hotelLoc);
          lastLoc = hotelLoc;
          prevHotel = best.poi;
          warnings.push(`第${dayIdx + 1}晚住「${best.poi.name}」（${best.reason}），同城后续晚默认连住，可在候选中切换`);
        } else {
          warnings.push(`第${dayIdx + 1}晚未找到合适酒店，请自行预订`);
        }
        const hotelLocFinal = day.locations[day.locations.length - 1];
        if (hotelLocFinal && Number.isFinite(hotelLocFinal.longitude)) {
          prevPoint = { lng: hotelLocFinal.longitude, lat: hotelLocFinal.latitude, name: hotelLocFinal.name, city: hotelLocFinal.city || city.name };
        } else {
          prevPoint = { lng: city.lng, lat: city.lat, name: city.name, city: city.name };
        }
      } else if (lastLoc && Number.isFinite(lastLoc.longitude)) {
        prevPoint = { lng: lastLoc.longitude, lat: lastLoc.latitude, name: lastLoc.name, city: lastLoc.city || city.name };
      }
      tripDays.push(day);
      dayIdx++;
    }
  }

  // 返程腿提示
  if (returnLeg) {
    warnings.push(`返程 ${returnLeg.from.name || ''}→${originName} 约 ${returnLeg.km}km / ${(returnLeg.minutes / 60).toFixed(1)}小时，请在最后一天预留时间（可在行程中删减当天景点）`);
  }

  // P1-15 费用预估（分段口径：自驾油/电+过路；班次票价按 schedule.price × 人数；租车/包车按天粗估）
  const driveLegs = legs.filter((l) => !l.isTransit);
  const driveKm = Math.round(driveLegs.reduce((s, l) => s + (l.km || 0), 0));
  const cost = {
    currency: 'CNY',
    items: {},
    note: '粗估口径：油 0.6 / 电 0.12 元/km、过路 0.45 元/km、租车 300 元/天、包车 600 元/天；班次票价以实际客票为准',
  };
  if (driveKm > 0) {
    cost.items.fuel = Math.round(driveKm * (ev ? 0.12 : 0.6));
    cost.items.toll = Math.round(driveKm * 0.45);
  }
  const schedPriceSum = legs.reduce((s, l) => s + ((l.schedule && l.schedule.price) || 0), 0);
  if (schedPriceSum > 0) cost.items.transit = Math.round(schedPriceSum * (party.adults + party.children));
  if (isRentalTrip) cost.items[groundMode] = Math.max(1, days - Math.max(0, rentalAtIdx)) * (groundMode === 'rental' ? 300 : 600);
  cost.total = Object.values(cost.items).reduce((s, n) => s + n, 0);

  const totalPlaces = tripDays.reduce((s, d) => s + d.locations.filter((l) => l.type === 'attraction').length, 0);
  return {
    trip: {
      name: `${originName}${roundTrip ? '环线' : ''}·${order.map((c) => c.name.replace(/(市|地区|自治州)$/, '')).join('→')}${days}日`,
      startDate,
      endDate: addDays(startDate, days - 1),
      tripMode,
      adults: party.adults,
      children: party.children,
      rooms: party.rooms,
      roomType: party.roomType,
      budget: budgetKey,
      days: tripDays,
    },
    stats: {
      totalPlaces,
      days: tripDays.length,
      source,
      pace,
      tripMode,
      roundTrip,
      ev: ev && driveMode,
      groundMode: isRentalTrip ? groundMode : null,
      rentalAt: isRentalTrip ? order[rentalAtIdx].name : null,
      schedulesLoaded: schedules.length,
      cities: order.map((c, i) => ({ name: c.name, stayDays: cityDays[i], stopType: c.stopType === 'waypoint' ? 'waypoint' : 'overnight', vehicle: c.vehicle || null, reason: c.reason || null })),
      legs: legs.map((l) => ({
        from: l.from.name || originName, to: l.to.name || originName, km: l.km, minutes: l.minutes,
        mode: l.isTransit ? 'transit' : 'drive', vehicle: l.vehicle || null, isReturn: Boolean(l.isReturn),
        estimated: Boolean(l.estimated),
        schedule: l.schedule ? { no: l.schedule.no, dep: l.schedule.dep, arr: l.schedule.arr, price: l.schedule.price, isFixed: true } : null,
      })),
      hints: hints.notes,
      suggestions, // 被收紧/裁剪的 POI，可手动加回（默认可撤销）
      cost,
    },
    warnings,
  };
}

// ---------- S6 编辑重算：用户增删改查/排序后，自动重算时刻表 ----------
// 输入：{ scope: 'day'|'trip', trip: { tripMode, days: [{ date, dayNumber, locations: [...] }] } }
// scope=day（默认）：只重算各天内部的时间链；scope=trip：额外做跨天衔接——
//   次晨按"9:00 从上一晚酒店出发"重算当天首站的真实交通（用户调整跨天顺序后整条链顺一遍）。
// 规则：只重算时间和交通（用户顺序与停留时长为准），不删用户数据；打烊冲突只提示不擅改。
export async function recalcTrip(input, { travelFn = null } = {}) {
  const trip = input && input.trip;
  if (!trip || !Array.isArray(trip.days)) { const e = new Error('缺少 trip.days'); e.status = 400; e.expose = true; throw e; }
  // M2：全行程地点数上限（每段都要算路，N 个点 ≈ N 次高德调用，必须封顶）
  const totalLocations = trip.days.reduce(
    (s, d) => s + (d && Array.isArray(d.locations) ? d.locations.length : 0), 0);
  if (totalLocations > MAX_TOTAL_LOCATIONS) {
    const e = new Error(`行程点数量过多：收到 ${totalLocations} 个，单次最多支持 ${MAX_TOTAL_LOCATIONS} 个`);
    e.status = 400; e.expose = true; throw e;
  }
  const scope = input.scope === 'trip' ? 'trip' : 'day';
  const mode = trip.tripMode === 'pureTransit' ? 'transit' : 'drive';
  const warnings = [];
  const dirCache = makeCache(30 * 60 * 1000); // 段间算路缓存：编辑重算不重复烧高德配额（direction 类不进 amapProxy 缓存）
  const doTravel = travelFn || (async (from, to) => {
    if (![from.longitude, from.latitude, to.longitude, to.latitude].every(Number.isFinite)) return null;
    const key = `${mode}|${from.longitude.toFixed(4)},${from.latitude.toFixed(4)}|${to.longitude.toFixed(4)},${to.latitude.toFixed(4)}`;
    const hit = dirCache.get(key);
    if (hit) return hit;
    const t = await segmentMinutes(
      { lng: from.longitude, lat: from.latitude, city: from.city || '' },
      { lng: to.longitude, lat: to.latitude, city: to.city || '' },
      to.city || from.city || '',
      mode
    );
    if (t) dirCache.set(key, t);
    return t;
  });

  let prevDayHotel = null;
  let tripChained = false;
  for (const day of trip.days) {
    if (!Array.isArray(day.locations)) continue;
    // scope=trip：跨天衔接（P1-13）——上一晚酒店 → 次晨 9:00 出发 → 当天首站
    if (scope === 'trip' && prevDayHotel && day.locations.length) {
      const first = day.locations[0];
      const firstIsHub = first.type === 'transport' && (first._intercity || first.transport?.scope === 'intercity');
      if (!firstIsHub && first.type !== 'hotel' && [prevDayHotel.longitude, prevDayHotel.latitude, first.longitude, first.latitude].every(Number.isFinite)) {
        const t = await doTravel(prevDayHotel, first);
        if (t) {
          first.transportMinutes = t.minutes;
          first.transportMode = mode;
          first.transport = { type: mode === 'drive' ? 'selfDrive' : 'transit', scope: 'intraCity', durationMinutes: t.minutes, distance: Math.round((t.km || 0) * 1000) };
          first.arrivalTime = fmt(540 + t.minutes);
          tripChained = true;
        }
      }
    }
    let prev = null;
    for (const loc of day.locations) {
      // 跨城枢纽块不动（判据用稳定字段：客户端序列化可能丢 _intercity 下划线字段）
      if (loc.type === 'transport' && (loc._intercity || loc.transport?.scope === 'intercity')) { prev = loc; continue; }
      const stay = Math.max(15, parseInt(loc.stayMinutes, 10) || 90);
      loc.stayMinutes = stay;
      if (prev) {
        const t = await doTravel(prev, loc);
        if (t) {
          loc.transportMinutes = t.minutes;
          loc.transportMode = mode; // 以用户出行为准（segmentMinutes 估算兜底会返回 transit/walk，不能代表自驾意图）
          loc.transport = { type: mode === 'drive' ? 'selfDrive' : 'transit', scope: 'intraCity', durationMinutes: t.minutes, distance: Math.round((t.km || 0) * 1000) };
        } else {
          warnings.push(`「${loc.name}」缺少坐标，未能重算与前一站的交通时间`);
        }
      }
      const arrival = prev && loc.transportMinutes != null
        ? toMin(prev.leaveTime) + loc.transportMinutes
        : (toMin(loc.arrivalTime) || 540); // 首站无有效时间（含 '00:00' 占位）默认 9:00
      loc.arrivalTime = fmt(arrival);
      loc.leaveTime = fmt(arrival + stay);
      const closeMin = toMin(loc.closeTime);
      if (closeMin !== null && arrival + stay > closeMin) {
        warnings.push(`「${loc.name}」${loc.closeTime}打烊，当前排法停留不足（${loc.arrivalTime}到达），建议调换顺序或压缩前站`);
      }
      prev = loc;
    }
    // 记录当晚酒店，供次晨跨天衔接（取当天最后一个酒店类点）
    for (let i = day.locations.length - 1; i >= 0; i--) {
      const l = day.locations[i];
      if (l.type === 'hotel' && Number.isFinite(l.longitude)) {
        prevDayHotel = { longitude: l.longitude, latitude: l.latitude, city: l.city || '' };
        break;
      }
    }
  }
  if (tripChained) warnings.push('已按"次晨 9:00 从上一晚酒店出发"重算各天首站交通（scope=trip）');
  return { trip, warnings };
}

// ---------- S7 实时价格（骨架）：高德参考价 + 联盟API预留 + 反爬红线 ----------
// 教训（北京-威海实测）：OTA 页面（携程/Trip.com）有 whaleguard 等反爬，禁止爬虫抓取；
// 实时价的唯一正路是联盟 API（携程联盟/美团联盟），未接入前只给参考价 + 官方 H5 入口 + 时间戳。
// P1-14 比价卡：返回 top3 候选并列（位置/评分/参考价），单一数字参考价易误导。
export async function lookupPrice({ city, name, kind = 'hotel' }) {
  if (!city || !name) { const e = new Error('需要 city 与 name 参数'); e.status = 400; e.expose = true; throw e; }
  const isHotel = kind !== 'ticket';
  const raw = await queryPois(city, { keywords: name, types: isHotel ? '100000' : '' }, 1);
  const now = new Date();
  const candidates = raw.map(normalizePoi).filter(Boolean).slice(0, 3)
    .map((p) => {
      const rawPoi = raw.find((r) => r.id === p.id);
      const cost = String(rawPoi?.biz_ext?.cost || '').match(/(\d+)(?:\s*-\s*(\d+))?/);
      return {
        name: p.name, address: p.address, latitude: p.lat, longitude: p.lng, rating: p.rating || null,
        reference: cost ? { low: parseInt(cost[1], 10), high: cost[2] ? parseInt(cost[2], 10) : parseInt(cost[1], 10), currency: 'CNY' } : null,
        source: 'amap-static（滞后参考，预订前以平台实时价为准）',
      };
    })
    .sort((a, b) => (b.rating || 0) - (a.rating || 0));
  const withPrice = candidates.find((c) => c.reference);
  return {
    kind: isHotel ? 'hotel' : 'ticket',
    name, city,
    poi: candidates[0] || null,
    candidates,
    reference: withPrice ? withPrice.reference : null,
    realTime: {
      available: false,
      provider: 'ctrip-union (P0-5 预留)',
      deepLink: isHotel ? 'https://m.ctrip.com/webapp/hotel/' : 'https://m.ctrip.com/webapp/you/',
      note: 'OTA 页面有反爬，不做爬虫抓取；实时价请接入联盟 API（携程联盟/美团联盟），CPS 佣金同源',
    },
    source: 'amap-static',
    fetchedAt: now.toISOString(),
    fetchedAtText: `截至 ${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`, // 比价卡三红线之一：标时间戳
    warning: candidates.length ? (withPrice ? null : '高德无参考价数据，仅返回候选位置信息') : `高德未搜到「${name}」`,
  };
}

// ---------- 路由注册 ----------
export function registerMultiCityRoutes(app) {
  // M2：corridor / recalc 各挂一个独立限流器（5 次/分/IP）。
  // 每次 makeRateLimit 调用返回独立桶，互不影响（util.js 已按限流器实例隔离计数）。
  const corridorLimit = makeRateLimit(MULTICITY_RATE);
  const recalcLimit = makeRateLimit(MULTICITY_RATE);

  app.post('/api/planner/corridor', corridorLimit, async (req, res, next) => {
    try {
      const result = await planCorridor(req.body || {});
      res.json(result);
    } catch (e) { next(e); }
  });
  app.post('/api/planner/recalc', recalcLimit, async (req, res, next) => {
    try {
      const result = await recalcTrip(req.body || {});
      res.json(result);
    } catch (e) { next(e); }
  });
  app.get('/api/planner/prices', async (req, res, next) => {
    try {
      const result = await lookupPrice({ city: req.query.city, name: req.query.name, kind: req.query.kind });
      res.json(result);
    } catch (e) { next(e); }
  });
}
