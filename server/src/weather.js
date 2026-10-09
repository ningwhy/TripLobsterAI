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
      // WX-02：daily 补风字段（最大风速 + 主导风向），供客户端展示「NW 10km/h」；16 天窗口不变
      const daily = [
        'temperature_2m_max',
        'temperature_2m_min',
        'precipitation_probability_max',
        'weather_code',
        'wind_speed_10m_max',
        'wind_direction_10m_dominant',
      ].join(',');
      const url =
        `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
        `&daily=${daily}` +
        '&wind_speed_unit=kmh' +
        '&timezone=Asia%2FShanghai&forecast_days=16';
      const { ok, data } = await fetchJson(url, { timeoutMs: 10000 });
      if (!ok || !data) return res.status(502).json({ error: '天气服务暂不可用' });
      res.json(data);
    } catch (e) { next(e); }
  });
}
