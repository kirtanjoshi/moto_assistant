import 'package:flutter/services.dart';

class IntercomAudioService {
  static const MethodChannel _channel = MethodChannel('com.motovoice.moto_assistant/audio_routing');

  Future<bool> startBluetoothSco() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('startBluetoothSco');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> stopBluetoothSco() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('stopBluetoothSco');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> resetToNormal() async {
    return await stopBluetoothSco();
  }

  Future<bool> isBluetoothScoOn() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('isBluetoothScoOn');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> adjustVolume(String direction) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('adjustVolume', {'direction': direction});
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
