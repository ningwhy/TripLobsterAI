# 旅行行程创建助手 - 架构设计文档

**文档版本**: V1.0
**创建日期**: 2026-02-23
**作者**: 架构师
**状态**: 正式发布

---

## 一、技术选型

### 1.1 前端技术选型

| 技术栈 | 选型方案 | 理由 |
|--------|----------|------|
| 框架 | React 18 + TypeScript | 生态成熟、类型安全、组件化开发效率高 |
| 状态管理 | Zustand | 轻量级、API简洁、适合中低复杂度应用 |
| UI框架 | Ant Design 5.x | 组件丰富、符合国内用户习惯、地图集成友好 |
| 地图SDK | 高德地图 Web JS API V2.0 | 国内POI数据最全、路径规划能力强、支持多插件 |
| 构建工具 | Vite | 开发体验好、构建速度快 |
| HTTP客户端 | Axios | 功能完善、拦截器支持、TypeScript友好 |

**备选方案**：
- 若项目需要跨平台（小程序），可考虑 Taro 或 uni-app
- 若需要更强的移动端体验，可选 React Native

### 1.2 后端技术选型

| 组件 | 选型方案 | 理由 |
|------|----------|------|
| 语言 | Node.js (Express/NestJS) | 前后端语言统一、异步IO适合IO密集型操作 |
| 框架 | NestJS | 结构化设计、内置依赖注入、装饰器语法友好 |
| 数据库 | PostgreSQL + PostGIS | 支持地理空间数据、JSON支持好、稳定可靠 |
| 缓存 | Redis | 高性能、支持多种数据结构 |
| ORM | Prisma | 类型安全、自动迁移、跨数据库兼容 |
| 任务队列 | Bull | 集成简单、延迟任务支持、重试机制完善 |

**备选方案**：
- 若处理复杂地理计算，可选 Python + GeoDjango/GeoPandas
- 若数据量级大，可考虑 MongoDB + Redis

### 1.3 地图SDK选型对比

| 特性 | 高德地图 | 百度地图 |
|------|----------|----------|
| 国内POI数据 | 更全 | 较全 |
| 路径规划 | 算法成熟 | 算法成熟 |
| Web API限制 | 30万次/日（免费版） | 30万次/日（免费版） |
| 驾车规划 | 支持实时路况 | 支持实时路况 |
| 公共交通规划 | 支持 | 支持 |
| 逆地理编码 | 支持 | 支持 |
| 多插件支持 | 丰富 | 较丰富 |

**推荐**: 高德地图 Web JS API
- 理由：国内POI数据更全面、公交地铁规划更准确、API响应速度更快

### 1.4 数据库选型

| 数据库 | 用途 | 选型理由 |
|--------|------|----------|
| PostgreSQL + PostGIS | 主数据库 | 地理空间数据支持、JSON支持、稳定性高 |
| Redis | 缓存层 | 热点数据缓存、API限流、会话存储 |

---

## 二、系统架构设计

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              客户端层                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │
│  │  Web (H5)   │  │  小程序     │  │  PWA        │  │  Native App │    │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘    │
└─────────┼────────────────┼────────────────┼────────────────┼──────────┘
          │                │                │                │
          └────────────────┴────────────────┴────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              网关层                                      │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     API Gateway (Nginx/Kong)                     │   │
│  │  - 负载均衡                                                      │   │
│  │  - 限流熔断                                                      │   │
│  │  - 认证鉴权                                                      │   │
│  │  - 请求路由                                                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              应用服务层                                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │  Trip Service   │  │  Map Service    │  │  OTA Service    │         │
│  │  行程管理服务    │  │  地图计算服务    │  │  票务预订服务    │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │  Location Svc   │  │  Auth Service   │  │  Analytics Svc │         │
│  │  地点管理服务    │  │  认证服务        │  │  数据分析服务    │         │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                              ▼
┌────────────────────────────────┐   ┌────────────────────────────────┐
│          数据层                 │   │         外部接口层              │
│  ┌────────────────────────┐    │   │  ┌────────────────────────┐    │
│  │    PostgreSQL           │    │   │  │   高德/百度地图API      │    │
│  │    (主数据库)           │    │   │  │   地图服务              │    │
│  └────────────────────────┘    │   │  └────────────────────────┘    │
│  ┌────────────────────────┐    │   │  ┌────────────────────────┐    │
│  │    Redis               │    │   │  │   携程开放平台         │    │
│  │    (缓存/会话)         │    │   │  │   OTA接口              │    │
│  └────────────────────────┘    │   │  └────────────────────────┘    │
└───────────────────────────────┘   │  ┌────────────────────────┐       │
                                    │  │   飞猪开放平台         │       │
                                    │  │   OTA接口              │       │
                                    │  └────────────────────────┘       │
                                    │  ┌────────────────────────┐       │
                                    │  │   美团开放平台         │       │
                                    │  │   OTA接口              │       │
                                    │  └────────────────────────┘       │
                                    └────────────────────────────────────┘
