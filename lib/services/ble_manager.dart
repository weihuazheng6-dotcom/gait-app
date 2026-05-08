import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/gait_data.dart';
import 'package:uuid/uuid.dart';

/// 蓝牙管理器：负责设备扫描、连接、角色分配、数据解析与录制控制
class BLEManager extends ChangeNotifier {
  // ================= 全局状态 =================
  bool isScanning = false;
  double scanProgress = 0.0;
  List<ScanResult> foundDevices = [];
  final Map<DeviceIdentifier, BluetoothDevice> activeDevices = {};
  final Map<DeviceRole, BluetoothDevice> roleAssignments = {};
  Timer? scanTimer;

  // ================= 实时数据缓存 =================
  SensorData leftPressureData = SensorData(timestamp: DateTime.now());
  SensorData rightPressureData = SensorData(timestamp: DateTime.now());
  SensorData leftIMUData = SensorData(timestamp: DateTime.now());
  SensorData rightIMUData = SensorData(timestamp: DateTime.now());

  // ================= 录制控制 =================
  bool isRecording = false;
  String currentLabel = "0";
  List<List<dynamic>> recordingBuffer = [];

  // ================= IMU轮询定时器 =================
  Timer? _imuPollTimer;
  final Duration _pollInterval = const Duration(milliseconds: 100);
  final _uuidGen = const Uuid();

  // ================= BLE 常量定义 =================
  static const String SvcPressure = "FFE0";
  static const String CharPressureNotify = "FFE1";
  static const Guid SvcIMU = Guid("0000FFE5-0000-1000-8000-00805F9A34FB");
  static const Guid CharIMUNotify = Guid("0000FFE4-0000-1000-8000-00805F9A34FB");
  static const Guid CharIMUWrite = Guid("0000FFE9-0000-1000-8000-00805F9A34FB");

