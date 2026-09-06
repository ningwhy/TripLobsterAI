import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'services/storage_service.dart';
import 'providers/trip_provider.dart';
import 'pages/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();
  await AppConfig.load();

  runApp(TripApp(storage: storage));
}

class TripApp extends StatelessWidget {
  final StorageService storage;

  const TripApp({super.key, required this.storage});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TripProvider(storage)..loadData(),
      child: MaterialApp(
        title: '旅行行程助手',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4A90D9),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF333333),
            elevation: 0,
          ),
        ),
        home: const HomePage(),
      ),
    );
  }
}
