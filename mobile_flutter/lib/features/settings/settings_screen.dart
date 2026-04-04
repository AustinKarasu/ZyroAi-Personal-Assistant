import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/api_service.dart';
import '../../core/services/motion_tracking_service.dart';
import '../../core/services/native_telecom_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _settings = {};
  Map<String, dynamic> _profile = {};
  Map<String, String> _deviceInfo = {};
  Map<String, dynamic> _callScreening = {'supported': false, 'roleHeld': false};
  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  final _apiBaseUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profileRes = await widget.api.fetchProfile();
    final settingsRes = await widget.api.fetchSettings();
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
    _apiBaseUrlCtrl.text = apiBaseUrl;

    setState(() {
      _profile = profile;
      _settings = settings;
      _deviceInfo = deviceInfo;
      _callScreening = callScreening;
      _loading = false;
    });
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

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.api.saveApiBaseUrl(_apiBaseUrlCtrl.text.trim());
    await widget.api.saveProfile({
      'name': _nameCtrl.text.trim(),
      'title': _titleCtrl.text.trim(),
      'daily_step_goal': int.tryParse(_goalCtrl.text) ?? 8000,
      'language': _profile['language'] ?? 'en',
    });
    await widget.api.saveSettings(_settings);
    final automation = (_settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
    if (Platform.isAndroid) {
      await NativeTelecomService.syncCallAutomation(
        dndMode: automation['dndMode'] == true,
        callAutoReply: automation['callAutoReply'] != false,
      );
      _callScreening = await NativeTelecomService.getCallScreeningStatus();
    }
    await MotionTrackingService.instance.refreshConfig();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
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

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _toggleTile({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final appearance = (_settings['appearance'] as Map?)?.cast<String, dynamic>() ?? {};
    final automation = (_settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
    final permissions = (_settings['permissions'] as Map?)?.cast<String, dynamic>() ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF171717), Color(0xFF0B0B0B)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/images/zyroai-logo.jpg',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ZyroAi Settings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Premium control for profile, privacy, DND, motion tracking, and support.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Profile', 'Identity, language, and step goals'),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 10),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 10),
                TextField(controller: _goalCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Daily step goal')),
                const SizedBox(height: 10),
                TextField(controller: _apiBaseUrlCtrl, decoration: const InputDecoration(labelText: 'Backend API base URL')),
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
                  onChanged: (value) => setState(() => _profile['language'] = value),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Automation', 'On or off controls for how ZyroAi behaves'),
                _toggleTile(
                  title: 'DND mode',
                  subtitle: 'Answer incoming calls with the busy AI message.',
                  value: automation['dndMode'] == true,
                  onChanged: (value) => setState(() {
                    automation['dndMode'] = value;
                    _settings['automation'] = automation;
                  }),
                ),
                _toggleTile(
                  title: 'Call auto-reply',
                  subtitle: 'Send the DND call response automatically.',
                  value: automation['callAutoReply'] != false,
                  onChanged: (value) => setState(() {
                    automation['callAutoReply'] = value;
                    _settings['automation'] = automation;
                  }),
                ),
                _toggleTile(
                  title: 'Smart step tracking',
                  subtitle: 'Use native step sensor plus location speed filtering.',
                  value: automation['autoStepTracking'] == true,
                  onChanged: (value) => setState(() {
                    automation['autoStepTracking'] = value;
                    _settings['automation'] = automation;
                  }),
                ),
              ],
            ),
          ),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Call Screening', 'Native Android telecom role and DND screening'),
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
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Permissions', 'Use switch controls and request actual device permissions'),
                _toggleTile(
                  title: 'Location permission',
                  subtitle: 'Allow weather refresh and live movement tracking.',
                  value: permissions['location'] == true,
                  onChanged: (value) => value
                      ? _requestPermission('location')
                      : setState(() {
                          permissions['location'] = false;
                          _settings['permissions'] = permissions;
                        }),
                ),
                _toggleTile(
                  title: 'Activity permission',
                  subtitle: 'Allow native step and movement tracking.',
                  value: permissions['activity'] == true,
                  onChanged: (value) => value
                      ? _requestPermission('activity')
                      : setState(() {
                          permissions['activity'] = false;
                          _settings['permissions'] = permissions;
                        }),
                ),
                _toggleTile(
                  title: 'Notifications permission',
                  subtitle: 'Allow reminders, alerts, and DND updates.',
                  value: permissions['notifications'] == true,
                  onChanged: (value) => value
                      ? _requestPermission('notifications')
                      : setState(() {
                          permissions['notifications'] = false;
                          _settings['permissions'] = permissions;
                        }),
                ),
                _toggleTile(
                  title: 'Microphone permission',
                  subtitle: 'Allow speech-to-text translation and voice assistant features.',
                  value: permissions['microphone'] == true,
                  onChanged: (value) => value
                      ? _requestPermission('microphone')
                      : setState(() {
                          permissions['microphone'] = false;
                          _settings['permissions'] = permissions;
                        }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Appearance', 'Executive theme controls'),
                DropdownButtonFormField<String>(
                  initialValue: (appearance['theme'] ?? 'black-gold').toString(),
                  decoration: const InputDecoration(labelText: 'Theme'),
                  items: const [
                    DropdownMenuItem(value: 'black-gold', child: Text('Black Gold')),
                    DropdownMenuItem(value: 'black-ice', child: Text('Black Ice')),
                    DropdownMenuItem(value: 'obsidian-blue', child: Text('Obsidian Blue')),
                  ],
                  onChanged: (value) => setState(() => appearance['theme'] = value),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Device Info', 'Live device information available to ZyroAi'),
                ..._deviceInfo.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                        const SizedBox(width: 8),
                        Expanded(flex: 6, child: Text(entry.value)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
                      Text('Need help with updates, setup, or account behavior?'),
                    ],
                  ),
                ),
                TextButton(onPressed: _openSupport, child: const Text('Email Support')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Apply Settings')),
      ],
    );
  }
}
