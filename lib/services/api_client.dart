import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// 后端 API 客户端：统一超时、重试、错误处理
class ApiClient {
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _longTimeout = Duration(seconds: 60); // AI 生成

  static Future<String?> get token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> saveSession(String token, String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_username', username);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
  }

  static Future<String?> get username async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_username');
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    Duration timeout = _timeout,
    int retries = 1,
  }) async {
    final uri = Uri.parse('${AppConfig.serverBaseUrl}$path');
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (auth) {
          final t = await token;
          if (t != null) headers['Authorization'] = 'Bearer $t';
        }
        final encoded = body != null ? jsonEncode(body) : null;
        late Future<http.Response> future;
        switch (method) {
          case 'POST':
            future = http.post(uri, headers: headers, body: encoded);
            break;
          case 'PUT':
            future = http.put(uri, headers: headers, body: encoded);
            break;
          case 'DELETE':
            future = http.delete(uri, headers: headers);
            break;
          default:
            future = http.get(uri, headers: headers);
        }
        final resp = await future.timeout(timeout);
        if (resp.statusCode == 401) {
          await clearSession();
          throw ApiException('登录已过期，请重新登录', statusCode: 401);
        }
        final data = resp.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(resp.bodyBytes));
        if (resp.statusCode >= 400) {
          throw ApiException(data?['error'] ?? '服务异常(${resp.statusCode})', statusCode: resp.statusCode);
        }
        return data;
      } on ApiException {
        rethrow; // 业务错误不重试
      } on SocketException {
        lastError = ApiException('无法连接服务器，请检查网络或服务器地址');
      } on TimeoutException {
        lastError = ApiException('服务器响应超时，请稍后再试');
      } catch (e) {
        lastError = ApiException('请求失败: $e');
      }
      if (attempt < retries) await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
    throw lastError is ApiException ? lastError : ApiException('请求失败');
  }

  // ---------- 账号 ----------
  static Future<Map<String, dynamic>> register(String username, String password) async {
    final data = await _request('POST', '/api/auth/register', body: {'username': username, 'password': password});
    await saveSession(data['token'], data['username']);
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await _request('POST', '/api/auth/login', body: {'username': username, 'password': password});
    await saveSession(data['token'], data['username']);
    return Map<String, dynamic>.from(data);
  }

  static Future<void> logout() async {
    try {
      await _request('POST', '/api/auth/logout', auth: true, retries: 0);
    } catch (_) {}
    await clearSession();
  }

  // ---------- 云同步 ----------
  static Future<Map<String, dynamic>> pull({int since = 0}) async {
    final data = await _request('GET', '/api/sync/pull?since=$since', auth: true);
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> push(List<Map<String, dynamic>> trips, List<Map<String, dynamic>> deleted) async {
    final data = await _request('POST', '/api/sync/push', body: {'trips': trips, 'deleted': deleted}, auth: true);
    return Map<String, dynamic>.from(data);
  }

  // ---------- AI 行程生成 ----------
  static Future<Map<String, dynamic>> generatePlan({
    required String city,
    required int days,
    required String startDate,
    required String pace,
    required List<String> interests,
    String tripMode = 'pureTransit',
    String intercityVehicle = 'highSpeedTrain',
    String description = '',
    String? fromCity,
    int adults = 2,
    int children = 0,
    int rooms = 1,
    String? roomType,
    String budget = 'comfort',
    List<String> mustVisit = const [],
  }) async {
    final data = await _request('POST', '/api/planner/generate', body: {
      'city': city,
      'days': days,
      'startDate': startDate,
      'pace': pace,
      'interests': interests,
      'tripMode': tripMode,
      'intercityVehicle': intercityVehicle,
      'description': description,
      'fromCity': fromCity,
      'adults': adults,
      'children': children,
      'rooms': rooms,
      'roomType': roomType,
      'budget': budget,
      'mustVisit': mustVisit,
    }, timeout: _longTimeout, retries: 0);
    return Map<String, dynamic>.from(data);
  }

  // ---------- 天气（为 P0-3/P0-4 预留） ----------
  static Future<Map<String, dynamic>> weather(double lat, double lon) async {
    final data = await _request('GET', '/api/weather?lat=$lat&lon=$lon');
    return Map<String, dynamic>.from(data);
  }

  // ---------- 健康检查 ----------
  static Future<bool> health() async {
    try {
      final data = await _request('GET', '/');
      return data?['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