```

### 2.2 微服务模块设计

#### 2.2.1 行程管理服务 (Trip Service)

```
职责:
  - 行程CRUD操作
  - 行程地点管理
  - 行程时间线计算
  - 行程分享与导出

API端点:
  POST   /api/trips              - 创建行程
  GET    /api/trips              - 获取行程列表
  GET    /api/trips/:id          - 获取行程详情
  PUT    /api/trips/:id          - 更新行程
  DELETE /api/trips/:id          - 删除行程
  POST   /api/trips/:id/locations - 添加地点
  PUT    /api/trips/:id/locations/:locId - 更新地点
  DELETE /api/trips/:id/locations/:locId - 删除地点
```

#### 2.2.2 地图计算服务 (Map Service)

```
职责:
  - POI搜索与地址解析
  - 距离/时间计算
  - 路径规划（自驾/公共交通）
  - 交通枢纽查找

API端点:
  GET    /api/maps/search        - POI搜索
  GET    /api/maps/geocode       - 地址转坐标
  GET    /api/maps/reverse-geocode - 坐标转地址
  GET    /api/maps/distance      - 距离计算
  GET    /api/maps/direction     - 路径规划
  GET    /api/maps/transit-hubs  - 查找交通枢纽

缓存策略:
  - 相同起点终点: 缓存24小时
  - POI搜索结果: 缓存1小时
```

#### 2.2.3 地点管理服务 (Location Service)

```
职责:
  - 地点信息管理
  - 地点类型定义
  - 地点收藏与历史

API端点:
  GET    /api/locations/:id       - 获取地点详情
  GET    /api/locations/search   - 搜索地点
  POST   /api/locations/favorite - 收藏地点
  GET    /api/locations/history  - 获取历史地点
```

#### 2.2.4 OTA票务服务 (OTA Service)

```
职责:
  - OTA平台对接（预留）
  - 票务信息查询
  - 预订跳转链接生成

API端点:
  GET    /api/ota/flights        - 查询航班
  GET    /api/ota/trains         - 查询火车
  GET    /api/ota/hotels         - 查询酒店
  GET    /api/ota/attractions    - 查询景点门票
  GET    /api/ota/book-link      - 生成预订跳转链接
