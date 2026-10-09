// 运行时模型：不进 Trip.toJson
//
// 对应服务端 `stats.cost`（server/src/multiCity.js P1-15 费用预估）。
// 取数点唯一：`Trip.fromPlannerResponse()` 读 `json['stats']['cost']`
// （注意它在 stats 下、不在 trip 下 —— 只解析 trip 的写法会静默丢弃它）。
//
// 【裁 2】本次客户端不接 /api/planner/corridor，因此该值在端上恒为 null；
// 模型与取数路径先定义好，下一迭代接 corridor 时零改动。
// 【裁 1】客户端严禁自行估算油/电/过路/租车，本模型只做"展示服务端已给的数字"。

/// 行程级费用预估（服务端粗估口径：油/电 + 过路 + 班次票价 + 租车/包车）
class TripCost {
  /// 币种（服务端恒为 CNY）
  final String currency;

  /// 费用明细，**动态 key**（fuel / toll / transit / rental / charter 均可缺省）
  final Map<String, int> items;

  /// 合计（服务端已算好，客户端不重新求和、不对账）
  final int total;

  /// 服务端原始口径说明（必须原样展示，不得改写、不得省略）
  final String? note;

  const TripCost({
    this.currency = 'CNY',
    this.items = const <String, int>{},
    this.total = 0,
    this.note,
  });

  /// 【裁 2 / M6】口径冲突提示：本卡含油电过路，与「当日已计价」口径不同，两者不可相加。
  /// 文案单一来源，UI 直接引用，避免各处手写走样。
  /// （M11：页面口径已改名为「当日已计价」，本提示同步改名。）
  static const String scopeConflictNote =
      '本卡口径含油电过路，与「当日已计价」口径不同，两者不可相加';

  /// 明细按金额降序（UI 展示 items 时用，保证主次清晰）
  List<MapEntry<String, int>> get sortedItems {
    final list = items.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// 是否有明细（无明细时 UI 应整块隐藏，而不是显示 ¥0）
  bool get isEmpty => items.isEmpty && total == 0;

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'items': items,
        'total': total,
        'note': note,
      };

  /// 解析服务端 `stats.cost`。
  /// 向后兼容：items 中非数值项跳过；total 缺失时**不自行求和**（口径属于服务端）。
  factory TripCost.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <String, int>{};
    if (rawItems is Map) {
      for (final entry in rawItems.entries) {
        final v = entry.value;
        if (v is int) {
          items[entry.key.toString()] = v;
        } else if (v is num) {
          items[entry.key.toString()] = v.round();
        }
        // 其余类型（null / String / 数组）→ 跳过，不抛异常
      }
    }
    final rawTotal = json['total'];
    return TripCost(
      currency: (json['currency'] as String?) ?? 'CNY',
      items: items,
      total: rawTotal is int ? rawTotal : (rawTotal is num ? rawTotal.round() : 0),
      note: json['note'] as String?,
    );
  }

  @override
  String toString() =>
      'TripCost($currency, total=$total, items=$items${note == null ? '' : ', note=$note'})';
}
