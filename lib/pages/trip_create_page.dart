import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../models/trip_models.dart';
import '../services/amap_service.dart';
import '../utils/wizard_step.dart';
import '../widgets/create_wizard/step_indicator.dart';
import '../widgets/create_wizard/step_option_card.dart';
import '../widgets/create_wizard/transport_arrival.dart';
import '../widgets/create_wizard/wizard_colors.dart';
import '../widgets/transport_select_modal.dart';
import 'location_search_page.dart';
import 'transport_preference_page.dart';

class TripCreatePage extends StatefulWidget {
  final Trip? trip; // 如果传入trip则为编辑模式

  const TripCreatePage({super.key, this.trip});

  @override
  State<TripCreatePage> createState() => _TripCreatePageState();
}

class _TripCreatePageState extends State<TripCreatePage> {
  final _nameController = TextEditingController();
  final _amapService = AmapService();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 2));
  List<Location> _locations = [];
  // 存储每段路程的路线信息
  final Map<String, AmapRoute?> _routeInfo = {};
  TripMode _tripMode = TripMode.pureTransit;
  TransportType _intercityPref = TransportType.flight;
  TransportType _intraCityPref = TransportType.taxi;
  /// 地点归属天（locationId → dayNumber）
  final Map<String, int> _dayOfLocation = {};
  bool get _isEditing => widget.trip != null;

  /// 当前步（0-based）。
  ///
  /// 所有表单数据都存在 State 字段 / `TextEditingController` / `_locations` 里，
  /// 切步只换 pane，**不重建、不清空**任何数据 → 跨步不丢。
  int _step = 0;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      // 加载现有行程数据
      _nameController.text = widget.trip!.name;
      _startDate = widget.trip!.startDate;
      _endDate = widget.trip!.endDate;
      _tripMode = widget.trip!.tripMode;
      _locations = List.from(widget.trip!.allLocations);
      for (final day in widget.trip!.days) {
        for (final loc in day.locations) {
          _dayOfLocation[loc.id] = day.dayNumber;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final homeLocation = provider.homeLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑行程' : '创建行程'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _showBackDialog(),
        ),
      ),
      body: Column(
        children: [
          // 顶部步骤圆点（原型 :119-124），点击可直接跳步
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: WizardStepIndicator(
              current: _step,
              total: kWizardStepCount,
              onStepTap: _goToStep,
            ),
          ),
          Expanded(
            // IndexedStack + 状态索引：4 个 pane 常驻 Element 树，
            // 外层 Offstage 让非当前步不参与布局/命中测试（也让 widget 测试的
            // finder 只看到当前步，避免同名文案重复匹配）。
            child: IndexedStack(
              index: _step,
              sizing: StackFit.expand,
              children: [
                Offstage(offstage: _step != 0, child: _buildBasicsStep()),
                Offstage(offstage: _step != 1, child: _buildDatesStep()),
                Offstage(
                  offstage: _step != 2,
                  child: _buildTransportStep(homeLocation),
                ),
                Offstage(offstage: _step != 3, child: _buildConfirmStep()),
              ],
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 四个 pane（字段与文案逐项沿用原单页长表单，不丢、不加业务字段）
  // ---------------------------------------------------------------------------

  /// 第 1 步：行程名称 + 行程类型。
  ///
  /// ⚠️ 现有页面**没有**人数 / 房型 / 预算等输入控件，按「不加字段」红线
  ///    不凭空新增；本步只放原有 TextField 与原「行程类型」三个选项。
  Widget _buildBasicsStep() {
    return ListView(
      key: const Key('wizardPane0'),
      padding: const EdgeInsets.all(16),
      children: [
        // Trip Name
        TextField(
          key: const Key('tripNameField'),
          controller: _nameController,
          decoration: InputDecoration(
            hintText: '请输入行程名称',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 行程类型（原 ChoiceChip 三选项，换成设计图 .opt-card 单选卡）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '行程类型',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              StepOptionGroup(
                optionKeyPrefix: 'tripTypeOption',
                options: const [
                  StepOptionItem(title: '🚗 纯自驾'),
                  StepOptionItem(title: '🚄 纯公共交通'),
                  StepOptionItem(title: '🛬 公交+落地租车'),
                ],
                // 选项顺序与 TripMode.values 顺序一致：
                // pureDrive / pureTransit / transitPlusRental
                selectedIndex: _tripMode.index,
                onSelected: (index) {
                  setState(() {
                    _tripMode = TripMode.values[index];
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 第 2 步：起止日期（沿用 `_buildDatePicker` 的 showDatePicker 口径）。
  Widget _buildDatesStep() {
    return ListView(
      key: const Key('wizardPane1'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDatePicker(
                key: const Key('startDatePicker'),
                label: '开始日期',
                date: _startDate,
                onChanged: (date) {
                  setState(() {
                    _startDate = date;
                    if (_endDate.isBefore(_startDate)) {
                      _endDate = _startDate;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDatePicker(
                key: const Key('endDatePicker'),
                label: '结束日期',
                date: _endDate,
                onChanged: (date) => setState(() {
                  _endDate = date;
                  // 沿用「开始日期」选择器既有纠正口径：结束日不得早于开始日。
                  if (_endDate.isBefore(_startDate)) {
                    _endDate = _startDate;
                  }
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${_endDate.difference(_startDate).inDays + 1}天行程',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  /// 第 3 步：交通偏好 / 跨城同城选项 + 地点时间线。
  Widget _buildTransportStep(HomeLocation? homeLocation) {
    return ListView(
      key: const Key('wizardPane2'),
      padding: const EdgeInsets.all(16),
      children: [
        // Home Location
        if (homeLocation != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: const Icon(Icons.home, color: Colors.white),
              title: const Text(
                '我的家',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
              subtitle: Text(
                homeLocation.address,
                style: const TextStyle(color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit, color: Colors.white70, size: 18),
              onTap: () async {
                // 【async gap】`TripProvider` 在 `await`（地点搜索页）之前捕获：
                // 搜索页停留期间本页面可能被 pop，届时的 `context` 已失效。
                final provider = context.read<TripProvider>();
                final result = await Navigator.push<Location>(
                  context,
                  MaterialPageRoute(builder: (_) => const LocationSearchPage()),
                );
                if (result != null) {
                  final newHome = HomeLocation(
                    id: 'home',
                    name: result.name,
                    address: result.address,
                    latitude: result.latitude ?? 0,
                    longitude: result.longitude ?? 0,
                    city: result.city,
                    district: result.district,
                  );
                  await provider.setHomeLocation(newHome);
                }
              },
            ),
          ),
          // 从家出发按钮
          if (_locations.isEmpty || _locations.first.type != LocationType.home)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  final homeLoc = Location(
                    id: 'home_${DateTime.now().millisecondsSinceEpoch}',
                    name: homeLocation.name,
                    address: homeLocation.address,
                    latitude: homeLocation.latitude,
                    longitude: homeLocation.longitude,
                    city: homeLocation.city,
                    district: homeLocation.district,
                    type: LocationType.home,
                  );
                  setState(() {
                    _locations.insert(0, homeLoc);
                  });
                },
                icon: const Icon(Icons.home, size: 18),
                label: const Text('从家出发'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],

        // 交通偏好设置按钮
        Container(
          margin: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () async {
              // 【async gap】两件事都必须在 `await` 之前完成：
              //
              // 1. `ScaffoldMessenger.of(context)` 提前捕获 —— messenger 挂在
              //    MaterialApp 上（远高于本页），本页被 pop 后它依然有效；
              //    而 await 之后再 `ScaffoldMessenger.of(context)`，若那时
              //    context 已失效就会抛异常。
              // 2. await 之后先 `if (!mounted) return;` 再 `setState` ——
              //    旧写法 `setState` 在任何守卫**之前**执行，页面已销毁时
              //    直接抛 setState-after-dispose，是本处最严重的一条。
              final messenger = ScaffoldMessenger.of(context);
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(
                  builder: (_) => TransportPreferencePage(
                    initialMode: _tripMode,
                    initialIntercity: _intercityPref,
                    initialIntraCity: _intraCityPref,
                  ),
                ),
              );
              // 页面已销毁时不再改动本页面 State（用户偏好已带回，属预期行为）
              if (!mounted) return;
              if (result != null) {
                setState(() {
                  _tripMode = result['tripMode'] ?? _tripMode;
                  _intercityPref = result['bigTransport'] ?? _intercityPref;
                  _intraCityPref = result['smallTransport'] ?? _intraCityPref;
                });
                messenger.showSnackBar(
                  const SnackBar(content: Text('交通偏好已设置')),
                );
              }
            },
            icon: const Icon(Icons.directions_car, size: 18),
            label: Text(_tripModeLabel),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 跨城 / 同城（原「行程类型」容器下半部分，ChoiceChip 文案原样保留）
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_tripMode != TripMode.pureDrive) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                        padding: EdgeInsets.only(top: 8), child: Text('跨城: ')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            label: const Text('✈️ 飞机'),
                            selected: _intercityPref == TransportType.flight,
                            onSelected: (_) => setState(
                                () => _intercityPref = TransportType.flight),
                          ),
                          ChoiceChip(
                            label: const Text('🚄 高铁'),
                            selected:
                                _intercityPref == TransportType.highSpeedTrain,
                            onSelected: (_) => setState(() => _intercityPref =
                                TransportType.highSpeedTrain),
                          ),
                          ChoiceChip(
                            label: const Text('🚌 大巴'),
                            selected: _intercityPref == TransportType.bus,
                            onSelected: (_) => setState(
                                () => _intercityPref = TransportType.bus),
                          ),
                          ChoiceChip(
                            label: const Text('⛴️ 轮船'),
                            selected: _intercityPref == TransportType.ship,
                            onSelected: (_) => setState(
                                () => _intercityPref = TransportType.ship),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                        padding: EdgeInsets.only(top: 8), child: Text('同城: ')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            label: const Text('🚕 打车'),
                            selected: _intraCityPref == TransportType.taxi,
                            onSelected: (_) => setState(
                                () => _intraCityPref = TransportType.taxi),
                          ),
                          ChoiceChip(
                            label: const Text('🚇 地铁'),
                            selected: _intraCityPref == TransportType.subway,
                            onSelected: (_) => setState(
                                () => _intraCityPref = TransportType.subway),
                          ),
                          ChoiceChip(
                            label: const Text('🚌 公交'),
                            selected: _intraCityPref == TransportType.bus,
                            onSelected: (_) => setState(
                                () => _intraCityPref = TransportType.bus),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('纯自驾行程无交通枢纽，长距离将自动提示服务区',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Timeline
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '行程时间线',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: _addLocation,
                    icon: const Icon(Icons.add_circle),
                    color: const Color(0xFF4A90D9),
                  ),
                ],
              ),
              const Divider(),

              // Hint
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb, color: Color(0xFF4A90D9), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '跨城交通自动触发：添加不同城市地点时，系统会自动弹出交通选择',
                        style: TextStyle(fontSize: 12, color: Color(0xFF4A90D9)),
                      ),
                    ),
                  ],
                ),
              ),

              // Locations
              if (_locations.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('点击 + 添加地点'),
                  ),
                )
              else
                ...List.generate(_locations.length, (index) {
                  return _buildLocationItem(index);
                }),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  /// 第 4 步：确认摘要 + 可展开的分天完整时间线（对应原型 :236-282 `<details>`）。
  ///
  /// ⛔ 所有展示值都来自用户已填/已有数据；没有可靠数据就不编造时刻、班次、
  ///    地点或价格。空天沿用现有时间线空态文案「点击 + 添加地点」。
  Widget _buildConfirmStep() {
    final int dayCount = _endDate.difference(_startDate).inDays + 1;
    final int fallbackDay = _isEditing ? dayCount : 1;

    return ListView(
      key: const Key('wizardPane3'),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nameController.text,
                key: const Key('confirmName'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_startDate.month}/${_startDate.day} - ${_endDate.month}/${_endDate.day} · $dayCount天行程',
                key: const Key('confirmDates'),
                style: const TextStyle(fontSize: 13, color: kWizardInk2),
              ),
              const SizedBox(height: 6),
              Text(
                _tripModeLabel,
                key: const Key('confirmMode'),
                style: const TextStyle(fontSize: 13, color: kWizardInk2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('confirmTimeline'),
              initiallyExpanded: false,
              title: const Text(
                '行程时间线',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (var i = 0; i < dayCount; i++)
                  _buildDaySummary(
                    dayNumber: i + 1,
                    date: _startDate.add(Duration(days: i)),
                    dayCount: dayCount,
                    fallbackDay: fallbackDay,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDaySummary({
    required int dayNumber,
    required DateTime date,
    required int dayCount,
    required int fallbackDay,
  }) {
    final List<Location> dayLocations = _locations
        .where((l) =>
            ((_dayOfLocation[l.id] ?? fallbackDay).clamp(1, dayCount)) ==
            dayNumber)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            '第$dayNumber天 · ${date.month}/${date.day}',
            key: Key('confirmDay$dayNumber'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kWizardPurpleDeep,
            ),
          ),
        ),
        if (dayLocations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '点击 + 添加地点',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          )
        else
          ...dayLocations.map(_buildSummaryLocationRow),
      ],
    );
  }

  Widget _buildSummaryLocationRow(Location location) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            location.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            location.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: kWizardInk2),
          ),
          if (location.transport != null) ...[
            const SizedBox(height: 2),
            Text(
              _transportSummary(location.transport!),
              style: const TextStyle(fontSize: 11, color: kWizardInk2),
            ),
          ],
        ],
      ),
    );
  }

  /// 时间线摘要里的交通行：只用已有字段，缺失显示 `--`（沿用 `_buildLocationItem`
  /// 的既有口径，不推算、不兜底）。
  String _transportSummary(Transport transport) {
    final buffer = StringBuffer(
      '${transport.departureTime ?? '--'} → ${transport.arrivalTime ?? '--'}',
    );
    if (transport.flightNumber != null &&
        transport.flightNumber!.isNotEmpty) {
      buffer.write(' ${transport.flightNumber}');
    }
    if (transport.durationMinutes != null) {
      buffer.write(' (${_formatDuration(transport.durationMinutes!)})');
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // 底部导航 / 步进
  // ---------------------------------------------------------------------------

  Widget _buildBottomNav() {
    final bool isLast = _step == kWizardStepCount - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('wizardPrevButton'),
              // 第 1 步上一步禁用（原型 :380 `prevBtn.disabled = (step === 1)`）
              onPressed:
                  _step == 0 ? null : () => setState(() => _step = prevIndex(_step)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(kPrevLabel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: isLast
                ? ElevatedButton(
                    key: const Key('wizardNextButton'),
                    onPressed: _saveTrip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kWizardPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(actionLabel(_step, kWizardStepCount)),
                  )
                : OutlinedButton(
                    key: const Key('wizardNextButton'),
                    onPressed: _onNext,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(actionLabel(_step, kWizardStepCount)),
                  ),
          ),
        ],
      ),
    );
  }

  /// 圆点直接跳步（原型 :419-426）。只切 pane，不动任何表单数据。
  void _goToStep(int index) {
    final int target = index < 0
        ? 0
        : (index >= kWizardStepCount ? kWizardStepCount - 1 : index);
    if (target == _step) return;
    setState(() => _step = target);
  }

  /// 「下一步」/「生成行程」。
  void _onNext() {
    if (_step == kWizardStepCount - 1) {
      // 最后一步：触发入口从原顶栏「保存」移到第 4 步「生成行程」。
      _saveTrip();
      return;
    }

    // 旧行程数据可能带非法日期区间：沿用「开始日期」选择器既有纠正口径。
    // 这不是兜底填充业务数据，只是把结束日对齐到用户已选的开始日。
    if (_endDate.isBefore(_startDate)) {
      setState(() => _endDate = _startDate);
    }

    if (!canAdvance(
      _step,
      kWizardStepCount,
      name: _nameController.text,
      startDate: _startDate,
      endDate: _endDate,
    )) {
      // 名称为空是唯一可由 UI 触发的拦截；沿用 `_saveTrip` 原有提示文案，
      // 不新增任何文案。
      if (_nameController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入行程名称')),
        );
      }
      return;
    }
    setState(() => _step = nextIndex(_step, kWizardStepCount));
  }

  // ---------------------------------------------------------------------------
  // 原有方法（语义保持不变）
  // ---------------------------------------------------------------------------

  void _showBackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存行程?'),
        content: const Text('是否保存当前行程?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(this.context);
            },
            child: const Text('不保存'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _saveTrip();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF4A90D9)),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker({
    Key? key,
    required String label,
    required DateTime date,
    required ValueChanged<DateTime> onChanged,
  }) {
    return InkWell(
      key: key,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  '${date.month}/${date.day}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationItem(int index) {
    final location = _locations[index];

    // 检查是否需要显示交通信息（只要有交通信息就显示）
    final showTransport = index > 0 && location.transport != null;
    // 简化：只要有交通信息就显示，不再严格判断跨城
    // 因为用户手动选择了交通方式，应该显示

    return Column(
      children: [
        // 显示交通信息（有交通信息时显示）
        if (showTransport)
          Container(
            margin: const EdgeInsets.only(left: 20, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _transportIcon(location.transport!.type),
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                // 显示出发时间 -> 到达时间
                Text(
                  '${location.transport!.departureTime ?? '--'} → ${location.transport!.arrivalTime ?? '--'}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
                // 显示班次/车次
                if (location.transport!.flightNumber != null && location.transport!.flightNumber!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    location.transport!.flightNumber!,
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
                // 显示时长
                if (location.transport!.durationMinutes != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${_formatDuration(location.transport!.durationMinutes!)})',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ],
              ],
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getTypeColor(location.type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getTypeIcon(location.type),
              color: _getTypeColor(location.type),
              size: 20,
            ),
          ),
          title: Text(location.name),
          subtitle: Text(
            location.address,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: () {
              setState(() {
                _locations.removeAt(index);
              });
            },
          ),
        ),
      ],
    );
  }

  void _addLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );

    if (result != null && result is Location) {
      // 选择归属天（点+线模型：每个点归属某一天）
      await _pickDayFor(result);

      // 如果有上一个地点，先计算路线
      if (_locations.isNotEmpty) {
        final previousLocation = _locations.last;

        // 判断是否同城
        final isInterCity = !previousLocation.isSameCity(result);

        // 显示加载中
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(isInterCity ? '正在计算跨城路线...' : '正在计算同城路线...'),
                ],
              ),
              duration: const Duration(seconds: 10),
            ),
          );
        }

        // 计算路线：自驾类用驾车路线；纯公交模式同城优先公交路线
        if (previousLocation.longitude != null && previousLocation.latitude != null &&
            result.longitude != null && result.latitude != null) {
          AmapRoute? route;
          if (_tripMode == TripMode.pureTransit && !isInterCity) {
            route = await _amapService.transitRoute(
              originLng: previousLocation.longitude!,
              originLat: previousLocation.latitude!,
              destinationLng: result.longitude!,
              destinationLat: result.latitude!,
              city: previousLocation.cityName,
            );
          }
          route ??= await _amapService.drivingRoute(
            originLng: previousLocation.longitude!,
            originLat: previousLocation.latitude!,
            destinationLng: result.longitude!,
            destinationLat: result.latitude!,
          );

          // 存储路线信息
          final routeKey = '${previousLocation.id}_${result.id}';
          _routeInfo[routeKey] = route;

          // 更新交通时间
          if (route != null && route.paths.isNotEmpty) {
            result.transportMinutes = route.duration;
            // 保存默认交通方式（根据同城/跨城设置）
            result.transport = Transport(
              type: _tripMode == TripMode.pureDrive
                  ? TransportType.selfDrive
                  : (isInterCity ? _intercityPref : _intraCityPref),
              scope: isInterCity ? TransportScope.intercity : TransportScope.intraCity,
              durationMinutes: route.duration,
              distance: route.distance.toDouble(),
            );
          }

          // 关闭加载提示
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        } else {
          // 关闭加载提示
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        }
      }

      setState(() {
        _locations.add(result);
      });

      // 跨城时弹出交通选择弹窗
      if (_locations.length > 1) {
        final previousLocation = _locations[_locations.length - 2];
        if (!previousLocation.isSameCity(result)) {
          // 延迟一下，让UI先更新
          Future.delayed(const Duration(milliseconds: 100), () {
            _showTransportModal(previousLocation, result);
          });
        }
      }
    }
  }

  void _showTransportModal(Location from, Location to) {
    // 获取已计算的路线信息
    final routeKey = '${from.id}_${to.id}';
    final routeInfo = _routeInfo[routeKey];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransportSelectModal(
        fromLocation: from,
        toLocation: to,
        routeInfo: routeInfo,
        onConfirm: (transport) {
          setState(() {
            // 添加交通信息到目的地：**保留弹窗返回的整个原对象**
            // （price / isFixed / estimated 等字段一个都不能丢）。
            to.transport = transport;

            // 重算到达时间：内部用未 mod 1440 的分钟数，跨午夜显示「次日 HH:mm」；
            // 出发时刻无法解析时不写到达时间（不编造）。
            // ⛔ 不重建 Transport —— 旧实现重建时丢了 price/isFixed/estimated。
            applyTransportArrivalTime(transport);
          });
        },
      ),
    );
  }

  IconData _transportIcon(TransportType type) {
    switch (type) {
      case TransportType.flight:
        return Icons.flight;
      case TransportType.highSpeedTrain:
      case TransportType.train:
        return Icons.train;
      case TransportType.ship:
        return Icons.directions_boat;
      case TransportType.selfDrive:
        return Icons.directions_car;
      case TransportType.taxi:
        return Icons.local_taxi;
      case TransportType.subway:
        return Icons.subway;
      case TransportType.walk:
        return Icons.directions_walk;
      default:
        return Icons.directions_bus;
    }
  }

  IconData _getTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return Icons.hotel;
      case LocationType.attraction:
        return Icons.attractions;
      case LocationType.restaurant:
        return Icons.restaurant;
      case LocationType.shopping:
        return Icons.shopping_bag;
      case LocationType.transport:
        return Icons.directions_bus;
      default:
        return Icons.place;
    }
  }

  /// 格式化时长显示
  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes分钟';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) {
        return '$hours小时';
      }
      return '$hours小时$mins分钟';
    }
  }

  Color _getTypeColor(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return const Color(0xFF9B59B6);
      case LocationType.attraction:
        return const Color(0xFFE74C3C);
      case LocationType.restaurant:
        return const Color(0xFFF39C12);
      case LocationType.shopping:
        return const Color(0xFF2ECC71);
      case LocationType.transport:
        return const Color(0xFF4A90D9);
      default:
        return const Color(0xFF95A5A6);
    }
  }

  String get _tripModeLabel {
    switch (_tripMode) {
      case TripMode.pureDrive:
        return '🚗 纯自驾';
      case TripMode.transitPlusRental:
        return '🛬 公交+落地租车';
      case TripMode.pureTransit:
        final big = _intercityPref == TransportType.flight
            ? '✈️ 飞机'
            : (_intercityPref == TransportType.ship
                ? '⛴️ 轮船'
                : (_intercityPref == TransportType.bus ? '🚌 大巴' : '🚄 高铁'));
        final small = _intraCityPref == TransportType.subway
            ? '🚇 地铁'
            : (_intraCityPref == TransportType.bus ? '🚌 公交' : '🚕 打车');
        return '$big + $small';
    }
  }

  Future<void> _pickDayFor(Location loc) async {
    final dayCount = _endDate.difference(_startDate).inDays + 1;
    if (dayCount <= 1) {
      _dayOfLocation[loc.id] = 1;
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('添加到哪一天？', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            ...List.generate(dayCount, (i) {
              final date = _startDate.add(Duration(days: i));
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE2F3DA),
                  child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF4CA84A), fontWeight: FontWeight.bold)),
                ),
                title: Text('第${i + 1}天 · ${date.month}/${date.day}'),
                onTap: () => Navigator.pop(ctx, i + 1),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    _dayOfLocation[loc.id] = picked ?? 1;
  }

  /// 只比年月日：`DateTime` 带时分秒，直接 `==` 会把"同一天不同时刻"判为不同。
  bool _isSameYmd(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _saveTrip() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入行程名称')),
      );
      return;
    }

    // 按“地点归属天”构建天数（点+线模型：点归属到天，线连接点）
    final dayCount = _endDate.difference(_startDate).inDays + 1;
    final fallbackDay = _isEditing ? dayCount : 1;

    // ---- T04：日期/跨日归属变化 → 清空旧日期的营业事实 ----
    //
    // 营业时间是**日期感知**的（服务端 `parseOpenTime(poi, dateStr)` 按具体日期解析）：
    // 出发日改了、或地点从第 1 天挪到第 2 天，旧结论就**不再是那条日期的事实**。
    // 沿用它就是拿旧日期的数据冒充新日期 —— 属于编造，违反三铁律。
    //
    // ⛔ 清空后走预览页 CH-09 日级披露；**不联网补查、不回填默认营业时间**
    //    （补查要另立数据源与配额契约，本轮不做）。
    final previousDayOf = <String, int>{};
    final startDateChanged = _isEditing && !_isSameYmd(widget.trip!.startDate, _startDate);
    if (_isEditing) {
      for (final day in widget.trip!.days) {
        for (final loc in day.locations) {
          previousDayOf[loc.id] = day.dayNumber;
        }
      }
    }

    final days = <TripDay>[];
    for (var i = 0; i < dayCount; i++) {
      final dayNumber = i + 1;
      days.add(TripDay(
        date: _startDate.add(Duration(days: i)),
        dayNumber: dayNumber,
        locations: _locations
            .where((l) => ((_dayOfLocation[l.id] ?? fallbackDay).clamp(1, dayCount)) == dayNumber)
            .toList(),
      ));
    }

    for (final loc in _locations) {
      final newDay = (_dayOfLocation[loc.id] ?? fallbackDay).clamp(1, dayCount);
      final oldDay = previousDayOf[loc.id];
      final dayChanged = oldDay != null && oldDay != newDay;
      if (startDateChanged || dayChanged) {
        loc.clearOpenHoursFacts();
      }
    }

    if (_isEditing) {
      // 更新现有行程（保留地点归属，不再清空）
      final updatedTrip = widget.trip!;
      updatedTrip.name = _nameController.text;
      updatedTrip.startDate = _startDate;
      updatedTrip.endDate = _endDate;
      updatedTrip.tripMode = _tripMode;
      updatedTrip.days = days;

      context.read<TripProvider>().updateTrip(updatedTrip);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程更新成功')),
      );
    } else {
      // 创建新行程
      final trip = Trip(
        name: _nameController.text,
        startDate: _startDate,
        endDate: _endDate,
        days: days,
        homeLocation: context.read<TripProvider>().homeLocation,
        tripMode: _tripMode,
      );

      context.read<TripProvider>().createTrip(trip);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程创建成功')),
      );
    }
  }
}
