import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_manager.dart';
import '../services/csv_export.dart';
import 'scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEManager>();
    return Scaffold(
      appBar: AppBar(title: const Text("步态检测"), backgroundColor: const Color(0xFF1565C0)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusGrid(ble),
            const SizedBox(height: 16),
            _buildRealtimeData(ble),
            const Spacer(),
            _buildBottomControls(ble),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusGrid(BLEManager ble) {
    final roles = DeviceRole.values;
    final names = ["左脚压力", "右脚压力", "左脚IMU", "右脚IMU"];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.5
      ),
      itemCount: 4,
      itemBuilder: (_, i) {
        final role = roles[i];
        final isConnected = ble.roleAssignments.containsKey(role);
        return Container(
          decoration: BoxDecoration(
            color: isConnected ? Colors.green.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isConnected ? Colors.green : Colors.grey.shade300)
          ),
          child: Center(child: Text("${names[i]}\n${isConnected ? '✅已连接' : '❌未连接'}",
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 14))),
        );
      },
    );
  }

  Widget _buildRealtimeData(BLEManager ble) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildDataColumn("左脚", acc: ble.leftIMUData, p: ble.leftPressureData, accDec: 3, gyroDec: 1, angDec: 1, pDec: 1)),
          const SizedBox(width: 12),
          Expanded(child: _buildDataColumn("右脚", acc: ble.rightIMUData, p: ble.rightPressureData, accDec: 3, gyroDec: 1, angDec: 1, pDec: 1)),
        ],
      ),
    );
  }

  Widget _buildDataColumn(String side, {required acc, required p, required int accDec, required int gyroDec, required int angDec, required int pDec}) {
    String fmt(double v, int d) => v.toStringAsFixed(d);
    return Column(
      children: [
        Text(side, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
        const SizedBox(height: 4),
        Text("压力: ${fmt(p.pressure[0], pDec)}, ${fmt(p.pressure[1], pDec)}, ${fmt(p.pressure[2], pDec)}", style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 2),
        Text("Acc: ${fmt(acc.accX, accDec)} ${fmt(acc.accY, accDec)} ${fmt(acc.accZ, accDec)}", style: const TextStyle(fontSize: 14)),
        Text("Gyro: ${fmt(acc.gyroX, gyroDec)} ${fmt(acc.gyroY, gyroDec)} ${fmt(acc.gyroZ, gyroDec)}", style: const TextStyle(fontSize: 14)),
        Text("Ang: ${fmt(acc.roll, angDec)} ${fmt(acc.pitch, angDec)} ${fmt(acc.yaw, angDec)}", style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildBottomControls(BLEManager ble) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: _ => const ScanScreen())),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text("扫描连接", style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: ble.isRecording ? null : () => ble.startRecording(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text("开始录制", style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: ble.isRecording ? () => ble.stopRecording() : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text("停止录制", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text("标签: ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            for (var i = 0; i <= 9; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TextButton(
                  onPressed: () => ble.updateLabel(i.toString()),
                  style: TextButton.styleFrom(
                    backgroundColor: ble.currentLabel == i.toString() ? const Color(0xFF1565C0) : Colors.grey.shade200,
                    foregroundColor: ble.currentLabel == i.toString() ? Colors.white : Colors.black87
                  ),
                  child: Text(i.toString(), style: const TextStyle(fontSize: 16)),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined, size: 28),
              onPressed: () async {
                final path = await CSVExporter.exportToDocuments(ble.recordingBuffer);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(path != null ? "导出成功: $path" : "无数据可导出")));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled, size: 28),
              onPressed: () => ble.clearAllConnections(),
              color: Colors.redAccent,
            )
          ],
        ),
      ],
    );
  }
}
