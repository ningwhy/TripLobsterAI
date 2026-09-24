# AI 规划管线设计：多城走廊版（S1→S7）

**日期**: 2026-09-24
**需求来源**: 主理人管线规格 —— "AI 研究游记攻略 → 按需求+时长选停留城市 → 按坐标排城市顺序 → 城内找高价值吃玩住娱 POI → 高德按用户出行动式串联 → 用户可增删改查/排序并自动重算 → 实时拉取 POI 价格"
**状态**: ✅ 管线已实现（`server/src/multiCity.js`），单测 19 项通过，/recalc 与 /prices 已实测；corridor 全链路需配 AMAP_KEY 后跑真实数据验证

---

## 一、管线阶段 ↔ 代码映射

| 阶段 | 规格 | 实现 | 端点 | 状态 |
|------|------|------|------|------|
| S1 | AI 研究多篇游记攻略 | `llmSuggestCities()`：LLM 按出发地/天数/出行方式/偏好推荐 2-6 个真实城市（jsonMode，失败显式报错**不编数据**）；用户也可显式传 `cities` 跳过 | POST `/api/planner/corridor` | ✅（LLM 需配 .env） |
| S2 | 按需求和时长选停留城市 | 推荐结果逐城 `geocodeCity` 校验（剔除无效/出发地同名），LLM 给出 `stayDays` 权重 | 同上 | ✅ |
| S3 | 按城市坐标排先后顺序 | `orderCities()`：最近邻 + 2-opt（直线距离优化，环线把回程计入成本）；最终腿用高德驾车路线算真实 km/分钟 | 同上 | ✅ 单测通过（北京环线样本：天津→潍坊→…） |
| S3.5 | ——（天数分配） | `allocateCityDays()`：赶路腿吸收进天卡（>6h 当天只留 1 站、3-6h 留 2 站），总天数按权重分到各城（每城保底 1 天） | 同上 | ✅ 单测通过 |
| S4 | 城内高价值吃玩住娱 POI | 复用单城管线：`gatherCandidates`（高德真实 POI 按兴趣收集+评分排序）、`clusterByDay`（地理分天）、`findHotels`（每晚 3 候选）、`buildDay`（含正餐插入/营业时间校验/超时裁剪） | 同上 | ✅（复用已验证代码） |
| S5 | 高德按用户出行方式串联 | 自驾：`segmentMinutes/drive` 逐腿算真实驾车路线；>250km 自动插服务区休息点；公共交通：枢纽对+典型时长占位（班次实时查询需高德企业认证，诚实提示） | 同上 | ✅ |
| S6 | 用户增删改查/排序后自动重算 | `recalcTrip()`：以**用户顺序与停留时长为准**，逐站重算交通+到达/离开时间链；打烊冲突只提示不擅改（建议不决策） | POST `/api/planner/recalc` | ✅ 已实测（HTTP 全链路） |
| S7 | 实时拉取 POI 价格 | `lookupPrice()`：高德参考价（biz_ext.cost）+ 联盟 API 预留 + 官方 H5 deepLink + 时间戳 | GET `/api/planner/prices?city=&name=&kind=` | ✅ 骨架（联盟 API 是 P0-5） |

## 二、关键设计决策

1. **LLM 永远不是事实来源**（铁律）：城市推荐结果必须过高德 geocode 校验，定位失败即剔除并提示；LLM 不可用时显式报错要求用户传 `cities`，绝不幻觉编造。
2. **赶路不占独立天卡**：长腿（>6h）吸收进抵达城市第一天（景点收紧到 1 站 + startClock 后移），这与真实自驾节奏一致（对标北京-威海 7 天样本：每天天卡=赶路+游玩混合）。
3. **走廊自驾优先**：`pureDrive` 全链路真实数据；`pureTransit` 跨城班次受"高德企业认证"限制按典型时长占位（与单城管线同一边界，warning 注明）。
4. **S7 反爬红线**（北京-威海实测教训）：携程/Trip.com 有 whaleguard 等反爬，**不做爬虫抓取**；实时价唯一正路是联盟 API（携程联盟/美团联盟），CPS 佣金同源，未接入前只给参考价+deepLink+时间戳。
5. **S6 是纯重算器**：不改用户顺序、不删用户数据、停留时长以用户为准；只重算交通与时间链，冲突仅提示。

## 三、API

```
POST /api/planner/corridor
{
  "origin": "北京",                 // 必填
  "cities": ["天津","潍坊","威海"],  // 可选；不传且已配 LLM 则 AI 推荐
  "days": 7, "startDate": "2026-09-30",
  "tripMode": "pureDrive",          // pureDrive(默认) | pureTransit | transitPlusRental
  "roundTrip": true,                // 环线（默认 true）
  "intercityVehicle": "highSpeedTrain",  // 仅 pureTransit 用
  "pace": "normal", "interests": ["nature","culture"],
  "description": "带娃自驾，想赶海", "mustVisit": ["刘公岛"],
  "adults": 4, "children": 3, "rooms": 2, "roomType": "family", "budget": "comfort"
}
→ 与 /api/planner/generate 同构的 trip JSON（客户端零改动可渲染）
→ stats.cities / stats.legs 含城市顺序、每城天数、真实里程耗时

POST /api/planner/recalc        // 用户编辑后重算（增删改查/排序后整包提交）
GET  /api/planner/prices?city=威海&name=温德姆&kind=hotel
```

## 四、验证记录（2026-09-24）

- `node test/multicity.mjs`：19/19 通过（S3 排序 7 项、S3.5 分配 3 项、S6 重算 8 项 + 跨城枢纽保护）
- HTTP 实测（无 AMAP_KEY 环境）：`/` 健康、`/api/planner/recalc` 时间链传播正确（09:00→12:00 →+102min→13:42→17:42，距离 38.2km 估算兜底）、`/api/planner/prices` 优雅降级（返回结构+warning，不 500）
- **待真机验证**：`/api/planner/corridor` 全链路（需 `.env` 配 `AMAP_KEY`，建议在开发机上跑 `node test/smoke.mjs` 风格的真实生成：北京→潍坊→威海 7 天）
- 已知边界：跨城班次（火车/飞机实时时刻表）需高德企业认证；LLM 城市推荐需配置 `LLM_BASE_URL/LLM_API_KEY/LLM_MODEL`

## 五、下一步（按 ROI 排序）

1. 真机跑 corridor 全链路（配 AMAP_KEY + LLM），用"北京 7 天环线"做回归样本
2. Flutter 端接入 corridor + recalc：编辑操作本地乐观更新 → 防抖调 `/recalc` 同步服务端精确时间
3. S7 接携程联盟 API（P0-5 比价卡），替换 deepLink 占位
4. 城内分天升级 LLM 分组（复用单城 `llmAssign` 思路，按城调用）
