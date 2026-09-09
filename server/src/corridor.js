// 走廊/行程路线：OSRM 代理（供路线海报画真实路线线）
// GET /api/corridor/route?waypoints=lng,lat;lng,lat;...&profile=driving
import { makeCache, fetchJson } from './util.js';

const OSRM = 'https://router.project-osrm.org/route/v1';
const cache = makeCache(30 * 60 * 1000);

export function registerCorridorRoutes(app) {
  app.get('/api/corridor/route', async (req, res, next) => {
    try {
      const raw = String(req.query.waypoints || '');
      const profile = ['driving', 'walking'].includes(req.query.profile) ? req.query.profile : 'driving';
      const pts = raw
        .split(';')
        .map((s) => s.split(',').map(Number))
        .filter((p) => p.length === 2 && Number.isFinite(p[0]) && Number.isFinite(p[1]))
        .map((p) => `${p[0].toFixed(5)},${p[1].toFixed(5)}`);
      if (pts.length < 2) {
        return res.status(400).json({ error: '至少需要两个途经点' });
      }
      if (pts.length > 25) {
        return res.status(400).json({ error: '途经点过多（≤25）' });
      }
      const key = `${profile}|${pts.join(';')}`;
      const hit = cache.get(key);
      if (hit) return res.json(hit);
      const { ok, status, data } = await fetchJson(`${OSRM}/${profile}/${key.split('|')[1]}?overview=full&geometries=geojson`, { timeoutMs: 15000 });
      if (!ok || data?.code !== 'Ok' || !data.routes?.[0]?.geometry?.coordinates) {
        return res.status(502).json({ error: '路线服务暂不可用，请稍后再试' });
      }
      const r = data.routes[0];
      const out = {
        coordinates: r.geometry.coordinates, // [lng,lat][]
        distanceKm: +(r.distance / 1000).toFixed(1),
        durationH: +(r.duration / 3600).toFixed(1),
      };
      cache.set(key, out);
      res.json(out);
    } catch (e) { next(e); }
  });
}
