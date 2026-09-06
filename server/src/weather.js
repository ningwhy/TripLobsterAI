// 天气：Open-Meteo 免 Key 代理（16 天预报）
import { fetchJson } from './util.js';

export function registerWeatherRoutes(app) {
  app.get('/api/weather', async (req, res, next) => {
    try {
      const lat = parseFloat(req.query.lat);
      const lon = parseFloat(req.query.lon);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
        return res.status(400).json({ error: '需要 lat/lon 参数' });
      }
      const url =
        `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code' +
        '&timezone=Asia%2FShanghai&forecast_days=16';
      const { ok, data } = await fetchJson(url, { timeoutMs: 10000 });
      if (!ok || !data) return res.status(502).json({ error: '天气服务暂不可用' });
      res.json(data);
    } catch (e) { next(e); }
  });
}