```

### 2.3 技术架构分层

```
┌────────────────────────────────────────────────────┐
│                 Presentation Layer                 │
│              (React + Ant Design)                  │
│   - 页面组件                                        │
│   - 地图组件                                        │
│   - 表单组件                                        │
└────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────┐
│                 Application Layer                  │
│              (NestJS Controllers)                   │
│   - 请求验证                                        │
│   - 路由转发                                        │
│   - 响应包装                                        │
└────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────┐
│                   Service Layer                    │
│              (NestJS Services)                      │
│   - 业务逻辑                                        │
│   - 数据处理                                        │
│   - 缓存管理                                        │
└────────────────────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────┐
│               Infrastructure Layer                 │
│              (Prisma + Redis + APIs)               │
│   - 数据库操作                                      │
│   - 外部API调用                                     │
│   - 消息队列                                        │
└────────────────────────────────────────────────────┘
```

---

## 三、关键API设计

### 3.1 行程管理API

#### 3.1.1 创建行程

```typescript
// Request
POST /api/trips
{
  "name": "北京3日游",
  "startDate": "2026-03-01",
  "endDate": "2026-03-03",
  "travelers": 2,
  "description": "家庭出游"
}

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "id": "trip_abc123",
    "name": "北京3日游",
    "startDate": "2026-03-01",
    "endDate": "2026-03-03",
    "travelers": 2,
    "description": "家庭出游",
    "status": "draft",
    "createdAt": "2026-02-23T10:00:00Z",
    "updatedAt": "2026-02-23T10:00:00Z"
  }
}
```

#### 3.1.2 添加地点

```typescript
// Request
POST /api/trips/trip_abc123/locations
{
  "name": "故宫博物院",
  "type": "attraction",
  "address": "北京市东城区景山前街4号",
  "latitude": 39.9163,
  "longitude": 116.3972,
  "arrivalDate": "2026-03-01",
  "stayDuration": 180,  // 分钟
  "notes": "建议提前预约门票"
}

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "id": "loc_xyz789",
    "name": "故宫博物院",
    "type": "attraction",
    "address": "北京市东城区景山前街4号",
    "latitude": 39.9163,
    "longitude": 116.3972,
    "arrivalDate": "2026-03-01",
    "stayDuration": 180,
    "notes": "建议提前预约门票",
    "order": 1
  }
}
```

### 3.2 地图计算API

#### 3.2.1 计算两点间距离和时间

```typescript
// Request
GET /api/maps/distance
? originLng=116.3972&originLat=39.9163
& destinationLng=116.4274&destinationLat=39.9283
& mode=driving  // driving | transit | walking

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "origin": {
      "lng": 116.3972,
      "lat": 39.9163,
      "name": "故宫博物院"
    },
    "destination": {
      "lng": 116.4274,
      "lat": 39.9283,
      "name": "天坛公园"
    },
    "distance": {
      "direct": 3500,      // 直线距离(米)
      "driving": 5200      // 驾车距离(米)
    },
    "duration": {
      "driving": 1200,    // 驾车时间(秒)
      "transit": 1800     // 公交时间(秒)
    },
    "traffic": "畅通"      // 实时路况
  }
}
```

#### 3.2.2 路径规划（自驾方案）

```typescript
// Request
GET /api/maps/direction
? tripId=trip_abc123
& mode=driving

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "type": "driving",
    "totalDistance": 25600,    // 总距离(米)
    "totalDuration": 7200,    // 总时间(秒)
    "segments": [
      {
        "from": "故宫博物院",
        "to": "天坛公园",
        "distance": 5200,
        "duration": 1200,
        "route": "沿景山前街向南 -> 沿南池子大街 -> ...",
        "path": [[116.3972,39.9163], [116.3972,39.9180], ...]  // 路线坐标点
      },
      {
        "from": "天坛公园",
        "to": "王府井饭店",
        "distance": 2100,
        "duration": 600,
        "route": "...",
        "path": [...]
      }
    ]
  }
}
```

#### 3.2.3 公共交通方案

```typescript
// Request
GET /api/maps/direction
? tripId=trip_abc123
& mode=transit
& transitType=high_speed  // high_speed | airplane | train | bus | ferry

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "type": "transit",
    "transitType": "high_speed",
    "totalDistance": 0,
    "totalDuration": 14400,  // 包含中转的总时间
    "segments": [
      {
        "segmentType": "to_hub",       // 前往交通枢纽
        "from": "上海酒店",
        "to": "上海虹桥站",
        "distance": 18000,
        "duration": 1800,
        "method": "地铁10号线",
        "hubType": "high_speed"
      },
      {
        "segmentType": "main",         // 主交通
        "from": "上海虹桥站",
        "to": "北京南站",
        "transport": {
          "type": "high_speed",
          "trainNumber": "G2",
          "departureTime": "2026-03-01T09:00:00",
          "arrivalTime": "2026-03-01T13:30:00",
          "duration": 16200,
          "price": 553
        }
      },
      {
        "segmentType": "from_hub",     // 离开交通枢纽
        "from": "北京南站",
        "to": "北京酒店",
        "distance": 25000,
        "duration": 2400,
        "method": "打车",
        "hubType": "high_speed"
      }
    ],
    "estimatedArrival": "2026-03-01T17:30:00",
    "totalCost": 553 + 80 + 50  // 火车票 + 打车 + 地铁
  }
}
```

#### 3.2.4 查找交通枢纽

```typescript
// Request
GET /api/maps/transit-hubs
? lng=116.4274
& lat=39.9283
& type=airport  // airport | high_speed | railway | bus | port
& radius=50000  // 搜索半径(米)

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "hubs": [
      {
        "name": "北京首都国际机场",
        "type": "airport",
        "code": "PEK",
        "distance": 32000,
        "address": "北京市朝阳区首都机场",
        "lng": 116.5802,
        "lat": 40.0799,
        "transports": ["飞机"]
      },
      {
        "name": "北京大兴国际机场",
        "type": "airport",
        "code": "PKX",
        "distance": 65000,
        "address": "北京市大兴区榆垡镇",
        "lng": 116.4224,
        "lat": 39.5112,
        "transports": ["飞机"]
      }
    ]
  }
}
```

### 3.3 OTA票务API（预留接口）

#### 3.3.1 查询航班

```typescript
// Request
GET /api/ota/flights
? origin=PEK
& destination=SHA
& date=2026-03-01
& passengers=2

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "flights": [
      {
        "airline": "中国国航",
        "flightNumber": "CA1515",
        "origin": "PEK",
        "destination": "SHA",
        "departureTime": "2026-03-01T08:00:00",
        "arrivalTime": "2026-03-01T10:30:00",
        "duration": 9000,
        "price": 680,
        "cabin": "经济舱",
        "provider": "ctrip",
        "bookingUrl": "https://m.ctrip.com/..."
      }
    ]
  }
}
```

#### 3.3.2 生成预订跳转链接

```typescript
// Request
POST /api/ota/book-link
{
  "type": "flight",
  "provider": "ctrip",
  "params": {
    "dcity": "北京",
    "acity": "上海",
    "ddate": "2026-03-01",
    "flightNo": "CA1515"
  }
}

