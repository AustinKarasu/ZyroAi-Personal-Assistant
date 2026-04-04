import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/chief_theme.dart';
import 'core/services/api_service.dart';
import 'core/services/motion_tracking_service.dart';
import 'features/communication/communication_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/decision/decision_screen.dart';
import 'features/settings/intelligence_screen.dart';
import 'features/settings/memory_screen.dart';
import 'features/settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChiefApp());
}

class ChiefApp extends StatefulWidget {
  const ChiefApp({super.key});

  @override
  State<ChiefApp> createState() => _ChiefAppState();
}

class _ChiefAppState extends State<ChiefApp> {
  static const _installedVersionKey = 'installed_app_version';

  int _index = 0;
  final _api = ApiService();
  bool _updatePromptChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _handleInstalledVersionChange();
      await MotionTrackingService.instance.start(_api);
      await _maybeShowUpdatePrompt();
    });
  }

  Future<void> _handleInstalledVersionChange() async {
    final prefs = await SharedPreferences.getInstance();
    final previousVersion = prefs.getString(_installedVersionKey);
    String currentVersion = '1.1.5';

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.version.isNotEmpty) {
        currentVersion = packageInfo.version;
      }
    } on MissingPluginException {
      // Keep fallback version when plugin isn't available on this runtime.
    } on PlatformException {
      // Keep fallback version when package_info platform channel fails.
    } catch (_) {
      // Keep fallback version as a safe default.
    }

    if (previousVersion != null && previousVersion != currentVersion) {
      await _api.clearLocalCache();
    }

    await prefs.setString(_installedVersionKey, currentVersion);
  }

  Future<void> _runUpdateFlow(String latestVersion, String url) async {
    await _api.clearAllLocalState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(MotionTrackingService.instance.dismissedUpdateVersionKey, latestVersion);
    if (url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _maybeShowUpdatePrompt() async {
    if (!mounted || _updatePromptChecked) return;
    _updatePromptChecked = true;

    try {
      final workspace = await _api.fetchWorkspace();
      final updateCenter = (workspace['updateCenter'] as Map?)?.cast<String, dynamic>();
      if (updateCenter == null || updateCenter['updateAvailable'] != true) return;

      final latestVersion = updateCenter['latestVersion']?.toString() ?? '';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(MotionTrackingService.instance.dismissedUpdateVersionKey) == latestVersion) {
        return;
      }

      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Update Available'),
          content: Text('Version $latestVersion is ready for ZyroAi. Updating will clear local cache so the new build starts clean.'),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setString(MotionTrackingService.instance.dismissedUpdateVersionKey, latestVersion);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () async {
                final url = updateCenter['downloadUrl']?.toString() ?? '';
                if (context.mounted) Navigator.of(context).pop();
                await _runUpdateFlow(latestVersion, url);
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(api: _api),
      CommunicationScreen(api: _api),
      DecisionScreen(api: _api),
      IntelligenceScreen(api: _api),
      MemoryScreen(api: _api),
      SettingsScreen(api: _api),
    ];

    const items = [
      (label: 'Dashboard', icon: Icons.space_dashboard_outlined),
      (label: 'Comms', icon: Icons.call_outlined),
      (label: 'Decision', icon: Icons.balance_outlined),
      (label: 'Intel', icon: Icons.insights_outlined),
      (label: 'Memory', icon: Icons.memory_outlined),
      (label: 'Settings', icon: Icons.settings_outlined),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZyroAi',
      theme: ChiefTheme.light,
      home: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/zyroai-logo.jpg',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('ZyroAi'),
                  Text(items[_index].label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/zyroai-logo.jpg',
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                    ),
                  ),
                  title: const Text('ZyroAi'),
                  subtitle: const Text('Executive mobile control center'),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        selected: _index == index,
                        onTap: () {
                          setState(() => _index = index);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        body: pages[_index],
      ),
    );
  }
}
