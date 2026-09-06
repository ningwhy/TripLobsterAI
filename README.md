# 旅行行程助手 TripPlanner Pro

Flutter 移动端旅行行程规划 App + Node.js 后端。目标：让自由行像跟团一样省心，同时保留行程的完全可控性（AI 给建议，用户做决策）。

## 架构

```
Flutter App ──► trip-server (Node + SQLite, server/)
                ├── 账号 + 行程云同步（LWW + 删除墓碑）
                ├── 高德 Web API 代理（Key 仅存服务端，缓存+限流+重试）
                ├── Open-Meteo 天气（免 Key）
                └── AI 行程生成引擎（规则引擎：真实POI收集→评分→地理聚类分天→2-opt排序→时刻表；可选 LLM 增强编排）
```

## 快速开始

### 后端

```powershell
cd server
npm install
node src/index.js     # 默认 http://0.0.0.0:8787，配置见 server/.env
```

### App

```powershell
flutter pub get
flutter run           # 或 flutter build apk --debug
```

首次使用：App 首页右上角 ☁️ 云同步 → 确认服务器地址（模拟器 `http://10.0.2.2:8787`，真机填电脑局域网 IP）→ 注册账号，之后行程自动云同步。

### 测试

```powershell
flutter test              # Dart 模型/同城判断测试
node server/test/smoke.mjs  # 后端全链路冒烟（auth/同步/代理/天气/AI生成）
```

## 页面

| 页面 | 功能 |
|------|------|
| 首页 | 行程列表、快捷入口（足迹 / **AI 帮我规划**）、云同步状态 |
| AI 帮我规划 | 目的地+天数+节奏+兴趣+必去 → 一键生成可编辑行程（先预览，采纳才落库） |
| 行程创建 | 手动时间线编辑、POI 搜索、交通衔接 |
| 行程预览 | 时间线总览、费用预估、交通信息 |
| 云同步设置 | 服务器地址、登录/注册、手动同步 |

## 文档

- [PRD-旅行行程创建助手V2.0.md](PRD-旅行行程创建助手V2.0.md) — 产品需求
- [AI能力优化方案.md](AI能力优化方案.md) — P0/P1 优化路线（阶段1已落地）
- [TREK项目调研.md](TREK项目调研.md) — 开源竞品调研与借鉴点
- [server/README.md](server/README.md) — 后端 API 与部署说明

## 安全注意

- 高德 Key 只存在 `server/.env`，客户端与 APK 零密钥
- 生产部署必须走 HTTPS 反向代理
- 云同步为 MVP 实现（LWW 合并），敏感场景后续引入端到端加密