// Response
{
  "code": 0,
  "message": "success",
  "data": {
    "url": "https://m.ctrip.com/onlinebooking/flight/book?tickettype=0&ddate=2026-03-01&...",
    "expireAt": "2026-02-24T10:00:00Z",
    "provider": "ctrip"
  }
}
```

---

## 四、OTA对接方案

### 4.1 OTA对接可行性分析

| OTA平台 | 对接方式 | 可行性 | 限制说明 |
|---------|----------|--------|----------|
| 携程 | 开放平台API | 需商务合作 | 需要企业资质、API需付费、审核周期长 |
| 飞猪 | 淘宝开放平台 | 需商务合作 | 需要淘宝商家入驻、复杂分销资质 |
| 美团 | 美团开放平台 | 需商务合作 | 需要商家入驻、仅支持部分品类 |

### 4.2 OTA对接现状

**结论**: MVP阶段无法直接对接OTA真实接口

**原因**:
1. 所有主流OTA平台均需要企业资质和商务合作
2. 开放平台API通常需要商家入驻或分销资质
3. 真正的票务预订接口不对个人开发者开放

### 4.3 MVP阶段的OTA解决方案

#### 方案A: 深度链接跳转（推荐）

```
实现方式:
  1. 构建目标OTA的DeepLink/URL Scheme
  2. 用户点击后跳转到对应OTA App或H5页面
  3. 预填充查询参数，减少用户输入

支持的跳转类型:
  - 携程: 机票/火车票/酒店/景点
  - 飞猪: 机票/火车票/酒店/景点
  - 美团: 酒店/景点/餐饮
```

**优点**:
- 无需API对接
- 用户体验相对流畅
- 实现成本低

**缺点**:
- 无法获取订单状态
- 无法实现真正的闭环预订

#### 方案B: 第三方票务API

```
可选服务商:
  - 票务分销API（如: 趣旅API、布拉旅行API）
  - 航旅纵横API（仅限航班动态）
  - 12306官方API（仅火车票）

优点: 有可能获取真实票务数据
缺点: 资质要求仍然较高、价格不透明
```

### 4.4 OTA接口设计（预留扩展）

```typescript
// OTA Provider Interface
interface OtaProvider {
  name: string;           // ctrip | fliggy | meituan
  isEnabled: boolean;     // 是否启用
  apiEndpoint: string;    // API地址
  authType: string;       // 认证方式
}

interface OtaService {
  // 搜索票务
  searchFlights(params: FlightSearchParams): Promise<Flight[]>;
  searchTrains(params: TrainSearchParams): Promise<Train[]>;
  searchHotels(params: HotelSearchParams): Promise<Hotel[]>;
  searchAttractions(params: AttractionSearchParams): Promise<Attraction[]>;

  // 预订跳转
  generateBookingLink(params: BookingParams): Promise<BookingLink>;
}
```

### 4.5 OTA数据缓存策略

```typescript
// 缓存策略设计
const OTA_CACHE_CONFIG = {
  flights: {
    ttl: 300,      // 5分钟
    staleWhileRevalidate: 600  // 后台刷新
  },
  trains: {
    ttl: 60,       // 1分钟（火车票实时性要求高）
    staleWhileRevalidate: 0
  },
  hotels: {
    ttl: 3600,     // 1小时
    staleWhileRevalidate: 7200
  },
  attractions: {
    ttl: 86400,    // 24小时（景点信息变化少）
    staleWhileRevalidate: 43200
  }
};
```

---

## 五、数据模型设计

### 5.1 核心实体

```
┌─────────────────────────────────────────────────────────────────┐
│                        Trip (行程)                               │
├─────────────────────────────────────────────────────────────────┤
│ id: UUID                      # 主键                            │
│ name: string                  # 行程名称                         │
│ start_date: date              # 开始日期                         │
│ end_date: date                # 结束日期                         │
│ travelers: integer            # 出行人数                         │
│ description: text             # 行程描述                         │
│ status: enum                  # 状态: draft | planning |        │
│                               #          confirmed | completed  │
│ user_id: UUID                 # 用户ID                           │
│ created_at: timestamp         # 创建时间                         │
│ updated_at: timestamp         # 更新时间                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 1:N
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TripLocation (行程地点)                     │
├─────────────────────────────────────────────────────────────────┤
│ id: UUID                      # 主键                            │
│ trip_id: UUID                 # 行程ID (外键)                   │
│ name: string                  # 地点名称                         │
│ type: enum                    # 类型: hotel | restaurant |      │
│                               #          attraction | shopping  │
│                               #          | other | transit_hub   │
│ address: string               # 地址                             │
│ latitude: decimal             # 纬度                             │
│ longitude: decimal            # 经度                             │
│ arrival_date: date            # 到达日期                         │
│ stay_duration: integer        # 停留时长(分钟)                  │
│ order_index: integer          # 排序                             │
│ notes: text                   # 备注                             │
│ created_at: timestamp         # 创建时间                         │
│ updated_at: timestamp         # 更新时间                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 1:N
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     RouteSegment (行程段)                        │
├─────────────────────────────────────────────────────────────────┤
│ id: UUID                      # 主键                            │
│ trip_id: UUID                 # 行程ID (外键)                   │
│ from_location_id: UUID        # 起点地点ID                      │
│ to_location_id: UUID          # 终点地点ID                      │
│ transport_mode: enum          # 交通方式: driving | transit     │
│ transit_type: enum            # 公共交通类型: airplane |        │
│                               #          high_speed | train |    │
│                               #          bus | ferry             │
│ distance: integer             # 距离(米)                         │
│ duration: integer             # 时间(秒)                        │
│ route_path: json              # 路线坐标点                      │
│ estimated_cost: decimal       # 预估费用                        │
│ transit_hub_id: UUID          # 交通枢纽ID(可选)                │
│ created_at: timestamp         # 创建时间                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TransitHub (交通枢纽)                        │
├─────────────────────────────────────────────────────────────────┤
│ id: UUID                      # 主键                            │
│ name: string                  # 枢纽名称                        │
│ type: enum                    # 类型: airport | high_speed |    │
│                               #          railway | bus | port     │
│ code: string                  # 代码(IATA/铁路局代码)           │
│ address: string               # 地址                             │
│ latitude: decimal             # 纬度                             │
│ longitude: decimal            # 经度                             │
│ city: string                  # 所在城市                         │
│ region: string                # 地区                             │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 完整ER图

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│    User      │     │      Trip        │     │   TripLocation  │
├──────────────┤     ├──────────────────┤     ├─────────────────┤
│ id (PK)      │◄─── │ user_id (FK)     │◄─── │ trip_id (FK)    │
│ username     │     │ id (PK)          │     │ id (PK)         │
│ email        │     │ name             │     │ name            │
│ phone        │     │ start_date       │     │ type            │
│ created_at   │     │ end_date         │     │ address         │
│ updated_at   │     │ travelers        │     │ latitude        │
└──────────────┘     │ status           │     │ longitude       │
                     │ created_at       │     │ arrival_date    │
                     │ updated_at       │     │ stay_duration   │
                     └──────────────────┘     │ order_index     │
                                               │ notes           │
                     ┌──────────────────┐     │ created_at      │
                     │  RouteSegment    │     │ updated_at      │
                     ├──────────────────┤     └─────────────────┘
                     │ id (PK)          │
                     │ trip_id (FK)     │
                     │ from_location_id │
                     │ to_location_id   │
                     │ transport_mode   │
                     │ transit_type     │
                     │ distance         │
                     │ duration         │
                     │ route_path (JSON)│
                     │ estimated_cost   │
                     │ transit_hub_id   │
                     │ created_at       │
                     └──────────────────┘
                              │
                              │ N:1 (可选)
                              ▼
                     ┌──────────────────┐
                     │   TransitHub     │
                     ├──────────────────┤
                     │ id (PK)          │
                     │ name             │
                     │ type             │
                     │ code             │
                     │ address          │
                     │ latitude         │
                     │ longitude        │
                     │ city             │
                     │ region           │
                     └──────────────────┘

