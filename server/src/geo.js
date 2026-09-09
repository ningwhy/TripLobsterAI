// 示意图数据：行政区划边界（阿里 DataV GeoAtlas，免 Key） + 山川水系贴纸（高德自然 POI）
import { amapCall } from './amapProxy.js';
import { makeCache, fetchJson } from './util.js';

const boundaryCache = makeCache(24 * 60 * 60 * 1000);
const natureCache = makeCache(24 * 60 * 60 * 1000);

const DATAV = 'https://geo.datav.aliyun.com/areas_v3/bound';

// 城市名 → adcode（高德行政区划查询）
async function cityAdcode(cityName) {
  const data = await amapCall('/v3/config/district', { keywords: cityName, subdistrict: '0', extensions: 'base' });
  const d = data?.districts?.[0];
  if (!d) return null;
  return { adcode: String(d.adcode), center: d.center, name: d.name };
}

function simplifyRing(ring, maxPts = 320) {
  if (ring.length <= maxPts) return ring;
  const step = Math.ceil(ring.length / maxPts);
  return ring.filter((_, i) => i % step === 0);
}

// 下辖区县边界（不含海区划线）
async function cityBoundary(cityName) {
  const key = `b|${cityName}`;
  const hit = boundaryCache.get(key);
  if (hit) return hit;
  const meta = await cityAdcode(cityName);
  if (!meta) return null;
  const { ok, data } = await fetchJson(`${DATAV}/${meta.adcode}_full.json`, { timeoutMs: 15000 });
  if (!ok || !data?.features?.length) return null;
  const polygons = [];
  const labels = [];
  for (const f of data.features) {
    const name = f.properties?.name || '';
    const c = f.properties?.center || f.properties?.centroid;
    if (Array.isArray(c)) labels.push({ name, lng: c[0], lat: c[1] });
    const geom = f.properties?.adcode && f.properties?.parent?.adcode === meta.adcode ? f.geometry : f.geometry;
    if (!geom) continue;
    const rings = geom.type === 'MultiPolygon' ? geom.coordinates.flat() : (geom.type === 'Polygon' ? geom.coordinates : []);
    for (const ring of rings) {
      if (ring.length < 8) continue;
      polygons.push(simplifyRing(ring.map((p) => [p[0], p[1]])));
      break; // 每区县只取外环
    }
  }
  const out = { city: meta.name, polygons, labels };
  boundaryCache.set(key, out);
  return out;
}

const NATURE_KEYWORDS = [
  { kw: '山', kind: 'mountain' },
  { kw: '湖', kind: 'water' },
  { kw: '江', kind: 'water' },
  { kw: '河', kind: 'water' },
  { kw: '水库', kind: 'water' },
];

async function natureFeatures(cityName, bbox) {
  const key = `n|${cityName}`;
  const hit = natureCache.get(key);
  if (hit) return inBbox(hit, bbox);
  const seen = new Set();
  const all = [];
  for (const { kw, kind } of NATURE_KEYWORDS) {
    try {
      const data = await amapCall('/v3/place/text', {
        keywords: kw, types: '110200|110300', city: cityName, citylimit: 'true',
        offset: '10', page: '1', extensions: 'base',
      });
      for (const p of data?.pois || []) {
        const [lngS, latS] = String(p.location || '').split(',');
        const lng = Number(lngS), lat = Number(latS);
        if (!Number.isFinite(lng) || seen.has(p.id) || !p.name) continue;
        seen.add(p.id);
        all.push({ name: p.name, lng, lat, kind });
      }
    } catch {}
  }
  // 山水名要像自然地物（过滤纯商业名）
  const filtered = all.filter((n) => !/公司|酒店|餐厅|农家|民宿|景区售票/.test(n.name));
  natureCache.set(key, filtered);
  return inBbox(filtered, bbox);
}

function inBbox(list, bboxStr) {
  const b = String(bboxStr || '').split(',').map(Number);
  if (b.length !== 4 || b.some((v) => !Number.isFinite(v))) return list.slice(0, 12);
  return list.filter((n) => n.lng >= b[0] && n.lat >= b[1] && n.lng <= b[2] && n.lat <= b[3]).slice(0, 12);
}

export function registerGeoRoutes(app) {
  // 城市下辖区县边界（可多城市逗号分隔）
  app.get('/api/geo/boundary', async (req, res, next) => {
    try {
      const cities = String(req.query.city || '').split(/[,，]/).map((s) => s.trim()).filter(Boolean).slice(0, 4);
      if (!cities.length) return res.status(400).json({ error: '缺少 city 参数' });
      const results = await Promise.all(cities.map(cityBoundary));
      const ok = results.filter(Boolean);
      if (!ok.length) return res.status(404).json({ error: '未找到行政区划数据' });
      res.json({
        polygons: ok.flatMap((r) => r.polygons),
        labels: ok.flatMap((r) => r.labels),
        cities: ok.map((r) => r.city),
      });
    } catch (e) { next(e); }
  });

  // 路线沿途山川水系
  app.get('/api/geo/nature', async (req, res, next) => {
    try {
      const city = String(req.query.city || '').trim();
      if (!city) return res.status(400).json({ error: '缺少 city 参数' });
      const feats = await natureFeatures(city, String(req.query.bbox || ''));
      res.json({ features: feats });
    } catch (e) { next(e); }
  });
}
