import 'package:flutter/services.dart';

class NativeTelecomService {
  NativeTelecomService._();

  static const MethodChannel _channel = MethodChannel('zyroai/native_telecom');
  static const String defaultReplyMessage =
      'The person is currently busy, drop your message for the user.';

  static Future<bool> syncCallAutomation({
    required bool dndMode,
    required bool callAutoReply,
    String replyMessage = defaultReplyMessage,
  }) async {
    final result = await _channel.invokeMethod<bool>('syncCallAutomation', {
      'dndMode': dndMode,
      'callAutoReply': callAutoReply,
      'replyMessage': replyMessage,
    });
    return result ?? false;
  }

  static Future<Map<String, dynamic>> getCallScreeningStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getCallScreeningStatus');
    return result ?? <String, dynamic>{};
  }

  static Future<bool> requestCallScreeningRole() async {
    final result = await _channel.invokeMethod<bool>('requestCallScreeningRole');
    return result ?? false;
  }
}
