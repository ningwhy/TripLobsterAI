// utils/scheduler.js - 行程时间排布引擎

const TransportEngine = require('./transport')

/**
 * 行程调度器
 * 输入：AI生成的活动骨架（有顺序无时间）+ 用户参数
 * 输出：带精确时间的完整行程
 */
const Scheduler = {

  // 每天时间边界
  DAY_START: 7 * 60 + 30,   // 07:30
  DAY_END: 21 * 60 + 30,    // 21:30
  BREAKFAST_END: 8 * 60 + 30, // 早餐结束时间
  LUNCH_WINDOW: [11 * 60 + 30, 13 * 60 + 30],  // 午餐时间窗口
  DINNER_WINDOW: [17 * 60 + 30, 20 * 60],       // 晚餐时间窗口（放宽到20:00）
  AFTERNOON_REST: 13 * 60 + 30, // 13:30 午休（有婴幼儿时插入）

  /**
   * 主入口：给整个行程排时间
   * @param {object} itinerary - AI生成的行程骨架
   * @param {object} userParams - 用户输入参数
   * @returns {object} 带精确时间的行程
   */
  schedule(itinerary, userParams) {
    const { transportMode, driverCount, childAges = [], days: totalDays } = userParams

    const scheduledDays = itinerary.days.map((day, index) => {
      const isFirstDay = index === 0
      const isLastDay = index === itinerary.days.length - 1
      return this.scheduleDay(day, {
        isFirstDay,
        isLastDay,
        transportMode,
        driverCount,
        childAges,
        totalDays
      })
    })

    return { ...itinerary, days: scheduledDays }
  },

  /**
   * 排布单天行程
   */
  scheduleDay(day, params) {
    const { isFirstDay, isLastDay, transportMode, childAges } = params
    const hasInfant = childAges.includes('0-3')
    const hasToddler = childAges.includes('3-6')

    let cursor = this.DAY_START  // 当前时间指针（分钟）
    const scheduled = []

    // 第一天：加城市间交通时间
    if (isFirstDay) {
      cursor = this.scheduleFirstDay(day, params, scheduled)
    } else {
      // 非第一天：插入早餐
      scheduled.push({
        time: this.minToTime(cursor),
        type: 'food',
        title: '🥐 早餐',
        desc: '酒店早餐或附近餐厅',
        duration: TransportEngine.MEAL_DURATION.breakfast,
        mealType: 'breakfast'
      })
      cursor += TransportEngine.MEAL_DURATION.breakfast
    }

    // 遍历活动列表，逐个分配时间
    const activities = day.activities || []
    let prevType = 'hotel'
    let lunchScheduled = false
    let dinnerScheduled = false
    let afternoonRestDone = false

    for (let i = 0; i < activities.length; i++) {
      const act = activities[i]

      // 超时校验：超过21:30停止安排
      if (cursor >= this.DAY_END) {
        console.warn(`Day ${day.day}: 行程超时，已截断后续活动`)
        break
      }

      // ── 先检查是否需要插入午餐（在去下一个景点之前）──
      if (!lunchScheduled && cursor >= this.LUNCH_WINDOW[0]) {
        const transit = this.getTransitTime(prevType, 'food', transportMode)
        if (transit > 0) {
          scheduled.push({
            time: this.minToTime(cursor),
            type: 'transit',
            title: this.getTransitLabel(transportMode),
            desc: '前往午餐餐厅',
            duration: transit
          })
          cursor += transit
        }
        scheduled.push({
          time: this.minToTime(cursor),
          type: 'food',
          title: '🍜 午餐',
          desc: '享用当地特色午餐',
          duration: TransportEngine.MEAL_DURATION.lunch,
          mealType: 'lunch'
        })
        cursor += TransportEngine.MEAL_DURATION.lunch
        lunchScheduled = true
        prevType = 'food'

        // 婴幼儿午休（午餐后）
        if (hasInfant && !afternoonRestDone) {
          scheduled.push({
            time: this.minToTime(cursor),
            type: 'rest',
            title: '🛏 午休',
            desc: '小宝宝需要午睡，大家也休息一下',
            duration: 60
          })
          cursor += 60
          afternoonRestDone = true
        }
      }

      // ── 检查是否需要插入晚餐 ──
      if (!dinnerScheduled && cursor >= this.DINNER_WINDOW[0]) {
        const transit = this.getTransitTime(prevType, 'food', transportMode)
        if (transit > 0) {
          scheduled.push({
            time: this.minToTime(cursor),
            type: 'transit',
            title: this.getTransitLabel(transportMode),
            desc: '前往晚餐餐厅',
            duration: transit
          })
          cursor += transit
        }
        scheduled.push({
          time: this.minToTime(cursor),
          type: 'food',
          title: '🍽 晚餐',
          desc: '享用当地特色晚餐',
          duration: TransportEngine.MEAL_DURATION.dinner,
          mealType: 'dinner'
        })
        cursor += TransportEngine.MEAL_DURATION.dinner
        dinnerScheduled = true
        prevType = 'food'
        // 晚餐后不再安排景点，结束当天
        break
      }

      // ── 计算交通时间 ──
      const transitTime = this.getTransitTime(prevType, act.type, transportMode)
      if (transitTime > 0) {
        scheduled.push({
          time: this.minToTime(cursor),
          type: 'transit',
          title: this.getTransitLabel(transportMode),
          desc: `前往${act.title}`,
          duration: transitTime
        })
        cursor += transitTime
      }

      // ── 分配活动时间 ──
      const duration = this.getActivityDuration(act, childAges)
      scheduled.push({
        ...act,
        time: this.minToTime(cursor),
        duration,
        endTime: this.minToTime(cursor + duration)
      })
      cursor += duration
      prevType = act.type
    }

    // 如果活动结束了还没到晚餐时间窗口，也要插入晚餐
    if (!dinnerScheduled && cursor < this.DAY_END) {
      const dinnerStart = Math.max(cursor, this.DINNER_WINDOW[0])
      // 等到晚餐时间
      if (dinnerStart > cursor) {
        scheduled.push({
          time: this.minToTime(cursor),
          type: 'activity',
          title: '🛍 自由活动',
          desc: '逛街、休息或自由探索',
          duration: dinnerStart - cursor
        })
        cursor = dinnerStart
      }
      const transit = this.getTransitTime(prevType, 'food', transportMode)
      if (transit > 0) {
        scheduled.push({
          time: this.minToTime(cursor),
          type: 'transit',
          title: this.getTransitLabel(transportMode),
          desc: '前往晚餐餐厅',
          duration: transit
        })
        cursor += transit
      }
      scheduled.push({
        time: this.minToTime(cursor),
        type: 'food',
        title: '🍽 晚餐',
        desc: '享用当地特色晚餐',
        duration: TransportEngine.MEAL_DURATION.dinner,
        mealType: 'dinner'
      })
      cursor += TransportEngine.MEAL_DURATION.dinner
      prevType = 'food'
    }

    // 返回酒店
    const returnTransit = this.getTransitTime(prevType, 'hotel', transportMode)
    if (returnTransit > 0) {
      scheduled.push({
        time: this.minToTime(cursor),
        type: 'transit',
        title: this.getTransitLabel(transportMode),
        desc: '返回酒店',
        duration: returnTransit
      })
      cursor += returnTransit
    }
    scheduled.push({
      time: this.minToTime(cursor),
      type: 'hotel',
      title: '🏨 返回酒店休息',
      desc: '结束愉快的一天',
      duration: 0
    })

    // 合理性校验
    const totalHours = (cursor - this.DAY_START) / 60
    const warnings = []
    if (totalHours > 12) warnings.push('今日行程较为紧凑，建议适当减少一个景点')

    return {
      ...day,
      activities: scheduled,
      totalHours: totalHours.toFixed(1),
      warnings
    }
  },

  /**
   * 第一天特殊处理：加城市间交通
   */
  scheduleFirstDay(day, params, scheduled) {
    const { transportMode } = params
    const transportLabels = {
      flight: '✈️ 乘坐飞机出发',
      train: '🚄 乘坐高铁出发',
      drive: '🚗 自驾出发',
      recommend: '🚀 出发'
    }

    // 出发时间根据交通方式
    let departureTime, arrivalTime
    if (transportMode === 'flight') {
      departureTime = 7 * 60 + 30   // 07:30 出发去机场
      arrivalTime = 13 * 60          // 预计13:00到达（估算）
    } else if (transportMode === 'train') {
      departureTime = 8 * 60         // 08:00
      arrivalTime = 12 * 60          // 预计12:00到达
    } else {
      departureTime = 7 * 60 + 30
      arrivalTime = 12 * 60
    }

    scheduled.push({
      time: this.minToTime(departureTime),
      type: 'transport',
      title: transportLabels[transportMode] || '🚀 出发',
      desc: '踏上旅途，开始家庭之旅！',
      duration: arrivalTime - departureTime
    })

    scheduled.push({
      time: this.minToTime(arrivalTime),
      type: 'hotel',
      title: '🏨 入住酒店',
      desc: '放下行李，稍作休整',
      duration: 60
    })

    return arrivalTime + 60  // 返回cursor
  },

  /**
   * 获取活动时长
   */
  getActivityDuration(activity, childAges) {
    if (activity.type === 'food') {
      return TransportEngine.MEAL_DURATION[activity.mealType || 'lunch']
    }
    if (activity.type === 'hotel') return 0
    if (activity.type === 'transport') return activity.duration || 60

    const size = activity.size || 'medium'
    return TransportEngine.getAttractionDuration(size, childAges)
  },

  /**
   * 获取两点间交通时间
   */
  getTransitTime(fromType, toType, transportMode) {
    if (fromType === toType && fromType === 'hotel') return 0
    const mode = transportMode === 'drive' ? 'drive' : 'taxi'
    return TransportEngine.calcInCity(mode, fromType, toType)
  },

  /**
   * 获取交通描述标签
   */
  getTransitLabel(transportMode) {
    const labels = {
      drive: '🚗 驾车前往',
      train: '🚕 打车前往',
      flight: '🚕 打车前往',
      recommend: '🚕 打车前往'
    }
    return labels[transportMode] || '🚕 前往'
  },

  /**
   * 分钟数转时间字符串
   * @param {number} minutes
   * @returns {string} "HH:MM"
   */
  minToTime(minutes) {
    const h = Math.floor(minutes / 60) % 24
    const m = minutes % 60
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
  }
}

module.exports = Scheduler
