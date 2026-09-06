import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../providers/trip_provider.dart';
import '../services/api_client.dart';

/// P0-1 云同步设置：服务器地址 / 登录注册 / 手动同步
class CloudSettingsPage extends StatefulWidget {
  const CloudSettingsPage({super.key});

  @override
  State<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends State<CloudSettingsPage> {
  final _serverController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _isRegister = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _serverController.text = AppConfig.serverBaseUrl;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _showMsg(String msg, {bool isError = false}) {
    setState(() {
      _message = msg;
      _messageIsError = isError;
    });
  }

  Future<void> _saveServer() async {
    await AppConfig.setServerBaseUrl(_serverController.text);
    final ok = await ApiClient.health();
    _showMsg(ok ? '服务器连接成功 ✓' : '无法连接该服务器，请检查地址和后端是否启动', isError: !ok);
  }

  Future<void> _auth() async {
    final user = _userController.text.trim();
    final pass = _passController.text;
    if (user.isEmpty || pass.isEmpty) {
      _showMsg('请输入用户名和密码', isError: true);
      return;
    }
    try {
      if (_isRegister) {
        await ApiClient.register(user, pass);
      } else {
        await ApiClient.login(user, pass);
      }
      _showMsg(_isRegister ? '注册成功，正在同步…' : '登录成功，正在同步…');
      final err = await context.read<TripProvider>().syncNow();
      if (!mounted) return;
      _showMsg(err ?? '同步完成 ✓', isError: err != null);
    } on ApiException catch (e) {
      _showMsg(e.message, isError: true);
    }
  }

  Future<void> _sync() async {
    final provider = context.read<TripProvider>();
    final err = await provider.syncNow();
    if (!mounted) return;
    _showMsg(err ?? '同步完成 ✓', isError: err != null);
  }

  Future<void> _logout() async {
    await ApiClient.clearSession();
    _showMsg('已退出登录（本地数据保留）');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('云同步'),
        backgroundColor: const Color(0xFFF0F7FF),
        actions: [
          FutureBuilder<String?>(
            future: ApiClient.token,
            builder: (context, snap) {
              if (snap.data == null) return const SizedBox.shrink();
              return IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 20),
                tooltip: '退出登录',
              );
            },
          ),
        ],
      ),
      body: Consumer<TripProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('服务器地址'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serverController,
                      decoration: const InputDecoration(
                        hintText: 'http://192.168.x.x:8787',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _saveServer, child: const Text('保存')),
                ],
              ),
              const SizedBox(height: 4),
              const Text('模拟器用户填 http://10.0.2.2:8787', style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 24),
              FutureBuilder<String?>(
                future: ApiClient.username,
                builder: (context, snap) {
                  final loggedIn = snap.data != null && snap.connectionState == ConnectionState.done;
                  if (loggedIn) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('当前账号'),
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person, size: 20)),
                            title: Text(snap.data!),
                            subtitle: provider.lastSyncAt > 0
                                ? Text('上次同步: ${DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(provider.lastSyncAt))}')
                                : const Text('尚未同步过'),
                            trailing: provider.isSyncing
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton(onPressed: _sync, child: const Text('立即同步')),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(_isRegister ? '注册账号' : '登录账号'),
                      TextField(
                        controller: _userController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '密码（至少6位）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _auth,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90D9),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(_isRegister ? '注册并同步' : '登录并同步'),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _isRegister = !_isRegister),
                            child: Text(_isRegister ? '已有账号？去登录' : '没有账号？去注册'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '登录后行程将自动云同步：换手机、双设备使用不再丢数据。',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                    ],
                  );
                },
              ),
              if (_message != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _messageIsError ? const Color(0xFFFFF0F0) : const Color(0xFFEFFFEF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _messageIsError ? const Color(0xFFFFC1C1) : const Color(0xFFB7E4B7)),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(fontSize: 13, color: _messageIsError ? const Color(0xFFCC3333) : const Color(0xFF2E7D32)),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}
