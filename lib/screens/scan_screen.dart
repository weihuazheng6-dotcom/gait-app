import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gait_data.dart'; // <--- 新增导入
import '../services/ble_manager.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEManager>();
    return Scaffold(
      appBar: AppBar(title: const Text("设备扫描"), backgroundColor: const Color(0xFF1565C0)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text("扫描进度: ${(ble.scanProgress * 100).toInt()}%", style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: ble.scanProgress, backgroundColor: Colors.grey.shade200, color: const Color(0xFF1565C0)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: ble.isScanning ? null : () => ble.startScan(),
                  icon: Icon(ble.isScanning ? Icons.stop : Icons.search),
                  label: Text(ble.isScanning ? "停止扫描" : "开始扫描"),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ble.foundDevices.length,
              itemBuilder: (_, i) {
                final dev = ble.foundDevices[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth, color: Color(0xFF1565C0)),
                    // <--- 修正：使用 dev.device.platformName
                    title: Text(dev.device.platformName.isNotEmpty ? dev.device.platformName : "Unknown Device", style: const TextStyle(fontSize: 16)),
                    subtitle: Text("${dev.device.remoteId.str} | RSSI: ${dev.rssi}dBm", style: const TextStyle(fontSize: 14)),
                    trailing: IconButton(
                      icon: const Icon(Icons.link, color: Color(0xFF1565C0)),
                      onPressed: () => _showRoleDialog(context, dev),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  void _showRoleDialog(BuildContext context, dynamic scanResult) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("分配设备角色"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DeviceRole.values.map((role) => ListTile(
            title: Text(_roleName(role), style: const TextStyle(fontSize: 16)),
            onTap: () async {
              Navigator.pop(context);
              try {
                await context.read<BLEManager>().connectAndAssignRole(scanResult, role);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("成功连接: ${_roleName(role)}")));
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
          )).toList(),
        ),
      ),
    );
  }

  String _roleName(DeviceRole r) => switch(r) {
    DeviceRole.leftPressure => "左脚压力",
    DeviceRole.rightPressure => "右脚压力",
    DeviceRole.leftIMU => "左脚IMU",
    DeviceRole.rightIMU => "右脚IMU",
  };
}
