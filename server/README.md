# trip-server 后端服务

P0 阶段 1 后端：账号云同步 + 高德 Key 代理 + 天气 + AI 行程生成。

## 启动

```powershell
cd C:\Users\win11\lobsterai\trip\server
npm install        # 首次
node src/index.js  # 或 npm run dev（热重载）
```

默认监听 `http://0.0.0.0:8787`，数据存 `server/data/trip.db`（SQLite，已 gitignore）。

## 配置（.env）

| 变量 | 说明 |
|------|------|
| `PORT` | 端口，默认 8787 |
| `AMAP_KEY` | 高德 Web 服务 Key（只存服务端，客户端零密钥） |
| `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL` | 可选。任意 OpenAI 兼容接口（如 DeepSeek）。配置后 AI 行程生成升级为 LLM 编排+规则兜底；不配置则纯规则引擎，零成本 |

## API 一览

- `POST /api/auth/register|login|logout`、`GET /api/me` — 账号（scrypt 哈希 + 会话令牌）
- `GET /api/sync/pull?since=`、`POST /api/sync/push` — 行程云同步（LWW + 删除墓碑）
- `ANY /api/amap/v3/*` — 高德代理（白名单 9 个端点，带缓存与限流）
- `GET /api/weather?lat=&lon=` — Open-Meteo 16 天预报（免 Key）
- `POST /api/planner/generate` — AI 行程生成：`{city, days, startDate, pace, interests[], mustVisit[]}`
- `GET /api/planner/interests` — 兴趣类型列表
- `POST /api/planner/corridor` — 多城走廊规划（S1-S5 管线）：`{origin, cities[]?, days, tripMode, roundTrip, pace, interests[], mustVisit[], party...}`；cities 不传且已配 LLM 则 AI 推荐停留城市。详见根目录 `AI规划管线设计-多城走廊.md`
- `POST /api/planner/recalc` — 编辑重算（S6）：用户增删改查/排序后提交整包 trip，服务端以用户顺序为准重算交通与时间链
- `GET /api/planner/prices?city=&name=&kind=hotel|ticket` — POI 价格（S7 骨架）：高德参考价 + 联盟 API 预留（OTA 反爬，不做爬虫抓取）

## 客户端对接

- Flutter 端默认服务器地址 `http://<本机LAN IP>:8787`（App 内"云同步"页可改）
- Android 模拟器用 `http://10.0.2.2:8787`
- 高德调用链路：`AmapService → 本代理 → restapi.amap.com`

## 测试

```powershell
node test/smoke.mjs   # 全链路冒烟：auth/同步/代理/天气/AI生成
```

## 安全说明

- 客户端 APK 与源码已无任何高德 Key；泄露只需轮换服务端配置
- `/api` 全局限流 300 次/分钟/IP，高德代理单独 120 次/分钟
- 生产部署务必置于 HTTPS 反向代理之后（Nginx/Caddy 均可，无 WebSocket 需求到 P0-4 再加）