┌──────────────────┐     ┌──────────────────┐
│   FavoritePlace  │     │   TripHistory    │
├──────────────────┤     ├──────────────────┤
│ id (PK)          │     │ id (PK)          │
│ user_id (FK)     │     │ trip_id (FK)     │
│ location_name    │     │ user_id (FK)     │
│ address          │     │ viewed_at        │
│ latitude         │     └──────────────────┘
│ longitude        │
│ location_type    │
│ created_at       │
└──────────────────┘
```

### 5.3 Prisma Schema定义

```prisma
// schema.prisma

generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum TripStatus {
  DRAFT
  PLANNING
  CONFIRMED
  COMPLETED
}

enum LocationType {
  HOTEL
  RESTAURANT
  ATTRACTION
  SHOPPING
  OTHER
  TRANSIT_HUB
}

enum TransportMode {
  DRIVING
  TRANSIT
  WALKING
  CYCLING
}

enum TransitType {
  AIRPLANE
  HIGH_SPEED
  TRAIN
  BUS
  FERRY
}

enum HubType {
  AIRPORT
  HIGH_SPEED
  RAILWAY
  BUS
  PORT
}

model User {
  id        String   @id @default(uuid())
  username  String
  email     String?  @unique
  phone     String?  @unique
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  trips         Trip[]
  favoritePlaces FavoritePlace[]
  tripHistories TripHistory[]
}

model Trip {
  id          String     @id @default(uuid())
  name        String
  startDate   DateTime
  endDate     DateTime
  travelers   Int        @default(1)
  description String?
  status      TripStatus @default(DRAFT)
  userId      String
  createdAt   DateTime   @default(now())
  updatedAt   DateTime   @updatedAt

  user     User          @relation(fields: [userId], references: [id])
  locations TripLocation[]
  routes   RouteSegment[]
  histories TripHistory[]
}

model TripLocation {
  id           String       @id @default(uuid())
  name         String
  type         LocationType
  address      String
  latitude     Float
  longitude    Float
  arrivalDate  DateTime
  stayDuration Int          @default(120)  // 分钟
  orderIndex   Int
  notes        String?
  tripId       String
  createdAt    DateTime     @default(now())
  updatedAt    DateTime     @updatedAt

  trip        Trip          @relation(fields: [tripId], references: [id], onDelete: Cascade)
  fromRoutes  RouteSegment[] @relation("FromLocation")
  toRoutes    RouteSegment[] @relation("ToLocation")
}

