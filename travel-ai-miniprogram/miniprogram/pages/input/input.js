// pages/input/input.js - 分步引导式输入
Page({
  data: {
    // 当前步骤 0-7
    step: 0,
    totalSteps: 7,

    // 表单数据
    form: {
      destination: '',
      departure: '',
      transportMode: '', // train | flight | drive | recommend
      driverCount: 1,    // 自驾：司机人数
      useHighway: true,  // 自驾：是否走高速
      days: 5,
      adults: 2,
      children: 0,
      childAges: [],     // ['0-3', '3-6', '6-12']
      budget: '',
      travelStyle: '',   // compact | leisure | theme-kids | theme-food | nature | culture
      preference: ''
    },

    // 热门目的地
    hotDestinations: ['云南', '西藏', '三亚', '北京', '成都', '厦门', '桂林', '黄山'],

    // 交通方式选项
    transportOptions: [
      { value: 'train', icon: '🚄', label: '高铁', desc: '稳定舒适，适合6h内' },
      { value: 'flight', icon: '✈️', label: '飞机', desc: '速度最快，适合远途' },
      { value: 'drive', icon: '🚗', label: '自驾', desc: '自由灵活，适合周边' },
      { value: 'recommend', icon: '🤔', label: '帮我推荐', desc: '根据距离AI智能推荐' }
    ],

    // 旅行风格
    styleOptions: [
      { value: 'compact', icon: '🏃', label: '紧凑型', desc: '每天4-5个景点，多看多走' },
      { value: 'leisure', icon: '😌', label: '悠闲型', desc: '每天2-3个景点，慢慢体验' },
      { value: 'theme-kids', icon: '🎠', label: '亲子主题', desc: '游乐园/动物园优先' },
      { value: 'theme-food', icon: '🍜', label: '美食主题', desc: '餐厅/夜市/特色小吃' },
      { value: 'nature', icon: '🏔', label: '自然风光', desc: '山水/公园/户外' },
      { value: 'culture', icon: '🏛', label: '历史文化', desc: '古迹/博物馆/古镇' }
    ],

    // 预算选项
    budgetOptions: [
      { value: '5千以内', label: '5千以内' },
      { value: '1万左右', label: '1万左右' },
      { value: '2万左右', label: '2万左右' },
      { value: '5万以上', label: '5万以上' }
    ],

    // 天数选项
    daysOptions: [3, 4, 5, 6, 7],

    // 小孩年龄段
    childAgeOptions: [
      { value: '0-3', label: '0-3岁', desc: '婴幼儿', icon: '👶' },
      { value: '3-6', label: '3-6岁', desc: '学龄前', icon: '🧒' },
      { value: '6-12', label: '6-12岁', desc: '小学生', icon: '👦' }
    ],

    // 确认页展示数据
    confirmData: null
  },

  onLoad() {
    // 自动定位出发地
    this.autoLocate()
  },

  autoLocate() {
    wx.getLocation({
      type: 'gcj02',
      success: () => {
        // 实际项目接入逆地理编码，这里先用默认值
        this.setData({ 'form.departure': '当前城市' })
      },
      fail: () => {
        // 定位失败不影响流程
      }
    })
  },

  // ─── 步骤导航 ───

  nextStep() {
    const { step, form } = this.data
    // 校验当前步骤
    if (!this.validateStep(step)) return

    // 跳过逻辑：非自驾跳过自驾详情
    let next = step + 1
    if (step === 2 && form.transportMode !== 'drive') {
      next = 4 // 跳过自驾详情步骤
    }
    // 无小孩跳过小孩年龄
    if (step === 5 && form.children === 0) {
      next = 6
    }

    if (next >= this.data.totalSteps) {
      this.showConfirm()
    } else {
      this.setData({ step: next })
    }
  },

  prevStep() {
    const { step, form } = this.data
    let prev = step - 1
    // 反向跳过逻辑
    if (step === 4 && form.transportMode !== 'drive') {
      prev = 2
    }
    if (step === 6 && form.children === 0) {
      prev = 4
    }
    if (prev < 0) return
    this.setData({ step: prev })
  },

  validateStep(step) {
    const { form } = this.data
    const checks = {
      0: { field: form.destination, msg: '请填写目的地' },
      1: { field: form.departure, msg: '请填写出发地' },
      2: { field: form.transportMode, msg: '请选择出行方式' },
      4: { field: form.days, msg: '请选择天数' },
      6: { field: form.budget, msg: '请选择预算' },
      7: { field: form.travelStyle, msg: '请选择旅行风格' }  // 注：实际step=7但totalSteps=7，会触发showConfirm
    }
    if (checks[step] && !checks[step].field) {
      wx.showToast({ title: checks[step].msg, icon: 'none' })
      return false
    }
    return true
  },

  // ─── 各步骤输入处理 ───

  onDestinationInput(e) {
    this.setData({ 'form.destination': e.detail.value })
  },

  onDepartureInput(e) {
    this.setData({ 'form.departure': e.detail.value })
  },

  selectHotDest(e) {
    const dest = e.currentTarget.dataset.dest
    this.setData({ 'form.destination': dest })
  },

  selectTransport(e) {
    const mode = e.currentTarget.dataset.value
    this.setData({ 'form.transportMode': mode })
    // 自动进入下一步
    setTimeout(() => this.nextStep(), 300)
  },

  selectDriverCount(e) {
    this.setData({ 'form.driverCount': e.currentTarget.dataset.count })
  },

  toggleHighway(e) {
    this.setData({ 'form.useHighway': e.detail.value })
  },

  selectDays(e) {
    this.setData({ 'form.days': e.currentTarget.dataset.days })
  },

  changePeople(e) {
    const { type, op } = e.currentTarget.dataset
    let val = this.data.form[type]
    if (op === 'plus') val = Math.min(val + 1, 8)
    if (op === 'minus') val = Math.max(val - 1, type === 'adults' ? 1 : 0)
    this.setData({ [`form.${type}`]: val })
  },

  toggleChildAge(e) {
    const age = e.currentTarget.dataset.age
    let ages = [...this.data.form.childAges]
    const idx = ages.indexOf(age)
    if (idx > -1) ages.splice(idx, 1)
    else ages.push(age)
    this.setData({ 'form.childAges': ages })
  },

  selectBudget(e) {
    this.setData({ 'form.budget': e.currentTarget.dataset.value })
    setTimeout(() => this.nextStep(), 300)
  },

  selectStyle(e) {
    const style = e.currentTarget.dataset.value
    this.setData({ 'form.travelStyle': style })
    setTimeout(() => this.showConfirm(), 300)
  },

  onPreferenceInput(e) {
    this.setData({ 'form.preference': e.detail.value })
  },

  // ─── 确认页 ───

  showConfirm() {
    const { form } = this.data
    const transportLabels = {
      train: '🚄 高铁', flight: '✈️ 飞机',
      drive: '🚗 自驾', recommend: '🤔 AI推荐'
    }
    const styleLabels = {
      compact: '🏃 紧凑型', leisure: '😌 悠闲型',
      'theme-kids': '🎠 亲子主题', 'theme-food': '🍜 美食主题',
      nature: '🏔 自然风光', culture: '🏛 历史文化'
    }
    const childAgeLabels = { '0-3': '婴幼儿', '3-6': '学龄前', '6-12': '小学生' }

    const confirmData = {
      route: `${form.departure} → ${form.destination}`,
      transport: transportLabels[form.transportMode] || '',
      days: `${form.days}天${form.days - 1}夜`,
      people: form.children > 0
        ? `${form.adults}大人 + ${form.children}小孩（${form.childAges.map(a => childAgeLabels[a]).join('、')}）`
        : `${form.adults}位大人`,
      budget: `💰 ${form.budget}`,
      style: styleLabels[form.travelStyle] || '',
      preference: form.preference || '无特别要求'
    }
    this.setData({ step: 99, confirmData })
  },

  editForm() {
    this.setData({ step: 0 })
  },

  generateItinerary() {
    wx.navigateTo({
      url: `/pages/loading/loading?data=${encodeURIComponent(JSON.stringify(this.data.form))}`
    })
  }
})
