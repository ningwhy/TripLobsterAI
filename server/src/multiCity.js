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
import {
  gatherCandidates, geocodeCity, haversineKm, clusterByDay, buildDay,
  findHotels, segmentMinutes, findRestStop, toLocation, fmt, toMin, addDays,
  extractHints, queryPois, normalizePoi,
  INTERESTS, PER_DAY_CAP, START_CLOCK, STAY_FACTOR, VEHICLE_CONF,
} from './planner.js';

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
async function llmSuggestCities({ origin, days, tripMode, interestLabels, desc }) {
  const modeText = { pureDrive: '自驾（每日驾驶建议不超过6小时）', pureTransit: '公共交通', transitPlusRental: '公共交通+落地租车' }[tripMode] || tripMode;
  try {
    const content = await llmChat(
      [
        { role: 'system', content: '你是资深旅行规划师。根据出发地、总天数、出行方式和偏好，推荐真实存在、适合该行程的中途停留或深度游玩城市（不要推荐出发地本身）。输出JSON：{"cities":[{"name":"城市名","stayDays":2,"reason":"一句话理由"}]}。城市数2-6个，各城stayDays之和加上路途时间约等于总天数。' },
        { role: 'user', content: JSON.stringify({ origin, days, mode: modeText, interests: interestLabels, 用户描述: desc || '无' }) },
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
async function legTime(from, to, tripMode, vehicle) {
  const km = haversineKm(from, to);
  if (tripMode !== 'pureTransit') {
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
  // 公共交通：班次实时查询需高德企业认证（与单城规划一致的边界），按工具典型速度估算
  const conf = VEHICLE_CONF[vehicle] || VEHICLE_CONF.highSpeedTrain;
  return { minutes: Math.max(30, Math.round((km / conf.speedKmh) * 60 + conf.prep)), km, estimated: true };
}

// 公共交通跨城：枢纽对（无真实班次，时长估算，诚实提示）
async function findHub(cityName, vehicle) {
  const conf = VEHICLE_CONF[vehicle] || VEHICLE_CONF.highSpeedTrain;
  const pois = await queryPois(cityName, { keywords: conf.hubKw }, 1);
  const poi = pois.map(normalizePoi).find(Boolean);
  return poi || { name: `${cityName}${conf.hubKw}`, city: cityName, typecode: conf.fallbackCode, lng: null, lat: null, address: cityName };
}

// ---------- 主管线：多城走廊规划 ----------
export async function planCorridor(input) {
  const originName = String(input.origin || input.fromCity || '').trim();
  if (!originName) { const e = new Error('请填写出发地 origin（如：北京）'); e.status = 400; e.expose = true; throw e; }
  const days = Math.min(15, Math.max(2, parseInt(input.days, 10) || 5));
  const tripMode = ['pureDrive', 'pureTransit', 'transitPlusRental'].includes(input.tripMode) ? input.tripMode : 'pureDrive';
  const roundTrip = input.roundTrip !== false;
  const vehicle = ['flight', 'highSpeedTrain', 'train', 'bus', 'ship'].includes(input.intercityVehicle) ? input.intercityVehicle : 'highSpeedTrain';
  const warnings = [];

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
  const cap = PER_DAY_CAP[pace];

  // 出发地定位
  const originGeo = await geocodeCity(originName);
  if (!originGeo) { const e = new Error(`无法定位出发地「${originName}」`); e.status = 404; e.expose = true; throw e; }

  // S1/S2：城市集合 —— 用户显式给定，或 LLM 按攻略式推荐（失败报错，不编数据）
  let cityInputs = (Array.isArray(input.cities) ? input.cities : [])
    .map((c) => (typeof c === 'string' ? { name: c } : c))
    .filter((c) => c && typeof c.name === 'string' && c.name.trim())
    .map((c) => ({ name: c.name.trim().replace(/(市|地区|自治州)$/, ''), stayDays: Math.max(0, parseInt(c.stayDays, 10) || 0), reason: String(c.reason || '') }));
  let source = 'rule';
  if (!cityInputs.length) {
    if (!isLlmEnabled()) {
      const e = new Error('请提供想去的城市列表 cities（如 ["天津","潍坊","威海"]），或在服务端配置 LLM 后由 AI 按攻略自动推荐');
      e.status = 400; e.expose = true; throw e;
    }
    const suggested = await llmSuggestCities({ origin: originName, days, tripMode, interestLabels: interestKeys.map((k) => INTERESTS[k].label), desc: String(input.description || '').trim() });
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
  for (const leg of legs) {
    const t = await legTime(leg.from, leg.to, tripMode, vehicle);
    leg.minutes = t.minutes;
    leg.km = Math.round(t.km * 10) / 10;
    leg.estimated = Boolean(t.estimated);
  }
  const legToCity = order.map((c, i) => legs[i]); // legs[0]=origin→c0, legs[i]=c(i-1)→ci（环线最后一条是返程）
  const legHours = legs.map((l) => l.minutes / 60);

  // S3.5：天数分配
  const weights = order.map((c) => c.stayDays || 0);
  const { days: cityDays, legSum } = allocateCityDays(days, order.length, legHours, weights);
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
    const selected = candidates.slice(0, need);
    const groups = clusterByDay(selected, nDays, cap);

    const arriveLeg = legToCity[ci];
    for (let d = 0; d < nDays; d++) {
      let pts = groups[d].map((p) => ({ ...p, _must: mustIds.has(p.id) }));
      let startClock = null;
      let origin = prevPoint;

      // 赶路日收紧当天景点量：>6h 只留1站，3-6h 留2站
      if (d === 0 && arriveLeg) {
        const h = arriveLeg.minutes / 60;
        if (h > 6) pts = pts.slice(0, 1);
        else if (h > 3) pts = pts.slice(0, 2);
      }

      // 自驾长腿（>250km）：先插入高速服务区休息点（走廊式长线刚需）
      if (d === 0 && driveMode && arriveLeg && arriveLeg.km > 250 && pts.length) {
        const rest = await findRestStop(prevPoint, pts[0]);
        if (rest) {
          pts.unshift(rest);
          warnings.push(`第${dayIdx + 1}天赶路 ${arriveLeg.km}km，已在中途插入「${rest.name}」休息点`);
        }
      }

      // 公共交通跨城：起点改为到达枢纽，出发钟点让位给"候车+跨城+出站"
      let intercityHubs = null;
      if (d === 0 && !driveMode && !arriveLeg.isReturn) {
        const conf = VEHICLE_CONF[vehicle] || VEHICLE_CONF.highSpeedTrain;
        const fromName = arriveLeg.from.name || originName;
        const depHub = await findHub(fromName, vehicle);
        const arrHub = await findHub(city.name, vehicle);
        startClock = START_CLOCK[pace] + conf.prep + arriveLeg.minutes + 45;
        if (Number.isFinite(arrHub.lng)) origin = { lng: arrHub.lng, lat: arrHub.lat, name: arrHub.name, city: arrHub.city };
        intercityHubs = { depHub, arrHub, prep: conf.prep, vehicle };
        warnings.push(`${fromName}→${city.name} 跨城班次实时查询需高德企业认证，已按${conf.label}典型时长${arriveLeg.minutes}分钟占位（预订时填真实车次/航班）`);
      }

      const day = await buildDay(dayIdx, addDays(startDate, dayIdx), pts, { pace, city: city.name, warnings, tripMode, startClock, origin });

      // 枢纽对插到当天头部并回填时间
      if (intercityHubs) {
        const mk = (poi, kind) => ({
          name: poi.name,
          address: poi.address || '',
          latitude: poi.lng ? poi.lat : null,
          longitude: poi.lng || null,
          city: poi.city || '',
          type: 'transport',
          hubKind: (VEHICLE_CONF[vehicle] || VEHICLE_CONF.highSpeedTrain).hubKind,
          stayMinutes: kind === 'dep' ? intercityHubs.prep : 45,
          transportMinutes: kind === 'arr' ? arriveLeg.minutes : null,
          transportMode: kind === 'arr' ? intercityHubs.vehicle : null,
          transport: kind === 'arr' ? { type: intercityHubs.vehicle, scope: 'intercity', durationMinutes: arriveLeg.minutes, estimated: true } : null,
          _intercity: { kind },
        });
        let clock = START_CLOCK[pace];
        const depLoc = mk(intercityHubs.depHub, 'dep');
        depLoc.arrivalTime = fmt(clock);
        depLoc.leaveTime = fmt(clock + intercityHubs.prep);
        clock += intercityHubs.prep;
        const arrLoc = mk(intercityHubs.arrHub, 'arr');
        arrLoc.arrivalTime = fmt(clock);
        arrLoc.leaveTime = fmt(clock + 45);
        day.locations = [depLoc, arrLoc, ...day.locations];
      }

      // 每晚酒店（全程最后一天不排：返程到家/或由用户加）
      const isTripLastDay = ci === order.length - 1 && d === nDays - 1;
      let lastLoc = day.locations[day.locations.length - 1];
      if (!isTripLastDay && lastLoc) {
        const anchors = [{ poi: { lng: lastLoc.longitude, lat: lastLoc.latitude }, w: 1 }];
        const cands = await findHotels(anchors, budgetKey, party);
        if (cands.length) {
          const best = cands[0];
          const base = toMin(lastLoc.leaveTime) || (startClock ?? START_CLOCK[pace]);
          const travel = Number.isFinite(lastLoc.longitude)
            ? await segmentMinutes({ lng: lastLoc.longitude, lat: lastLoc.latitude, city: city.name }, best.poi, city.name, driveMode ? 'drive' : 'transit')
            : null;
          const arrival = base + (travel ? travel.minutes : 15);
          const hotelLoc = toLocation({ ...best.poi, typecode: '100100' }, arrival, 600, travel, {});
          hotelLoc.hotelCandidates = cands.map((cd) => ({
            name: cd.poi.name, address: cd.poi.address, latitude: cd.poi.lat, longitude: cd.poi.lng,
            rating: cd.poi.rating || null, cost: cd.poi.cost || null, reason: cd.reason,
          }));
          day.locations.push(hotelLoc);
          lastLoc = hotelLoc;
          warnings.push(`第${dayIdx + 1}晚住「${best.poi.name}」（${best.reason}）`);
        } else {
          warnings.push(`第${dayIdx + 1}晚未找到合适酒店，请自行预订`);
        }
      }
      if (lastLoc && Number.isFinite(lastLoc.longitude)) {
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
      cities: order.map((c, i) => ({ name: c.name, stayDays: cityDays[i], reason: c.reason || null })),
      legs: legs.map((l) => ({ from: l.from.name || originName, to: l.to.name || originName, km: l.km, minutes: l.minutes, isReturn: Boolean(l.isReturn), estimated: Boolean(l.estimated) })),
      hints: hints.notes,
    },
    warnings,
  };
}

// ---------- S6 编辑重算：用户增删改查/排序后，自动重算时刻表 ----------
// 输入：{ trip: { tripMode, days: [{ date, dayNumber, locations: [...] }] } }
// 规则：只重算时间和交通（用户顺序与停留时长为准），不删用户数据；打烊冲突只提示不擅改。
export async function recalcTrip(input, { travelFn = null } = {}) {
  const trip = input && input.trip;
  if (!trip || !Array.isArray(trip.days)) { const e = new Error('缺少 trip.days'); e.status = 400; e.expose = true; throw e; }
  const mode = trip.tripMode === 'pureTransit' ? 'transit' : 'drive';
  const warnings = [];
  const doTravel = travelFn || (async (from, to) => {
    if (![from.longitude, from.latitude, to.longitude, to.latitude].every(Number.isFinite)) return null;
    return segmentMinutes(
      { lng: from.longitude, lat: from.latitude, city: from.city || '' },
      { lng: to.longitude, lat: to.latitude, city: to.city || '' },
      to.city || from.city || '',
      mode
    );
  });

  for (const day of trip.days) {
    if (!Array.isArray(day.locations)) continue;
    let prev = null;
    for (const loc of day.locations) {
      if (loc.type === 'transport' && loc._intercity) { prev = loc; continue; } // 跨城枢纽块不动
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
        : (toMin(loc.arrivalTime) ?? 540);
      loc.arrivalTime = fmt(arrival);
      loc.leaveTime = fmt(arrival + stay);
      const closeMin = toMin(loc.closeTime);
      if (closeMin !== null && arrival + stay > closeMin) {
        warnings.push(`「${loc.name}」${loc.closeTime}打烊，当前排法停留不足（${loc.arrivalTime}到达），建议调换顺序或压缩前站`);
      }
      prev = loc;
    }
  }
  return { trip, warnings };
}

// ---------- S7 实时价格（骨架）：高德参考价 + 联盟API预留 + 反爬红线 ----------
// 教训（北京-威海实测）：OTA 页面（携程/Trip.com）有 whaleguard 等反爬，禁止爬虫抓取；
// 实时价的唯一正路是联盟 API（携程联盟/美团联盟），未接入前只给参考价 + 官方 H5 入口 + 时间戳。
export async function lookupPrice({ city, name, kind = 'hotel' }) {
  if (!city || !name) { const e = new Error('需要 city 与 name 参数'); e.status = 400; e.expose = true; throw e; }
  const isHotel = kind !== 'ticket';
  const raw = await queryPois(city, { keywords: name, types: isHotel ? '100000' : '' }, 1);
  const norms = raw.map(normalizePoi).filter(Boolean);
  const norm = norms.find((p) => p.name && p.name.includes(String(name).slice(0, 4))) || norms[0] || null;
  let reference = null;
  if (norm) {
    const rawPoi = raw.find((p) => p.id === norm.id);
    const cost = String(rawPoi?.biz_ext?.cost || '').match(/(\d+)(?:\s*-\s*(\d+))?/);
    if (cost) reference = { low: parseInt(cost[1], 10), high: cost[2] ? parseInt(cost[2], 10) : parseInt(cost[1], 10), currency: 'CNY' };
  }
  return {
    kind: isHotel ? 'hotel' : 'ticket',
    name, city,
    poi: norm ? { name: norm.name, address: norm.address, latitude: norm.lat, longitude: norm.lng, rating: norm.rating || null } : null,
    reference,
    realTime: {
      available: false,
      provider: 'ctrip-union (P0-5 预留)',
      deepLink: isHotel ? 'https://m.ctrip.com/webapp/hotel/' : 'https://m.ctrip.com/webapp/you/',
      note: 'OTA 页面有反爬，不做爬虫抓取；实时价请接入联盟 API（携程联盟/美团联盟），CPS 佣金同源',
    },
    source: 'amap-static',
    fetchedAt: new Date().toISOString(),
    warning: reference ? null : `高德无「${name}」的参考价数据`,
  };
}

// ---------- 路由注册 ----------
export function registerMultiCityRoutes(app) {
  app.post('/api/planner/corridor', async (req, res, next) => {
    try {
      const result = await planCorridor(req.body || {});
      res.json(result);
    } catch (e) { next(e); }
  });
  app.post('/api/planner/recalc', async (req, res, next) => {
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