model RouteSegment {
  id              String        @id @default(uuid())
  tripId          String
  fromLocationId  String
  toLocationId    String
  transportMode   TransportMode
  transitType     TransitType?
  distance        Int           // 米
  duration        Int           // 秒
  routePath       Json?         // 坐标点数组
  estimatedCost   Float?
  transitHubId    String?
  createdAt       DateTime      @default(now())

  trip         Trip          @relation(fields: [tripId], references: [id], onDelete: Cascade)
  fromLocation TripLocation  @relation("FromLocation", fields: [fromLocationId], references: [id])
  toLocation   TripLocation  @relation("ToLocation", fields: [toLocationId], references: [id])
  transitHub   TransitHub?   @relation(fields: [transitHubId], references: [id])
}

model TransitHub {
  id        String   @id @default(uuid())
  name      String
  type      HubType
  code      String?  // IATA代码或铁路局代码
  address   String
  latitude  Float
  longitude Float
  city      String
  region    String?

  routes RouteSegment[]
}

model FavoritePlace {
  id           String       @id @default(uuid())
  userId       String
  locationName String
  address      String
  latitude     Float
  longitude    Float
  locationType LocationType
  createdAt    DateTime     @default(now())

  user User @relation(fields: [userId], references: [id])
}

model TripHistory {
  id        String   @id @default(uuid())
  tripId    String
  userId    String
  viewedAt  DateTime @default(now())

  trip Trip  @relation(fields: [tripId], references: [id])
  user User  @relation(fields: [userId], references: [id])
}
```

### 5.4 数据库索引设计

```sql
-- 行程相关索引
CREATE INDEX idx_trip_user_id ON "Trip"(user_id);
CREATE INDEX idx_trip_status ON "Trip"(status);
CREATE INDEX idx_trip_date_range ON "Trip"(start_date, end_date);

-- 地点相关索引
CREATE INDEX idx_trip_location_trip_id ON "TripLocation"(trip_id);
CREATE INDEX idx_trip_location_order ON "TripLocation"(trip_id, order_index);
CREATE INDEX idx_trip_location_type ON "TripLocation"(type);

-- 路线相关索引
CREATE INDEX idx_route_segment_trip_id ON "RouteSegment"(trip_id);

-- 交通枢纽索引
CREATE INDEX idx_transit_hub_type ON "TransitHub"(type);
CREATE INDEX idx_transit_hub_city ON "TransitHub"(city);
CREATE INDEX idx_transit_hub_location ON "TransitHub"(latitude, longitude);

-- 地理空间索引 (PostGIS)
CREATE INDEX idx_trip_location_geom ON "TripLocation" USING GIST (geometry(POINT, 4326));
CREATE INDEX idx_transit_hub_geom ON "TransitHub" USING GIST (geometry(POINT, 4326));
```

---

## 六、关键技术难点和解决方案

### 6.1 地图路径规划计算

**难点描述**:
- 每次计算需要调用地图API，存在调用次数限制
- 多个地点的排列组合会导致API调用量激增
- 用户拖拽排序地点时需要实时更新路线

**解决方案**:

```typescript
// 1. 计算优化 - 增量计算
class RouteCalculator {
  // 仅计算变化的部分
  async recalculateAfterReorder(
    tripId: string,
    oldIndex: number,
    newIndex: number
  ): Promise<RouteSegment[]> {
    // 获取受影响的段
    const affectedSegments = this.getAffectedSegments(
      oldIndex,
      newIndex,
      this.locations.length
    );

    // 并行请求，限制并发
    const results = await this.batchCalculate(
      affectedSegments,
      { concurrency: 3 }
    );

    // 更新数据库
    await this.updateRouteSegments(results);

    return results;
  }

  // 2. 缓存策略 - LRU缓存 + Redis
  private async getCachedRoute(
    from: Coordinate,
    to: Coordinate,
    mode: TransportMode
  ): Promise<RouteResult | null> {
    const cacheKey = this.generateCacheKey(from, to, mode);
    const cached = await this.redis.get(cacheKey);

    if (cached) {
      return JSON.parse(cached);
    }
    return null;
  }

  // 3. 请求合并 - 相同起点终点的请求合并
  private requestQueue = new RequestQueue<RouteResult>({
    deduplication: true,
    ttl: 5000 // 5秒内的相同请求合并
  });
}
```

**缓存策略**:
```
缓存层级:
  L1: 内存缓存 (进程内) - 热点数据
  L2: Redis缓存 - 跨进程共享
  L3: 数据库缓存 - 持久化结果

缓存失效策略:
  - 相同起点终点: 24小时
  - 地图POI搜索: 1小时
  - 交通枢纽信息: 7天
