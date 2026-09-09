// AI 行程生成引擎（P0-2 MVP）
// 架构：LLM 只做"编排与文案"，所有事实（地点/坐标/评分/路线）来自高德真实数据
// 默认走规则引擎：候选收集 → 评分排名 → 地理聚类分天 → NN+2-opt 排序 → 时刻表构建（含用餐、营业时间校验）
import { amapCall } from './amapProxy.js';
import { isLlmEnabled, llmChat } from './llm.js';

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

function parseOpenTime(poi) {
  const raw = poi.biz_ext?.opentime || poi.biz_ext?.open_time || '';
  const m = String(raw).match(/(\d{1,2}:\d{2})\s*[-—~至]\s*(\d{1,2}:\d{2})/);
  if (!m) return { open: null, close: null };
  return { open: m[1], close: m[2] };
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

function normalizePoi(p) {
  const [lng, lat] = String(p.location || '').split(',').map(Number);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const { open, close } = parseOpenTime(p);
  return {
    id: p.id,
    name: p.name,
    address: typeof p.address === 'string' ? p.address : (p.address?.[0]?.value || p.address?.[0] || ''),
    lat, lng,
    city: p.cityname || p.city || '',
    district: p.adname || p.district || '',
    typecode: p.typecode || '',
    rating: ratingOf(p),
    openTime: open,
    closeTime: close,
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

async function findNearbyRestaurant(lng, lat, atMin = null) {
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
      // 优先选该时段营业中的餐厅
      const open = pois.filter((p) => {
        const close = toMin(p.closeTime);
        const openM = toMin(p.openTime);
        if (close === null && openM === null) return true;
        if (openM !== null && atMin < openM) return false;
        return close === null || close - atMin >= 60;
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

async function buildDay(dayIndex, dateStr, points, { pace, city, warnings, tripMode = 'pureTransit' }) {
  if (!points.length) return { date: dateStr, dayNumber: dayIndex + 1, locations: [] };
  const driveMode = tripMode === 'pureDrive' || tripMode === 'transitPlusRental';
  const ordered = tourOrder(points);
  let clock = START_CLOCK[pace];
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
    const closeMin = toMin(poi.closeTime);
    if (closeMin !== null && arrival + stay > closeMin) {
      if (closeMin - arrival >= 45) {
        // 压缩停留时长以适应打烊
        const fit = Math.max(45, closeMin - arrival - 10);
        locations.push(toLocation(poi, arrival, fit, travel, extra));
        clock = arrival + fit;
        warnings.push(`第${dayIndex + 1}天「${poi.name}」打烊较早，建议停留时长已压缩至${fit}分钟`);
        return;
      }
      warnings.push(`第${dayIndex + 1}天「${poi.name}」按当前时间排到打烊前玩不完(${poi.closeTime}打烊)，建议调换顺序、提前安排或替换`);
    }
    locations.push(toLocation(poi, arrival, stay, travel, extra));
    clock = arrival + stay;
  };

  for (const poi of ordered) {
    let travel = prev ? await segmentMinutes(prev, poi, city, driveMode ? 'drive' : 'transit') : null;
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
      const meal = await findNearbyRestaurant(prev ? prev.lng : poi.lng, prev ? prev.lat : poi.lat, Math.max(clock, 12 * 60));
      if (meal) {
        await pushLoc({ ...meal, typecode: '050100' }, null, { isMeal: '午餐' });
        lunchDone = true;
      } else lunchDone = true;
    }
    await pushLoc(poi, travel);
    prev = poi;
    if (lunchDone && !dinnerDone && clock >= mealLimit.dinner) {
      const meal = await findNearbyRestaurant(poi.lng, poi.lat, clock);
      if (meal) {
        await pushLoc({ ...meal, typecode: '050100' }, { minutes: 10, mode: 'walk', km: 0.6 }, { isMeal: '晚餐' });
        dinnerDone = true;
      }
    }
  }
  // 天结束较早（如轻松节奏）时，补插入午餐
  if (!lunchDone && clock >= 12 * 60 && ordered.length) {
    const lastPoi = ordered[ordered.length - 1];
    const meal = await findNearbyRestaurant(lastPoi.lng, lastPoi.lat, Math.max(clock, 12 * 60));
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

function toLocation(poi, arrival, stay, travel, extra = {}) {
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
    openTime: poi.openTime || null,
    closeTime: poi.closeTime || null,
    rating: poi.rating || null,
    arrivalTime: fmt(arrival),
    leaveTime: fmt(arrival + stay),
    mealFor: extra.isMeal || null,
    _must: extra.must || false,
  };
}

function addDays(iso, n) {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + n);
  return d.toISOString().slice(0, 10);
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
  for (let i = 0; i < days; i++) {
    const pts = (groups[i] || []).map((p) => ({ ...p, _must: mustIds.has(p.id) }));
    dayResults.push(await buildDay(i, addDays(startDate, i), pts, { pace, city, warnings, tripMode }));
  }

  const totalPlaces = dayResults.reduce((s, d) => s + d.locations.filter((l) => l.type === 'attraction').length, 0);
  return {
    trip: {
      name: `${city.replace(/(市|地区|自治州)$/,'')}${days}日游`,
      startDate,
      endDate: addDays(startDate, days - 1),
      tripMode,
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
