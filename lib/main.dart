import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/ble_manager.dart';
import 'screens/home_screen.dart';

void main() async {
  // 初始化 Flutter 绑定
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化蓝牙管理器
  final manager = BLEManager();
  
  // 异步请求权限，不阻塞 APP 启动，防止白屏闪退
  manager.requestPermissions(); 
  
  // 运行应用，并提供全局状态
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
      // 白色背景 + #1565C0 蓝色主题
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