```

### 6.2 交通枢纽自动添加

**难点描述**:
- 需要判断何时自动添加交通枢纽
- 交通枢纽的选择（距离最近 vs 时间最优）
- 用户手动指定 vs 系统自动推荐

**解决方案**:

```typescript
// 交通枢纽自动添加策略
class TransitHubManager {
  // 判断是否需要添加交通枢纽
  shouldAddHub(
    fromLocation: TripLocation,
    toLocation: TripLocation
  ): TransitType | null {
    const distance = this.calculateDirectDistance(
      fromLocation,
      toLocation
    );

    // 根据距离自动推荐交通方式
    if (distance > 800000) { // >800公里
      return 'AIRPLANE';
    } else if (distance > 300000) { // 300-800公里
      return 'HIGH_SPEED';
    } else if (distance > 100000) { // 100-300公里
      return 'TRAIN';
    } else {
      return null; // 不需要添加交通枢纽
    }
  }

  // 查找最近的交通枢纽
  async findNearestHubs(
    location: Coordinate,
    type: TransitType,
    limit: number = 3
  ): Promise<TransitHub[]> {
    // 1. 先从缓存/数据库查询
    let hubs = await this.hubRepository.findNearby(
      location.lat,
      location.lng,
      100000 // 100公里内
    );

    // 2. 如果缓存不足，调用地图API补充
    if (hubs.length < limit) {
      const apiHubs = await this.mapApi.searchTransitHubs(
        location,
        type
      );
      hubs = [...hubs, ...apiHubs];
    }

    // 3. 按距离排序
    return hubs
      .sort((a, b) => a.distance - b.distance)
      .slice(0, limit);
  }
}
```

### 6.3 地图API配额管理

**难点描述**:
- 免费API有日调用次数限制
- 防止恶意刷调用
- 需要合理的限流策略

**解决方案**:

```typescript
// API配额管理
class MapApiQuotaManager {
  private quotaConfig = {
    amap: {
      dailyLimit: 300000,
      perMinuteLimit: 1000,
      perSecondLimit: 50
    },
    baidu: {
      dailyLimit: 300000,
      perMinuteLimit: 1000,
      perSecondLimit: 50
    }
  };

  // 令牌桶限流
  private rateLimiter = new TokenBucket({
    capacity: 50,
    refillRate: 50, // 每秒补充50个令牌
  });

  async checkAndConsume(
    provider: 'amap' | 'baidu'
  ): Promise<boolean> {
    // 1. 检查日限额
    const todayUsage = await this.getDailyUsage(provider);
    if (todayUsage >= this.quotaConfig[provider].dailyLimit) {
      throw new QuotaExceededError('每日配额已用完');
    }

    // 2. 检查速率限制
    if (!await this.rateLimiter.tryConsume(1)) {
      throw new RateLimitError('请求过于频繁');
    }

    // 3. 记录使用
    await this.recordUsage(provider);

    return true;
  }

  // 降级策略
  private fallbackStrategies = {
    'driving': ['amap', 'baidu'],
    'transit': ['amap', 'baidu'],
    'geocode': ['amap', 'baidu']
  };

  async executeWithFallback<T>(
    strategy: string,
    fn: () => Promise<T>
  ): Promise<T> {
    for (const provider of this.fallbackStrategies[strategy]) {
      try {
        return await this.executeWithProvider(provider, fn);
      } catch (error) {
        if (error instanceof QuotaExceededError) {
          continue; // 尝试下一个provider
        }
        throw error;
      }
    }
    throw new Error('所有地图服务商均不可用');
  }
}
```

### 6.4 离线数据与性能优化

**难点描述**:
- 交通枢纽数据变动不频繁，适合本地缓存
- 用户可能在网络不稳定环境下使用
- 首次加载需要快速响应

**解决方案**:

```typescript
// 1. 预加载常用交通枢纽数据
class HubDataPreloader {
  // 启动时预加载主要城市的交通枢纽
  async preloadMajorCities(): Promise<void> {
    const majorCities = [
      '北京', '上海', '广州', '深圳', '杭州',
      '成都', '重庆', '西安', '南京', '武汉'
    ];

    await Promise.all(
      majorCities.map(city => this.loadCityHubs(city))
    );
  }

  // 定期更新（增量同步）
  async incrementalSync(): Promise<void> {
    const lastSyncTime = await this.getLastSyncTime();
    const changedHubs = await this.hubApi.getChangedHubs(
      lastSyncTime
    );

    await this.db.transaction(async (tx) => {
      for (const hub of changedHubs) {
        await tx.hub.upsert(hub);
      }
      await this.setLastSyncTime(new Date());
    });
  }
}

// 2. Service Worker缓存策略
const CACHE_STRATEGY = {
  // 静态资源: Cache First
  static: {
    pattern: /\/static\//,
    strategy: 'cacheFirst',
    maxAge: 86400 * 30 // 30天
  },
  // API数据: Stale While Revalidate
  api: {
    pattern: /\/api\//,
    strategy: 'staleWhileRevalidate',
    maxAge: 3600, // 1小时
    maxStale: 86400 // 离线可用1天
  },
  // 地图瓦片: Cache Only
  tile: {
    pattern: /\/\/rest\.amap\.com\/.*\.png/,
    strategy: 'cacheOnly',
    maxAge: 86400 * 30
  }
};
```

### 6.5 前后端数据同步

**难点描述**:
- 用户可能在多设备使用
- 离线修改需要同步
- 冲突解决策略

**解决方案**:

```typescript
// 乐观锁 + 增量同步
class TripSyncManager {
  // 版本控制
  private async saveWithVersion(trip: Trip): Promise<void> {
    const currentVersion = await this.getVersion(trip.id);

    await this.db.trip.update({
      where: { id: trip.id },
      data: {
        ...trip,
        version: currentVersion + 1,
        lastModified: new Date()
      }
    });
  }

