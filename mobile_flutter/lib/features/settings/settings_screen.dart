import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/api_service.dart';
import '../../core/services/motion_tracking_service.dart';
import '../../core/services/native_telecom_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.onThemeChanged,
    required this.onLanguageChanged,
  });

  final ApiService api;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String _autosaveStatus = 'Everything saved';
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _auditLogs = [];
  Map<String, String> _deviceInfo = {};
  Map<String, dynamic> _callScreening = {'supported': false, 'roleHeld': false};
  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _apiBaseUrlCtrl = TextEditingController();
  Timer? _autosaveTimer;

  void _showSavePopup(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _goalCtrl.dispose();
    _cityCtrl.dispose();
    _apiBaseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profileRes = await widget.api.fetchProfile();
      final settingsRes = await widget.api.fetchSettings();
      final auditLogs = await widget.api.fetchAuditLogs();
      final apiBaseUrl = await widget.api.loadApiBaseUrl();
      final profile = (profileRes['profile'] as Map).cast<String, dynamic>();
      final settings = (settingsRes['settings'] as Map).cast<String, dynamic>();
      final deviceInfo = await _loadDeviceInfo();
      final callScreening = Platform.isAndroid
          ? await NativeTelecomService.getCallScreeningStatus()
          : <String, dynamic>{'supported': false, 'roleHeld': false};

      _nameCtrl.text = profile['name']?.toString() ?? '';
      _titleCtrl.text = profile['title']?.toString() ?? '';
      _goalCtrl.text = (profile['daily_step_goal'] ?? 8000).toString();
      _cityCtrl.text = profile['city']?.toString() ?? '';
      _apiBaseUrlCtrl.text = apiBaseUrl;

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _settings = settings;
        _auditLogs = auditLogs;
        _deviceInfo = deviceInfo;
        _callScreening = callScreening;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings loading fallback active.')),
      );
    }
  }

  Future<Map<String, String>> _loadDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return {
        'brand': info.brand,
        'model': info.model,
        'device': info.device,
        'manufacturer': info.manufacturer,
        'version.release': info.version.release,
        'version.sdkInt': '${info.version.sdkInt}',
        'hardware': info.hardware,
        'board': info.board,
        'bootloader': info.bootloader,
        'product': info.product,
        'isPhysicalDevice': '${info.isPhysicalDevice}',
      };
    }

    final base = await plugin.deviceInfo;
    return base.data.map((key, value) => MapEntry(key, '$value'));
  }

  Future<void> _save({bool showToast = true, bool syncNative = true, bool refreshMotion = true}) async {
    setState(() {
      _saving = true;
      _autosaveStatus = 'Saving changes...';
    });
    try {
      if (kDebugMode) {
        await widget.api.saveApiBaseUrl(_apiBaseUrlCtrl.text.trim());
      }

      final savedProfile = await widget.api.saveProfile({
        'name': _nameCtrl.text.trim(),
        'title': _titleCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'daily_step_goal': int.tryParse(_goalCtrl.text) ?? 8000,
        'language': _profile['language'] ?? 'en',
      });
      final savedSettings = await widget.api.saveSettings(_settings);
      _profile = (savedProfile['profile'] as Map?)?.cast<String, dynamic>() ?? _profile;
      _settings = (savedSettings['settings'] as Map?)?.cast<String, dynamic>() ?? _settings;

      final automation = (_settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
      if (syncNative && Platform.isAndroid && mounted) {
        try {
          await NativeTelecomService.syncCallAutomation(
            dndMode: automation['dndMode'] == true,
            callAutoReply: automation['callAutoReply'] != false,
            smsAutoReply: automation['smsAutoReply'] != false,
          );
          _callScreening = await NativeTelecomService.getCallScreeningStatus();
        } catch (_) {
          _autosaveStatus = 'Saved. Native sync will retry automatically.';
        }
      }

      if (refreshMotion) {
        try {
          await MotionTrackingService.instance.refreshConfig();
        } catch (_) {}
      }

      try {
        _auditLogs = await widget.api.fetchAuditLogs();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _autosaveStatus = _autosaveStatus == 'Saving changes...' ? 'Everything saved' : _autosaveStatus);
      _showSavePopup(showToast ? 'Settings saved successfully.' : 'Changes saved automatically.');
    } catch (error) {
      if (!mounted) return;
      final message = '$error';
      final label = message.toLowerCase().contains('profile')
          ? 'Profile save failed'
          : message.toLowerCase().contains('settings')
              ? 'Settings save failed'
              : 'Saving failed';
      setState(() => _autosaveStatus = '$label. Retry on next change');
      _showSavePopup('$label: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _scheduleAutosave({bool syncNative = false, bool refreshMotion = false}) {
    _autosaveTimer?.cancel();
    setState(() => _autosaveStatus = 'Unsaved changes');
    _autosaveTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      await _save(showToast: false, syncNative: syncNative, refreshMotion: refreshMotion);
    });
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse('mailto:berrykarasu@gmail.com?subject=ZyroAi%20Support');
    await launchUrl(uri);
  }

  Future<void> _requestPermission(String key) async {
    Permission permission;
    switch (key) {
      case 'location':
        permission = Permission.locationWhenInUse;
        break;
      case 'activity':
        permission = Permission.activityRecognition;
        break;
      case 'notifications':
        permission = Permission.notification;
        break;
      case 'sms':
        permission = Permission.sms;
        break;
      default:
        permission = Permission.microphone;
    }

    final status = await permission.request();
    final granted = status.isGranted || status.isLimited;
    setState(() {
      final permissions = (_settings['permissions'] as Map?)?.cast<String, dynamic>() ?? {};
      permissions[key] = granted;
      _settings['permissions'] = permissions;
    });
    _scheduleAutosave(refreshMotion: key == 'location' || key == 'activity');
  }

  Future<void> _requestCallScreeningRole() async {
    final granted = await NativeTelecomService.requestCallScreeningRole();
    final status = await NativeTelecomService.getCallScreeningStatus();
    if (!mounted) return;
    setState(() => _callScreening = status);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'ZyroAi can now screen incoming calls on this device.'
              : 'Call-screening role was not granted.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final appearance = (_settings['appearance'] as Map?)?.cast<String, dynamic>() ?? {};
    final assistant = (_settings['assistant'] as Map?)?.cast<String, dynamic>() ?? {};
    final automation = (_settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
    final permissions = (_settings['permissions'] as Map?)?.cast<String, dynamic>() ?? {};
    final data = (_settings['data'] as Map?)?.cast<String, dynamic>() ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF171717), Color(0xFF0F1620), Color(0xFF0A0A0A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/zyroai-logo.jpg',
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ZyroAi Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Profile, appearance, automation, permissions, data policy, and device trust settings.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                _saving ? Icons.sync : Icons.check_circle_outline,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_autosaveStatus)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Profile',
          subtitle: 'Identity, language, location, and personal goals',
          child: Column(
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (value) {
                  _profile['name'] = value;
                  _scheduleAutosave();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (value) {
                  _profile['title'] = value;
                  _scheduleAutosave();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cityCtrl,
                decoration: const InputDecoration(labelText: 'City'),
                onChanged: (value) {
                  _profile['city'] = value;
                  _scheduleAutosave();
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _goalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Daily step goal'),
                onChanged: (_) => _scheduleAutosave(refreshMotion: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: (_profile['language'] ?? 'en').toString(),
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                  DropdownMenuItem(value: 'es', child: Text('Spanish')),
                  DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                ],
                onChanged: (value) {
                  setState(() => _profile['language'] = value);
                  if (value != null) {
                    widget.onLanguageChanged(value);
                  }
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Automation',
          subtitle: 'How ZyroAi behaves across focus, calls, and movement',
          child: Column(
            children: [
              _toggleTile(
                title: 'DND mode',
                subtitle: 'Arm the busy shield and call triage flow.',
                value: automation['dndMode'] == true,
                onChanged: (value) => setState(() {
                  automation['dndMode'] = value;
                  _settings['automation'] = automation;
                  _scheduleAutosave(syncNative: true);
                }),
              ),
              _toggleTile(
                title: 'Call auto-reply',
                subtitle: 'Allow ZyroAi to block supported incoming calls and log the interruption.',
                value: automation['callAutoReply'] != false,
                onChanged: (value) => setState(() {
                  automation['callAutoReply'] = value;
                  _settings['automation'] = automation;
                  _scheduleAutosave(syncNative: true);
                }),
              ),
              _toggleTile(
                title: 'Message autopilot',
                subtitle: 'Generate context-aware busy replies while you focus.',
                value: automation['smsAutoReply'] != false,
                onChanged: (value) => setState(() {
                  automation['smsAutoReply'] = value;
                  _settings['automation'] = automation;
                  _scheduleAutosave();
                }),
              ),
              _toggleTile(
                title: 'Smart step tracking',
                subtitle: 'Use the step sensor plus movement filtering to ignore vehicle travel.',
                value: automation['autoStepTracking'] == true,
                onChanged: (value) => setState(() {
                  automation['autoStepTracking'] = value;
                  _settings['automation'] = automation;
                  _scheduleAutosave(refreshMotion: true);
                }),
              ),
              _toggleTile(
                title: 'Wellbeing guard',
                subtitle: 'Keep reminders and healthy nudges active during the day.',
                value: automation['wellbeingGuard'] != false,
                onChanged: (value) => setState(() {
                  automation['wellbeingGuard'] = value;
                  _settings['automation'] = automation;
                  _scheduleAutosave();
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Assistant',
          subtitle: 'Control persona, reporting cadence, and live behavior',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: (assistant['voiceStyle'] ?? 'calm').toString(),
                decoration: const InputDecoration(labelText: 'Voice style'),
                items: const [
                  DropdownMenuItem(value: 'calm', child: Text('Calm')),
                  DropdownMenuItem(value: 'direct', child: Text('Direct')),
                  DropdownMenuItem(value: 'operator', child: Text('Operator')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => assistant['voiceStyle'] = value);
                  _settings['assistant'] = assistant;
                  _scheduleAutosave();
                },
              ),
              const SizedBox(height: 10),
              _toggleTile(
                title: 'Automatic decision support',
                subtitle: 'Let the assistant weigh options more proactively.',
                value: assistant['autoDecisionSupport'] != false,
                onChanged: (value) => setState(() {
                  assistant['autoDecisionSupport'] = value;
                  _settings['assistant'] = assistant;
                  _scheduleAutosave();
                }),
              ),
              _toggleTile(
                title: 'Weekly reports',
                subtitle: 'Keep the weekly executive summary active.',
                value: assistant['weeklyReports'] != false,
                onChanged: (value) => setState(() {
                  assistant['weeklyReports'] = value;
                  _settings['assistant'] = assistant;
                  _scheduleAutosave();
                }),
              ),
              _toggleTile(
                title: 'Monthly reports',
                subtitle: 'Maintain monthly performance snapshots.',
                value: assistant['monthlyReports'] != false,
                onChanged: (value) => setState(() {
                  assistant['monthlyReports'] = value;
                  _settings['assistant'] = assistant;
                  _scheduleAutosave();
                }),
              ),
              _toggleTile(
                title: 'Yearly reports',
                subtitle: 'Preserve annual review snapshots and trends.',
                value: assistant['yearlyReports'] != false,
                onChanged: (value) => setState(() {
                  assistant['yearlyReports'] = value;
                  _settings['assistant'] = assistant;
                  _scheduleAutosave();
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Permissions',
          subtitle: 'Request actual device access and keep permission state visible',
          child: Column(
            children: [
              _toggleTile(
                title: 'Location permission',
                subtitle: 'Needed for weather refresh and live movement tracking.',
                value: permissions['location'] == true,
                onChanged: (value) => value
                    ? _requestPermission('location')
                    : setState(() {
                        permissions['location'] = false;
                        _settings['permissions'] = permissions;
                        _scheduleAutosave(refreshMotion: true);
                      }),
              ),
              _toggleTile(
                title: 'Activity permission',
                subtitle: 'Needed for step sensor and smart walking detection.',
                value: permissions['activity'] == true,
                onChanged: (value) => value
                    ? _requestPermission('activity')
                    : setState(() {
                        permissions['activity'] = false;
                        _settings['permissions'] = permissions;
                        _scheduleAutosave(refreshMotion: true);
                      }),
              ),
              _toggleTile(
                title: 'Notifications permission',
                subtitle: 'Needed for milestone alerts and reminders.',
                value: permissions['notifications'] == true,
                onChanged: (value) => value
                    ? _requestPermission('notifications')
                    : setState(() {
                        permissions['notifications'] = false;
                        _settings['permissions'] = permissions;
                        _scheduleAutosave();
                      }),
              ),
              _toggleTile(
                title: 'Microphone permission',
                subtitle: 'Needed for voice assistant and speech translation.',
                value: permissions['microphone'] == true,
                onChanged: (value) => value
                    ? _requestPermission('microphone')
                    : setState(() {
                        permissions['microphone'] = false;
                        _settings['permissions'] = permissions;
                        _scheduleAutosave();
                      }),
              ),
              _toggleTile(
                title: 'SMS permission',
                subtitle: 'Needed for real busy-text auto replies and direct SMS sending.',
                value: permissions['sms'] == true,
                onChanged: (value) => value
                    ? _requestPermission('sms')
                    : setState(() {
                        permissions['sms'] = false;
                        _settings['permissions'] = permissions;
                        _scheduleAutosave();
                      }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Appearance',
          subtitle: 'Theme and visual density for the mobile surface',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: (appearance['theme'] ?? 'black-gold').toString(),
                decoration: const InputDecoration(labelText: 'Theme'),
                items: const [
                  DropdownMenuItem(value: 'black-gold', child: Text('Black Gold')),
                  DropdownMenuItem(value: 'black-ice', child: Text('Black Ice')),
                  DropdownMenuItem(value: 'obsidian-blue', child: Text('Obsidian Blue')),
                  DropdownMenuItem(value: 'carbon-emerald', child: Text('Carbon Emerald')),
                  DropdownMenuItem(value: 'graphite-silver', child: Text('Graphite Silver')),
                  DropdownMenuItem(value: 'midnight-rose', child: Text('Midnight Rose')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => appearance['theme'] = value);
                  _settings['appearance'] = appearance;
                  widget.onThemeChanged(value);
                  _scheduleAutosave();
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: (appearance['density'] ?? 'comfortable').toString(),
                decoration: const InputDecoration(labelText: 'Density'),
                items: const [
                  DropdownMenuItem(value: 'comfortable', child: Text('Comfortable')),
                  DropdownMenuItem(value: 'compact', child: Text('Compact')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => appearance['density'] = value);
                  _settings['appearance'] = appearance;
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Data and Sync',
          subtitle: 'Cloud behavior and offline strategy',
          child: Column(
            children: [
              _toggleTile(
                title: 'Realtime sync',
                subtitle: 'Keep workspace data synchronized live when the backend is reachable.',
                value: data['realtimeSync'] != false,
                onChanged: (value) => setState(() {
                  data['realtimeSync'] = value;
                  _settings['data'] = data;
                  _scheduleAutosave();
                }),
              ),
              _toggleTile(
                title: 'Offline ready',
                subtitle: 'Keep local cache behavior available when the network is down.',
                value: data['offlineReady'] != false,
                onChanged: (value) => setState(() {
                  data['offlineReady'] = value;
                  _settings['data'] = data;
                  _scheduleAutosave();
                }),
              ),
              _toggleTile(
                title: 'Auto sync when online',
                subtitle: 'Push local updates back to the cloud path as connectivity returns.',
                value: data['autoSyncWhenOnline'] != false,
                onChanged: (value) => setState(() {
                  data['autoSyncWhenOnline'] = value;
                  _settings['data'] = data;
                  _scheduleAutosave();
                }),
              ),
              if (kDebugMode)
                TextField(
                  controller: _apiBaseUrlCtrl,
                  decoration: const InputDecoration(labelText: 'Backend API base URL (Debug)'),
                  onChanged: (_) => _scheduleAutosave(syncNative: false, refreshMotion: false),
                )
              else
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Backend'),
                  subtitle: Text('Connected to the secure ZyroAi cloud endpoint'),
                ),
            ],
          ),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'Call Screening',
            subtitle: 'Native Android telecom role and DND screening state',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _callScreening['supported'] == true
                      ? (_callScreening['roleHeld'] == true
                          ? 'Native call-screening role is active.'
                          : 'Native call-screening role is not granted yet.')
                      : 'This Android version does not support the native screening role.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _callScreening['supported'] == true ? _requestCallScreeningRole : null,
                  child: Text(_callScreening['roleHeld'] == true ? 'Role Active' : 'Enable Call Screening'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Audit Logs',
          subtitle: '${_auditLogs.length} recent configuration and automation events',
          child: _auditLogs.isEmpty
              ? _emptyState('Audit events will appear here as you use the app.')
              : Column(
                  children: _auditLogs.take(8).map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry['action']?.toString() ?? 'action', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(entry['detail']?.toString() ?? ''),
                          const SizedBox(height: 4),
                          Text(
                            entry['created_at']?.toString() ?? '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          context,
          title: 'Device Info',
          subtitle: 'Live device information available to ZyroAi',
          child: Column(
            children: _deviceInfo.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 6, child: Text(entry.value)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Support', style: TextStyle(fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('Need help with updates, setup, or app behavior?'),
                    ],
                  ),
                ),
                TextButton(onPressed: _openSupport, child: const Text('Email Support')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : () => _save(showToast: true),
          child: Text(_saving ? 'Saving...' : 'Save Now'),
        ),
      ],
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SwitchListTile.adaptive(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _emptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text),
    );
  }
}
