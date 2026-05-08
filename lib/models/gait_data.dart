/// 设备角色枚举
enum DeviceRole {
  leftPressure,
  rightPressure,
  leftIMU,
  rightIMU
}

/// 传感器单点数据模型
class SensorData {
  DateTime timestamp;
  List<double> pressure; // [P_first, P_Fifth, P_heel]
  double accX, accY, accZ;
  double gyroX, gyroY, gyroZ;
  double roll, pitch, yaw;

  SensorData({
    required this.timestamp,
    this.pressure = const [0.0, 0.0, 0.0],
    this.accX = 0, this.accY = 0, this.accZ = 0,
    this.gyroX = 0, this.gyroY = 0, this.gyroZ = 0,
    this.roll = 0, this.pitch = 0, this.yaw = 0,
  });
}

