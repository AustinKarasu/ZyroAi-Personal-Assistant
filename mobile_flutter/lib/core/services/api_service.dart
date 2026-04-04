import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task_item.dart';

class ApiService {
  ApiService({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultBaseUrl();

  final String _baseUrl;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _cachedVersion;
  static const _workspaceCacheKey = 'workspace_cache';
  static const _apiBaseUrlKey = 'api_base_url';
  static const _fallbackAppVersion = '1.1.5';

  static String _defaultBaseUrl() {
    const cloudBase = 'https://zyroai-backend.vercel.app';
    if (kIsWeb) return cloudBase;
    if (Platform.isAndroid) return cloudBase;
    return cloudBase;
  }

  Future<String> _deviceId() async {
    const key = 'device_id';
    final existing = await _secureStorage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    await _secureStorage.write(key: key, value: random);
    return random;
  }

  Future<String> _appVersion() async {
    if (_cachedVersion != null && _cachedVersion!.isNotEmpty) return _cachedVersion!;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedVersion = packageInfo.version;
      return _cachedVersion!;
    } on MissingPluginException {
      _cachedVersion = _fallbackAppVersion;
      return _cachedVersion!;
    } on PlatformException {
      _cachedVersion = _fallbackAppVersion;
      return _cachedVersion!;
    } catch (_) {
      _cachedVersion = _fallbackAppVersion;
      return _cachedVersion!;
    }
  }

  Future<Map<String, String>> _headers() async {
    return {
      'Content-Type': 'application/json',
      'x-device-id': await _deviceId(),
      'x-app-version': await _appVersion(),
    };
  }

  Future<String> _currentBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiBaseUrlKey) ?? _baseUrl;
  }

  Future<void> saveApiBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlKey, value);
  }

  Future<String> loadApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiBaseUrlKey) ?? _baseUrl;
  }

  Future<Map<String, dynamic>> _requestJson(String path, {String method = 'GET', Map<String, dynamic>? body, String? error}) async {
    final uri = Uri.parse('${await _currentBaseUrl()}$path');
    final requestHeaders = await _headers();
    final response = switch (method) {
      'POST' => await http.post(uri, headers: requestHeaders, body: body == null ? null : jsonEncode(body)),
      'PATCH' => await http.patch(uri, headers: requestHeaders, body: body == null ? null : jsonEncode(body)),
      _ => await http.get(uri, headers: requestHeaders),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(error ?? 'Request failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> _cacheWorkspace(Map<String, dynamic> workspace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workspaceCacheKey, jsonEncode(workspace));
  }

  Future<Map<String, dynamic>?> _loadWorkspaceCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_workspaceCacheKey);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchWorkspace() async {
    try {
      final response = await _requestJson('/api/workspace', error: 'Workspace load failed');
      await _cacheWorkspace(response);
      return response;
    } catch (_) {
      final cached = await _loadWorkspaceCache();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<TaskItem>> fetchDashboardTasks() async {
    final map = await _requestJson('/api/dashboard', error: 'Dashboard load failed');
    final list = (map['topPriorities'] as List<dynamic>).cast<Map<String, dynamic>>();
    return list.map(TaskItem.fromJson).toList();
  }

  Future<void> createTask({required String title, required int urgency, required int importance, required int energyCost}) async {
    await _requestJson('/api/tasks', method: 'POST', body: {'title': title, 'urgency': urgency, 'importance': importance, 'energyCost': energyCost}, error: 'Task creation failed');
  }

  Future<Map<String, dynamic>> runDecision({required String title, required List<Map<String, dynamic>> options}) async {
    return _requestJson('/api/decide', method: 'POST', body: {'title': title, 'options': options}, error: 'Decision engine failed');
  }

  Future<List<Map<String, dynamic>>> fetchCallLogs() async {
    final map = await _requestJson('/api/communications', error: 'Communications load failed');
    return (map['logs'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> submitCallLog(String caller, String transcript) async {
    await _requestJson('/api/communications/call-log', method: 'POST', body: {'caller': caller, 'transcript': transcript}, error: 'Call log submit failed');
  }

  Future<Map<String, dynamic>> handleIncomingCall(String caller, String transcript) async {
    return _requestJson('/api/communications/incoming-call', method: 'POST', body: {'caller': caller, 'transcript': transcript}, error: 'Incoming call failed');
  }

  Future<Map<String, dynamic>> fetchInsights() async {
    return _requestJson('/api/insights', error: 'Insights failed');
  }

  Future<List<Map<String, dynamic>>> fetchMemory() async {
    final map = await _requestJson('/api/memory', error: 'Memory fetch failed');
    return (map['entries'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> addMemory(String hint, String note) async {
    await _requestJson('/api/memory', method: 'POST', body: {'hint': hint, 'note': note}, error: 'Memory save failed');
  }

  Future<String> generateAutoReply(String sender, String context, String until) async {
    final map = await _requestJson('/api/messages/auto-reply', method: 'POST', body: {'sender': sender, 'context': context, 'until': until}, error: 'Auto reply failed');
    return map['message'] as String;
  }

  Future<Map<String, dynamic>> fetchProfile() async {
    return _requestJson('/api/profile', error: 'Profile fetch failed');
  }

  Future<Map<String, dynamic>> saveProfile(Map<String, dynamic> patch) async {
    return _requestJson('/api/profile', method: 'PATCH', body: patch, error: 'Profile save failed');
  }

  Future<Map<String, dynamic>> fetchSettings() async {
    return _requestJson('/api/settings', error: 'Settings fetch failed');
  }

  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> patch) async {
    return _requestJson('/api/settings', method: 'PATCH', body: patch, error: 'Settings save failed');
  }

  Future<Map<String, dynamic>> fetchReport(String period) async {
    return _requestJson('/api/reports?period=$period', error: 'Report fetch failed');
  }

  Future<Map<String, dynamic>> fetchSteps() async {
    return _requestJson('/api/steps', error: 'Step fetch failed');
  }

  Future<Map<String, dynamic>> logSteps(int count, {String mode = 'add', String source = 'manual'}) async {
    return _requestJson('/api/steps', method: 'POST', body: {'count': count, 'mode': mode, 'source': source}, error: 'Step logging failed');
  }

  Future<Map<String, dynamic>> fetchWeather({double? lat, double? lon}) async {
    final suffix = lat != null && lon != null ? '?lat=$lat&lon=$lon' : '';
    return _requestJson('/api/weather$suffix', error: 'Weather fetch failed');
  }

  Future<Map<String, dynamic>> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    return _requestJson(
      '/api/translate',
      method: 'POST',
      body: {
        'text': text,
        'sourceLang': sourceLang,
        'targetLang': targetLang,
      },
      error: 'Translation failed',
    );
  }

  Future<Map<String, dynamic>> chat(String message) async {
    return _requestJson('/api/assistant/chat', method: 'POST', body: {'message': message}, error: 'Assistant chat failed');
  }

  Future<void> saveUiPrefs({required bool wellbeingGuardEnabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wellbeing_guard_enabled', wellbeingGuardEnabled);
  }

  Future<bool> loadUiPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('wellbeing_guard_enabled') ?? true;
  }


  Future<void> clearLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_workspaceCacheKey);
    await prefs.remove('wellbeing_guard_enabled');
    await prefs.remove('motion_last_raw_steps');
    await prefs.remove('motion_last_raw_steps_date');
    await prefs.remove('installed_app_version');
    await prefs.remove('dismissed_update_version');
  }

  Future<void> clearAllLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _secureStorage.deleteAll();
  }

}