  // ================= 跨包数据缓冲 =================
  final Map<DeviceIdentifier, List<int>> _imuBuffers = {};
  final Map<DeviceIdentifier, StringBuffer> _pressureBuffers = {};
  final Map<DeviceIdentifier, bool> _isConnected = {};

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    scanTimer?.cancel();
    _imuPollTimer?.cancel();
    clearAllConnections();
    _log("Manager Disposed");
  }

  // ================= 权限请求 =================
  Future<void> requestPermissions() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.storage,
      ].request();
      _log("Permissions requested");
    } catch (e) {
      _log("Permission request failed: $e");
    }
  }

  // ================= 扫描控制 =================
  Future<void> startScan() async {
    if (isScanning) return;
    foundDevices.clear();
    isScanning = true;
    scanProgress = 0.0;
    notifyListeners();
    _log("BLE Scan Started");

    scanTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (scanProgress >= 1.0) {
        stopScan();
      } else {
        scanProgress += 0.01;
        notifyListeners();
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      FlutterBluePlus.scanResults.listen((results) {
        for (var r in results) {
          if (!foundDevices.any((e) => e.device.remoteId.str == r.device.remoteId.str)) {
            foundDevices.add(r);
            notifyListeners();
          }
        }
      });
    } catch (e) {
      _log("Scan failed: $e");
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    scanTimer?.cancel();
    await FlutterBluePlus.stopScan().catchError((_) {});
    isScanning = false;
    scanProgress = 1.0;
    _log("BLE Scan Stopped");
    notifyListeners();
  }

  // ================= 连接与角色分配 =================
  Future<void> connectAndAssignRole(ScanResult scanRes, DeviceRole role) async {
    final device = scanRes.device;
    final devId = device.remoteId;

    if (roleAssignments.values.any((d) => d.remoteId.str == devId.str)) {
      throw Exception("设备已分配其他角色");
    }
    if (roleAssignments.containsKey(role)) {
      throw Exception("该角色已被占用");
    }

    try {
      _log("Connecting to ${devId.str} as ${role.name}...");
      await device.connect(timeout: const Duration(seconds: 15));
      _isConnected[devId] = true;
      
      // 监听断开连接
      device.state.listen((state) {
        if (state == BluetoothDeviceState.disconnected) {
          _isConnected[devId] = false;
          roleAssignments.remove(role);
          activeDevices.remove(devId);
          _log("Device disconnected: ${devId.str}");
          _checkPollerStatus();
          notifyListeners();
        }
      });

      activeDevices[devId] = device;
      roleAssignments[role] = device;

      await _discoverAndSetup(device, role, devId);
      notifyListeners();
      _log("Successfully connected & assigned ${role.name}");
    } catch (e) {
      _log("Connection Failed for $devId: $e");
      rethrow;
    }
  }

  Future<void> _discoverAndSetup(BluetoothDevice device, DeviceRole role, DeviceIdentifier devId) async {
    final services = await device.discoverServices();
    _log("Discovered ${services.length} services for $devId");

    _imuBuffers[devId] = [];
    _pressureBuffers[devId] = StringBuffer();

    if (role.name.contains("IMU")) {
      _log("Setting up IMU Polling for ${role.name}");
      _checkPollerStatus();
    } else {
      for (var service in services) {
        if (service.uuid.toString().toLowerCase().contains(SvcPressure.toLowerCase())) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(CharPressureNotify.toLowerCase())) {
              await _setupPressureNotify(device, char, role);
              return;
            }
          }
        }
      }
      _log("Warning: Pressure notify characteristic not found for $devId");
    }
  }

  Future<void> _setupPressureNotify(BluetoothDevice device, BluetoothCharacteristic char, DeviceRole role) async {
    try {
      await char.setNotifyValue(true);
      char.lastValueStream.listen((value) {
        if (value.isNotEmpty && _isConnected[device.remoteId] == true) {
          _processPressureData(value, role, device.remoteId);
        }
      });
      _log("Pressure notify enabled for ${role.name}");
    } catch (e) {
      _log("Notify Setup Failed for ${role.name}: $e");
    }
  }

  void _checkPollerStatus() {
    final hasIMU = roleAssignments.keys.any((r) => r.name.contains("IMU"));
    if (hasIMU && (_imuPollTimer == null || !_imuPollTimer!.isActive)) {
      _startGlobalPolling();
    } else if (!hasIMU && _imuPollTimer != null) {
      _imuPollTimer?.cancel();
      _imuPollTimer = null;
    }
  }

  void _startGlobalPolling() {
    _imuPollTimer = Timer.periodic(_pollInterval, (timer) async {
      for (var role in DeviceRole.values.where((r) => r.name.contains("IMU"))) {
        final dev = roleAssignments[role];
        if (dev == null || !_isConnected[dev.remoteId]!) continue;
        await _readIMUCharacteristic(dev, role);
      }
    });
    _log("Global IMU polling started at 10Hz");
  }

  Future<void> _readIMUCharacteristic(BluetoothDevice device, DeviceRole role) async {
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? char;
      for (var svc in services) {
        if (svc.uuid == SvcIMU) {
          char = svc.characteristics.firstWhere(
            (c) => c.uuid == CharIMUNotify,
            orElse: () => BluetoothCharacteristic(characteristicUuid: Guid("")),
          );
          break;
        }
      }
      if (char != null && char.characteristicUuid != Guid("")) {
        final bytes = await char.read();
        if (bytes.isNotEmpty) _processIMUData(bytes, role, device.remoteId);
      }
    } catch (e) {
      // 轮询失败静默处理，避免阻塞主循环
    }
  }

  // ================= 数据解析引擎 =================
  void _processIMUData(List<int> data, DeviceRole role, DeviceIdentifier devId) {
    _imuBuffers[devId]!.addAll(data);
    final buf = _imuBuffers[devId]!;

    while (buf.length >= 20) {
      if (buf[0] == 0x55 && buf[1] == 0x61) {
        final frame = buf.sublist(0, 20);
        buf.removeRange(0, 20);
        _parseIMUFrame(frame, role);
      } else {
        buf.removeAt(0);
      }
    }
  }

  void _parseIMUFrame(List<int> frame, DeviceRole role) {
    int16 read16(int index) => (frame[index] | (frame[index + 1] << 8)).toSigned(16);

    final accX = read16(2) / 32768.0 * 16.0;
    final accY = read16(4) / 32768.0 * 16.0;
    final accZ = read16(6) / 32768.0 * 16.0;
    final gyroX = read16(8) / 32768.0 * 2000.0;
    final gyroY = read16(10) / 32768.0 * 2000.0;
    final gyroZ = read16(12) / 32768.0 * 2000.0;
    final roll  = read16(14) / 32768.0 * 180.0;
    final pitch = read16(16) / 32768.0 * 180.0;
    final yaw   = read16(18) / 32768.0 * 180.0;

    final now = DateTime.now();
    final data = SensorData(
      timestamp: now,
      accX: accX, accY: accY, accZ: accZ,
      gyroX: gyroX, gyroY: gyroY, gyroZ: gyroZ,
      roll: roll, pitch: pitch, yaw: yaw
    );

    if (role == DeviceRole.leftIMU) leftIMUData = data;
    else if (role == DeviceRole.rightIMU) rightIMUData = data;

    _recordIfActive(now);
    notifyListeners();
  }

  void _processPressureData(List<int> rawBytes, DeviceRole role, DeviceIdentifier devId) {
    final str = utf8.decode(rawBytes, allowMalformed: true);
    final buf = _pressureBuffers[devId]!;
    buf.write(str);

    final content = buf.toString();
    if (content.contains(';')) {
      final split = content.split(';');
      buf.clear();
      final lastPart = split.last;
      if (!content.endsWith(';')) buf.write(lastPart);
      
      final validParts = split.where((s) => s.trim().isNotEmpty && s.startsWith('\$')).toList();
      if (!content.endsWith(';') && split.isNotEmpty) validParts.removeLast();

      for (var part in validParts) {
        if (!part.startsWith('\$')) continue;
        final nums = part.substring(1).split(',').map((s) => double.tryParse(s) ?? 0.0).toList();
        if (nums.length >= 3) {
          final p = [nums[0], nums[1], nums[2]];
          final now = DateTime.now();
          if (role == DeviceRole.leftPressure) leftPressureData = SensorData(timestamp: now, pressure: p);
          else if (role == DeviceRole.rightPressure) rightPressureData = SensorData(timestamp: now, pressure: p);
          _recordIfActive(now);
          notifyListeners();
        }
      }
    }
  }

  // ================= 录制与标签 =================
  void startRecording() {
    isRecording = true;
    recordingBuffer.clear();
    _log("Recording Started");
    notifyListeners();
  }

  void stopRecording() {
    isRecording = false;
    _log("Recording Stopped. Captured ${recordingBuffer.length} samples.");
    notifyListeners();
  }

  void updateLabel(String newLabel) {
    currentLabel = newLabel;
    notifyListeners();
  }

  void _recordIfActive(DateTime ts) {
    if (!isRecording) return;
    recordingBuffer.add([
      ts.toIso8601String(),
      leftPressureData.pressure[0], leftPressureData.pressure[1], leftPressureData.pressure[2],
      leftIMUData.accX, leftIMUData.accY, leftIMUData.accZ,
      leftIMUData.gyroX, leftIMUData.gyroY, leftIMUData.gyroZ,
      leftIMUData.roll, leftIMUData.pitch, leftIMUData.yaw,
      rightPressureData.pressure[0], rightPressureData.pressure[1], rightPressureData.pressure[2],
      rightIMUData.accX, rightIMUData.accY, rightIMUData.accZ,
      rightIMUData.gyroX, rightIMUData.gyroY, rightIMUData.gyroZ,
      rightIMUData.roll, rightIMUData.pitch, rightIMUData.yaw,
      currentLabel
    ]);
  }

  // ================= 清理与重置 =================
  Future<void> clearAllConnections() async {
    _imuPollTimer?.cancel();
    _imuPollTimer = null;
    
    for (var dev in roleAssignments.values) {
      try { await dev.disconnect(); } catch(_) {}
    }
    activeDevices.clear();
    roleAssignments.clear();
    _imuBuffers.clear();
    _pressureBuffers.clear();
    _isConnected.clear();
    
    leftPressureData = SensorData(timestamp: DateTime.now());
    rightPressureData = SensorData(timestamp: DateTime.now());
    leftIMUData = SensorData(timestamp: DateTime.now());
    rightIMUData = SensorData(timestamp: DateTime.now());
    recordingBuffer.clear();
    isRecording = false;
    currentLabel = "0";
    _log("All connections cleared & state reset");
    notifyListeners();
  }

  void _log(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    if (kDebugMode) debugPrint("[$time] [BLEManager] $msg");
  }
}
