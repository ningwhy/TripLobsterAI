import 'package:shared_preferences/shared_preferences.dart';

/// 全局配置：后端服务器地址（可在设置页修改）
class AppConfig {
  /// 默认后端地址：本机 LAN IP（Android 真机同 WiFi 可直连）
  /// 模拟器可改为 http://10.0.2.2:8787
  static const String kDefaultServer = 'http://192.168.4.66:8787';

  static String serverBaseUrl = kDefaultServer;

  static const String _key = 'server_base_url';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    serverBaseUrl = prefs.getString(_key) ?? kDefaultServer;
  }

  static Future<void> setServerBaseUrl(String url) async {
    var v = url.trim();
    if (v.isEmpty) v = kDefaultServer;
    if (!v.startsWith('http')) v = 'http://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    serverBaseUrl = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, v);
  }
}
