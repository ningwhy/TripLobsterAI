// pages/itinerary/itinerary.js
Page({
  data: {
    itinerary: null,
    form: null,
    currentDay: 0,
    viewMode: 'card', // card | map
    typeIcons: {
      transport: '✈️',
      attraction: '🏛',
      food: '🍜',
      hotel: '🏨',
      activity: '🎡'
    }
  },

  onLoad(options) {
    const itinerary = JSON.parse(decodeURIComponent(options.data))
    const form = JSON.parse(decodeURIComponent(options.form))
    this.setData({ itinerary, form })

    wx.setNavigationBarTitle({ title: itinerary.title || 'AI行程规划' })
  },

  switchDay(e) {
    this.setData({ currentDay: e.currentTarget.dataset.index })
  },

  switchView(e) {
    this.setData({ viewMode: e.currentTarget.dataset.mode })
  },

  regenerate() {
    wx.showModal({
      title: '重新生成',
      content: '确定要重新生成行程吗？当前行程将被替换。',
      success: (res) => {
        if (res.confirm) {
          wx.redirectTo({
            url: `/pages/loading/loading?data=${encodeURIComponent(JSON.stringify(this.data.form))}`
          })
        }
      }
    })
  },

  saveItinerary() {
    // 保存到本地存储
    const saved = wx.getStorageSync('savedItineraries') || []
    saved.unshift({
      ...this.data.itinerary,
      savedAt: new Date().toLocaleDateString('zh-CN')
    })
    wx.setStorageSync('savedItineraries', saved.slice(0, 10)) // 最多保存10个

    wx.showToast({
      title: '行程已保存！',
      icon: 'success'
    })
  }
})
