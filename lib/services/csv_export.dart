import 'dart:io';

class CSVExporter {
  static const List<String> _headers = [
    'timestamp',
    'P_first_meta_R', 'P_Fifth_meta_R', 'P_heel_R',
    'acc_x_R', 'acc_y_R', 'acc_z_R',
    'ave_x_R', 'ave_y_R', 'ave_z_R',
    'ang_x_R', 'ang_y_R', 'ang_z_R',
    'P_first_meta_L', 'P_Fifth_meta_L', 'P_heel_L',
    'acc_x_L', 'acc_y_L', 'acc_z_L',
    'ave_x_L', 'ave_y_L', 'ave_z_L',
    'ang_x_L', 'ang_y_L', 'ang_z_L',
    'Label'
  ];

  static Future<String?> exportToDocuments(List<List<dynamic>> records) async {
    if (records.isEmpty) return null;

    final dir = Directory('/sdcard/Documents/');
    if (!dir.existsSync()) {
      try { dir.createSync(recursive: true); } catch (_) { return null; }
    }

    final fileName = "gait_data_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File('${dir.path}/$fileName');

    final sb = StringBuffer();
    sb.writeln(_headers.join(','));

    for (var row in records) {
      final fmtDouble = (v) {
        if (v is double) return v.toStringAsFixed(v.abs() > 100 ? 1 : 3);
        return v.toString();
      };

      // BLEManager存储顺序: 左P,左Acc,左Gyro,左Ang, 右P,右Acc,右Gyro,右Ang, Label
      // CSV要求顺序: 右..., 左..., Label
      final ts = row[0];
      final label = row.last;
      final lP = [fmtDouble(row[1]), fmtDouble(row[2]), fmtDouble(row[3])];
      final lA = [fmtDouble(row[4]), fmtDouble(row[5]), fmtDouble(row[6])];
      final lV = [fmtDouble(row[7]), fmtDouble(row[8]), fmtDouble(row[9])];
      final lN = [fmtDouble(row[10]), fmtDouble(row[11]), fmtDouble(row[12])];
      
      final rP = [fmtDouble(row[13]), fmtDouble(row[14]), fmtDouble(row[15])];
      final rA = [fmtDouble(row[16]), fmtDouble(row[17]), fmtDouble(row[18])];
      final rV = [fmtDouble(row[19]), fmtDouble(row[20]), fmtDouble(row[21])];
      final rN = [fmtDouble(row[22]), fmtDouble(row[23]), fmtDouble(row[24])];

      final csvRow = [ts, ...rP, ...rA, ...rV, ...rN, ...lP, ...lA, ...lV, ...lN, label];
      sb.writeln(csvRow.join(','));
    }

    file.writeAsStringSync(sb.toString());
    return file.path;
  }
}
