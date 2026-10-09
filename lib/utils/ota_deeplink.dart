import '../models/trip_models.dart';
import '../theme/preview_theme.dart';

/// OTA 深链分级降级（纯函数，零 IO，可单测）
///
/// MVP 全部走**关键词降级**（PRD Q3-A）：无精确 POI ID 表，落到搜索页。
/// 三铁律第 3 条：花钱类（酒店/购票）跳转必须二次确认；导航不需要。
///
/// 【PR-08】酒店 / 景点**探针实测无参考价** → 深链就是这两类**价格功能的主要交付形态**。
/// 【PR-10 ③】本文件**只依赖 `trip_models.dart` 的 `Location`**，不 import 任何价格模型
/// （`price_quote` / `trip_cost` / `cost_aggregator`）—— OTA 接入后深链直接复用、零改动。
class OtaDeepLink {
  OtaDeepLink._();

  /// 深链用途：决定是否需要二次确认
  static const String nav = 'nav';
  static const String hotel = 'hotel';
  static const String ticket = 'ticket';

  /// 【TL-10 回归】旧版地点详情弹窗是「OTA 三选」：高德导航 / 携程 / 美团比价。
  /// 本轮为防丢能力单独登记该用途；它不由 `purposeOf()` 按类型推导
  /// （美团不绑定地点类型，任何地点都能比价），由弹层显式传入。
  static const String meituan = 'meituan';

  /// 构造深链 URL（关键词降级）
  static String build(Location loc, String purpose) {
    final kw = Uri.encodeQueryComponent(loc.name);
    switch (purpose) {
      case hotel:
        return 'https://m.ctrip.com/webapp/hotel/list?keyword=$kw';
      case ticket:
        return 'https://piao.ctrip.com/ticket/list?keyword=$kw';
      case meituan:
        return 'https://www.meituan.com/s/${Uri.encodeComponent(loc.name)}';
      case nav:
      default:
        return 'https://uri.amap.com/search?keyword=$kw';
    }
  }

  /// 按地点类型推断默认用途（酒店→订房，景点→购票，其余→导航）
  static String purposeOf(Location loc) {
    switch (loc.type) {
      case LocationType.hotel:
        return hotel;
      case LocationType.attraction:
        return ticket;
      default:
        return nav;
    }
  }

  /// 是否需要二次确认（花钱类 = 酒店/购票/美团团购）
  static bool needsConfirm(String purpose) =>
      purpose == hotel || purpose == ticket || purpose == meituan;

  /// 渠道名（二次确认文案里要写清跳去哪，不能一律写"携程"）
  static String platformOf(String purpose) {
    switch (purpose) {
      case meituan:
        return '美团';
      case nav:
        return '高德';
      default:
        return '携程';
    }
  }

  /// 二次确认文案（M7：不写"可订状态"）
  static String confirmText(Location loc, String purpose) =>
      PreviewStrings.otaConfirm(loc.name, platform: platformOf(purpose));

  /// 按钮文案（PR-08：酒店/景点无参考价 → 深链即价格入口）
  ///
  /// 不写「立即预订」（那暗示可订状态）；也不写「实时价」（M7 违禁词）。
  static String buttonText(String purpose) {
    switch (purpose) {
      case hotel:
        return PreviewStrings.otaHotelText;
      case ticket:
        return PreviewStrings.otaTicketText;
      case meituan:
        return PreviewStrings.otaMeituanText;
      default:
        return PreviewStrings.otaNavText;
    }
  }

  /// 确认弹窗标题
  static String confirmTitle(String purpose) {
    switch (purpose) {
      case hotel:
        return '跳转到携程看房型';
      case ticket:
        return '跳转到携程看门票';
      case meituan:
        return '跳转到美团比价';
      default:
        return '跳转到高德导航';
    }
  }
}
