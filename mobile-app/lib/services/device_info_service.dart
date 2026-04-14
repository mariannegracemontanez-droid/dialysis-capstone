import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();

  factory DeviceInfoService() {
    return _instance;
  }

  DeviceInfoService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get device brand and model
  Future<Map<String, String>> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'brand': androidInfo.manufacturer,
          'model': androidInfo.model,
          'type': 'Android',
          'displayName': '${androidInfo.manufacturer} ${androidInfo.model}',
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'brand': 'Apple',
          'model': iosInfo.utsname.machine,
          'type': 'iOS',
          'displayName': 'Apple ${iosInfo.utsname.machine}',
        };
      } else if (Platform.isWindows) {
        return {
          'brand': 'Windows',
          'model': 'PC',
          'type': 'Windows',
          'displayName': 'Windows PC',
        };
      } else if (Platform.isMacOS) {
        return {
          'brand': 'Apple',
          'model': 'Mac',
          'type': 'macOS',
          'displayName': 'Apple Mac',
        };
      } else if (Platform.isLinux) {
        return {
          'brand': 'Linux',
          'model': 'Device',
          'type': 'Linux',
          'displayName': 'Linux Device',
        };
      } else {
        return {
          'brand': 'Unknown',
          'model': 'Unknown',
          'type': 'Unknown',
          'displayName': 'Unknown Device',
        };
      }
    } catch (e) {
      return {
        'brand': 'Unknown',
        'model': 'Unknown',
        'type': 'Unknown',
        'displayName': 'Unknown Device',
      };
    }
  }
}
