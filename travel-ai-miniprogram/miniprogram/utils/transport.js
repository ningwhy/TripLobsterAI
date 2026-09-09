// utils/transport.js - 交通时间算法引擎（规则版，预留地图API接口）

/**
 * 交通算法引擎
 * 分三层：城市间 / 城市内 / 景区内
 * 当前版本：规则引擎
 * 升级路径：替换 calcCityToCity / calcInCity 为腾讯地图API调用
 */

const TransportEngine = {

  // ─── 常量定义 ───

  // 各类景点停车时间（分钟）
  PARKING_TIME: {
    urban: 20,      // 市区景点
    suburban: 10,   // 郊区景区
    popular: 30,    // 热门大景区（故宫/黄山等）
    default: 15
  },

  // 景区内交通时间（分钟）
  SCENIC_INTERNAL: {
    large_natural: 40,   // 大型自然景区（黄山/张家界）含摆渡+步行
    mountain: 50,        // 山地景区（含索道等待）
    ancient_town: 0,     // 古镇街区（步行，不加交通时间）
    theme_park: 15,      // 主题公园（园内交通）
    urban_park: 0,       // 城市公园（步行）
    default: 15
  },

  // 餐饮时长（分钟）
  MEAL_DURATION: {
    breakfast: 40,
    lunch: 60,
    dinner: 75,         // 家庭晚餐较慢
    snack: 30
  },

  // 景点游览时长（分钟）
  ATTRACTION_DURATION: {
    large: 180,         // 故宫、黄山、西湖
    medium: 120,        // 普通公园、古镇
    small: 60,          // 寺庙、广场、小景点
    theme_park: 300,    // 主题乐园（半天）
    museum: 90,
    default: 120
  },

  // 城市间交通基础参数
  INTERCITY: {
    flight: { base: 180, checkin: 90, pickup: 45 },  // 飞行+值机+取行李
    train: { speed: 250 },                           // 高铁均速km/h
    drive: { speed: 80, restInterval: 120, restTime: 20 }  // 自驾
  },

  // 家庭系数（有小孩节奏放慢）
  FAMILY_FACTOR: {
    '0-3': 1.4,   // 婴幼儿，节奏最慢
    '3-6': 1.25,  // 学龄前
    '6-12': 1.1,  // 小学生
    none: 1.0
  },

  // ─── 核心方法 ───

  /**
   * 计算城市间交通时间
   * @param {string} mode - train | flight | drive | recommend
   * @param {number} distance - 两城距离（km），暂用估算值
   * @param {object} options - { driverCount, useHighway, holiday }
   * @returns {object} { duration(min), desc, tips }
   */
  calcCityToCity(mode, distance, options = {}) {
    // TODO: 接入腾讯地图后，distance改为真实路线距离
    const { driverCount = 1, useHighway = true, holiday = false } = options

    switch (mode) {
      case 'flight': {
        const flyTime = Math.round(distance / 800 * 60) + 30 // 估算飞行时间
        const total = flyTime + this.INTERCITY.flight.checkin + this.INTERCITY.flight.pickup
        return {
          duration: total,
          desc: `✈️ 飞机约${flyTime}分钟，含值机候机约${total}分钟`,
          tips: '建议提前2小时到机场'
        }
      }
      case 'train': {
        const trainTime = Math.round(distance / this.INTERCITY.train.speed * 60)
        return {
          duration: trainTime + 30, // +候车时间
          desc: `🚄 高铁约${trainTime}分钟`,
          tips: '建议提前30分钟到站'
        }
      }
      case 'drive': {
        const speed = useHighway ? 90 : 60
        let driveTime = Math.round(distance / speed * 60)
        // 加休息时间
        const restCount = Math.floor(driveTime / this.INTERCITY.drive.restInterval)
        driveTime += restCount * this.INTERCITY.drive.restTime
        // 节假日堵车
        if (holiday) driveTime = Math.round(driveTime * 1.3)
        // 单人驾驶上限300km/天
        const maxDaily = driverCount === 1 ? 300 : 500
        const days = Math.ceil(distance / maxDaily)
        return {
          duration: driveTime,
          days,
          desc: `🚗 自驾约${driveTime}分钟（${distance}km）`,
          tips: driverCount === 1 && distance > 300 ? '单人驾驶建议分两天' : '建议途中休息'
        }
      }
      default: {
        // recommend：根据距离自动推荐
        if (distance < 200) return this.calcCityToCity('drive', distance, options)
        if (distance < 800) return this.calcCityToCity('train', distance, options)
        return this.calcCityToCity('flight', distance, options)
      }
    }
  },

  /**
   * 计算城市内两点间交通时间
   * @param {string} transportMode - drive | taxi | subway | walk
   * @param {string} fromType - 上一个地点类型
   * @param {string} toType - 目标地点类型
   * @returns {number} 分钟数
   * TODO: 替换为腾讯地图 /ws/direction/v1/driving/ 接口
   */
  calcInCity(transportMode, fromType, toType) {
    // 规则引擎：根据地点类型组合估算
    const matrix = {
      'hotel-attraction': 30,
      'hotel-food': 20,
      'attraction-attraction': 35,
      'attraction-food': 20,
      'food-attraction': 25,
      'food-hotel': 25,
      default: 30
    }
    const key = `${fromType}-${toType}`
    let base = matrix[key] || matrix.default

    // 自驾加停车时间
    if (transportMode === 'drive') {
      base += this.PARKING_TIME[toType] || this.PARKING_TIME.default
    }
    // 打车加等车时间
    if (transportMode === 'taxi') {
      base += 10
    }
    return base
  },

  /**
   * 获取景点游览时长
   * @param {string} attractionSize - large | medium | small | theme_park | museum
   * @param {array} childAges - 小孩年龄段数组
   * @returns {number} 分钟数
   */
  getAttractionDuration(attractionSize, childAges = []) {
    let base = this.ATTRACTION_DURATION[attractionSize] || this.ATTRACTION_DURATION.default
    // 家庭系数：取最小年龄段的系数（最慢的那个小孩决定节奏）
    const factor = this.getFamilyFactor(childAges)
    return Math.round(base * factor)
  },

  /**
   * 获取家庭系数
   */
  getFamilyFactor(childAges = []) {
    if (!childAges || childAges.length === 0) return this.FAMILY_FACTOR.none
    // 取影响最大的年龄段
    if (childAges.includes('0-3')) return this.FAMILY_FACTOR['0-3']
    if (childAges.includes('3-6')) return this.FAMILY_FACTOR['3-6']
    if (childAges.includes('6-12')) return this.FAMILY_FACTOR['6-12']
    return this.FAMILY_FACTOR.none
  },

  /**
   * 自驾每日最大合理里程
   */
  getDriveMaxDaily(driverCount) {
    return driverCount >= 2 ? 500 : 300
  }
}

module.exports = TransportEngine
