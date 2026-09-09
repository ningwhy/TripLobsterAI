// pages/loading/loading.js
const app = getApp()
const Scheduler = require('../../utils/scheduler')

Page({
  data: { stepIndex: -1 },

  onLoad(options) {
    const form = JSON.parse(decodeURIComponent(options.data))
    this.form = form
    this.startGenerate()
  },

  startGenerate() {
    let step = 0
    const timer = setInterval(() => {
      this.setData({ stepIndex: step })
      step++
      if (step >= 4) clearInterval(timer)
    }, 1200)
    this.callAI()
  },

  buildPrompt(form) {
    const childInfo = form.children > 0
      ? `${form.children}个小孩（年龄段：${(form.childAges || []).join('、') || '未填写'}）`
      : '无小孩'

    const transportLabels = {
      flight: '飞机', train: '高铁', drive: '自驾', recommend: 'AI推荐'
    }
    const styleLabels = {
      compact: '紧凑型（每天4-5个景点）',
      leisure: '悠闲型（每天2-3个景点）',
      'theme-kids': '亲子主题（游乐园/动物园优先）',
      'theme-food': '美食主题（餐厅/夜市优先）',
      nature: '自然风光（山水/公园）',
      culture: '历史文化（古迹/博物馆）'
    }

    return `你是一位专业的家庭旅游规划师。请规划以下家庭旅游行程骨架。

出发地：${form.departure}
目的地：${form.destination}
出行天数：${form.days}天
交通方式：${transportLabels[form.transportMode] || '不限'}
出行人员：${form.adults}个大人，${childInfo}
预算：${form.budget}
旅行风格：${styleLabels[form.travelStyle] || '悠闲型'}
特别要求：${form.preference || '无'}

注意：
1. 只输出景点/活动列表，不需要安排时间（时间由系统计算）
2. 不需要安排早餐/午餐/晚餐（系统自动插入）
3. 根据旅行风格控制每天景点数量
4. 景点标注size（large/medium/small/theme_park/museum）
5. 景区内部标注scenicType（large_natural/mountain/ancient_town/theme_park/urban_park）

只返回JSON，格式如下：
{
  "title": "行程标题",
  "summary": "行程简介（50字以内）",
  "days": [
    {
      "day": 1,
      "theme": "今日主题",
      "activities": [
        {
          "type": "attraction",
          "title": "景点名称",
          "desc": "景点描述（30字以内）",
          "size": "medium",
          "scenicType": "urban_park",
          "tips": "实用小贴士",
          "cost": "费用参考"
        }
      ]
    }
  ]
}`
  },

  callAI() {
    const prompt = this.buildPrompt(this.form)
    const { apiKey, apiBase, model } = app.globalData

    wx.request({
      url: `${apiBase}/chat/completions`,
      method: 'POST',
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      data: {
        model,
        messages: [{ role: 'user', content: prompt }],
        temperature: 0.7,
        max_tokens: 4000
      },
      timeout: 60000,
      success: (res) => {
        if (res.statusCode === 200) {
          const content = res.data.choices[0].message.content
          try {
            const jsonMatch = content.match(/\{[\s\S]*\}/)
            if (jsonMatch) {
              const skeleton = JSON.parse(jsonMatch[0])
              // 用调度器排时间
              const itinerary = Scheduler.schedule(skeleton, this.form)
              setTimeout(() => {
                wx.redirectTo({
                  url: `/pages/itinerary/itinerary?data=${encodeURIComponent(JSON.stringify(itinerary))}&form=${encodeURIComponent(JSON.stringify(this.form))}`
                })
              }, 800)
            } else {
              this.handleError('解析行程失败，请重试')
            }
          } catch (e) {
            console.error('Parse error:', e)
            this.handleError('解析行程失败，请重试')
          }
        } else {
          this.handleError('AI服务暂时不可用，请重试')
        }
      },
      fail: () => this.handleError('网络错误，请检查网络后重试')
    })
  },

  handleError(msg) {
    wx.showModal({
      title: '出错了',
      content: msg,
      showCancel: false,
      success: () => wx.navigateBack()
    })
  }
})