  // 冲突检测与解决
  async resolveConflict(
    localTrip: Trip,
    serverTrip: Trip
  ): Promise<Trip> {
    // 策略: 最后写入者胜出 (Last Write Wins)
    // 考虑添加更智能的合并策略

    if (localTrip.lastModified > serverTrip.lastModified) {
      return localTrip;
    }
    return serverTrip;
  }

  // 增量同步
  async incrementalSync(changes: TripChange[]): Promise<SyncResult> {
    const results = [];

    for (const change of changes) {
      try {
        await this.applyChange(change);
        results.push({ id: change.id, status: 'success' });
      } catch (error) {
        results.push({ id: change.id, status: 'failed', error });
      }
    }

    return { results };
  }
}
```

---

## 七、非功能需求设计

### 7.1 性能设计

| 指标 | 目标值 | 实现方案 |
|------|--------|----------|
| API响应时间 | < 200ms | Redis缓存、读写分离 |
| 地图计算 | < 2s | 增量计算、并行请求 |
| 页面加载 | < 3s | SSR/SSG、CDN、懒加载 |
| 并发能力 | 1000 QPS | 水平扩展、微服务 |

### 7.2 安全设计

```
安全措施:
  1. 认证授权
     - JWT Token认证
     - 访问令牌 + 刷新令牌
     - 角色权限控制 (RBAC)

  2. 数据安全
     - HTTPS传输加密
     - 敏感数据AES加密存储
     - API Key后端存储，不暴露前端

  3. 接口安全
     - 请求签名验证
     - 限流防刷
     - SQL注入防护
     - XSS防护
```

### 7.3 可用性设计

```
高可用架构:
  1. 多实例部署
     - 无状态服务设计
     - 负载均衡

  2. 容灾备份
     - 数据库主从复制
     - 跨可用区部署
     - 定期备份

  3. 监控告警
     - 接口响应时间监控
     - 错误率监控
     - 配额使用监控
     - 异常告警通知
```

---

## 八、技术风险与应对

| 风险项 | 风险等级 | 应对方案 |
|--------|----------|----------|
| 地图API配额不足 | 高 | 1. 多平台备份 (高德+百度)<br>2. 严格缓存策略<br>3. 申请企业配额 |
| OTA接口无法对接 | 高 | 1. 使用DeepLink跳转方案<br>2. 预留接口便于后续扩展<br>3. 探索第三方票务API |
| 地理计算性能 | 中 | 1. 增量计算<br>2. 前端预计算<br>3. Web Worker后台处理 |
| 数据同步冲突 | 中 | 1. 乐观锁<br>2. 增量同步<br>3. 用户确认机制 |
| 地图定位不准 | 低 | 1. 允许用户手动修正坐标<br>2. 多源验证 |

---

## 九、开发计划建议

### 9.1 MVP阶段 (6-8周)

| 周次 | 工作内容 | 交付物 |
|------|----------|--------|
| 1 | 项目搭建、基础架构 | 项目骨架、技术验证 |
| 2-3 | 行程CRUD、地点管理 | 核心业务功能 |
| 4 | 地图SDK集成、POI搜索 | 地图基础能力 |
| 5 | 距离/时间计算、自驾方案 | 路径规划功能 |
| 6 | 公共交通方案、交通枢纽 | 综合出行方案 |
| 7 | 前端优化、集成测试 | 性能优化、Bug修复 |
| 8 | 验收、部署上线 | 上线交付 |

### 9.2 后续版本

| 版本 | 功能 | 周期 |
|------|------|------|
| V1.0 | 行程分享、导出PDF | 2周 |
| V1.1 | OTA DeepLink跳转 | 4周 |
| V2.0 | OCR识别截图、智能推荐 | 8周 |

---

## 十、附录

### 10.1 技术栈汇总

```
前端:
  - React 18 + TypeScript
  - Vite
  - Zustand (状态管理)
  - Ant Design 5.x
  - 高德地图 Web JS API
  - Axios
  - React Query

后端:
  - Node.js + NestJS
  - Prisma
  - PostgreSQL + PostGIS
  - Redis
  - JWT

DevOps:
  - Docker
  - GitHub Actions
  - PM2
```

### 10.2 参考文档

- [高德地图 Web API 文档](https://lbs.amap.com/api/webservice/guide/create-project/get-key)
- [PostGIS 地理空间扩展](https://postgis.net/documentation/)
- [NestJS 官方文档](https://docs.nestjs.com/)
- [Prisma ORM 文档](https://www.prisma.io/docs/)

---

**文档结束**

*本文档为架构设计初稿，具体实现时可根据项目实际情况调整。*
