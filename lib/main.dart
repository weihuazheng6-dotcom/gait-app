import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_manager.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final manager = BLEManager();
  await manager.requestPermissions();
  runApp(
    ChangeNotifierProvider.value(
      value: manager,
      child: const GaitDetectorApp(),
    ),
  );
}

class GaitDetectorApp extends StatelessWidget {
  const GaitDetectorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '步态检测',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF1565C0),
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 18, color: Colors.black87),
          bodyMedium: TextStyle(fontSize: 14),
          labelMedium: TextStyle(fontSize: 16),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
