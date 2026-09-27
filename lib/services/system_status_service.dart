import 'package:battery_plus/battery_plus.dart';

class SystemStatusService {
  final Battery _battery = Battery();

  Future<int?> getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }
}
