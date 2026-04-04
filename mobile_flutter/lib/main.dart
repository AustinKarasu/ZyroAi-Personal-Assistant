import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/chief_l10n.dart';
import 'core/chief_theme.dart';
import 'core/services/api_service.dart';
import 'core/services/motion_tracking_service.dart';
import 'core/services/native_telecom_service.dart';
import 'core/services/notification_service.dart';
import 'features/assistant/assistant_screen.dart';
import 'features/communication/communication_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/decision/decision_screen.dart';
import 'features/quests/quests_screen.dart';
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

class _ChiefAppState extends State<ChiefApp> with WidgetsBindingObserver {
  static const _installedVersionKey = 'installed_app_version';

  int _index = 0;
  final _api = ApiService();
  DateTime? _lastUpdateCheck;
  static const _updateCheckInterval = Duration(minutes: 30);
  String _themeName = 'black-gold';
  String _languageCode = 'en';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadTheme();
      await NotificationService.instance.init();
      await _handleInstalledVersionChange();
      await MotionTrackingService.instance.start(_api);
      await _maybeShowUpdatePrompt();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MotionTrackingService.instance.refreshConfig();
      _maybeShowUpdatePrompt(force: true);
    }
  }

  Future<void> _loadTheme() async {
    try {
      final settingsRes = await _api.fetchSettings();
      final settings = (settingsRes['settings'] as Map).cast<String, dynamic>();
      final appearance = (settings['appearance'] as Map?)?.cast<String, dynamic>() ?? {};
      final profileRes = await _api.fetchProfile();
      final profile = (profileRes['profile'] as Map).cast<String, dynamic>();
      final theme = (appearance['theme'] ?? 'black-gold').toString();
      final language = (profile['language'] ?? 'en').toString();
      if (!mounted) return;
      setState(() {
        _themeName = theme;
        _languageCode = language;
      });
    } catch (_) {}
  }

  void _onThemeChanged(String name) {
    if (!mounted) return;
    setState(() => _themeName = name);
  }

  void _onLanguageChanged(String code) {
    if (!mounted) return;
    setState(() => _languageCode = code);
  }

  Future<void> _handleInstalledVersionChange() async {
    final prefs = await SharedPreferences.getInstance();
    final previousVersion = prefs.getString(_installedVersionKey);
    String currentVersion = '1.1.11';

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
    final startedNativeInstall = url.isNotEmpty
        ? await NativeTelecomService.downloadAndInstallApk(
            url: url,
            version: latestVersion,
          )
        : false;
    if (!startedNativeInstall && url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<Map<String, dynamic>?> _loadUpdateCenter() async {
    try {
      final status = await _api.fetchUpdateStatus();
      return status.cast<String, dynamic>();
    } catch (_) {
      try {
        final workspace = await _api.fetchWorkspace();
        return (workspace['updateCenter'] as Map?)?.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  Future<void> _maybeShowUpdatePrompt({bool force = false}) async {
    if (!mounted) return;
    final now = DateTime.now();
    if (!force && _lastUpdateCheck != null && now.difference(_lastUpdateCheck!) < _updateCheckInterval) {
      return;
    }
    _lastUpdateCheck = now;

    try {
      final updateCenter = await _loadUpdateCenter();
      if (updateCenter == null || updateCenter['updateAvailable'] != true) return;

      final latestVersion = updateCenter['latestVersion']?.toString() ?? '';
      if (latestVersion.isEmpty) return;
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
          content: Text('Version $latestVersion is ready for ZyroAi. The app can download the new build and hand it to Android for installation without opening the browser.'),
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ZyroAi',
      locale: Locale(_languageCode),
      theme: ChiefTheme.fromName(_themeName),
      home: ChiefL10nScope(
        languageCode: _languageCode,
        child: Builder(
          builder: (context) {
            final l10n = ChiefL10nScope.of(context);
            final pages = [
              DashboardScreen(api: _api),
              CommunicationScreen(api: _api),
              DecisionScreen(api: _api),
              AssistantScreen(api: _api),
              QuestsScreen(api: _api),
              IntelligenceScreen(api: _api),
              MemoryScreen(api: _api),
              SettingsScreen(
                api: _api,
                onThemeChanged: _onThemeChanged,
                onLanguageChanged: _onLanguageChanged,
              ),
            ];
            final items = [
              (label: l10n.t('dashboard'), icon: Icons.space_dashboard_outlined),
              (label: l10n.t('comms'), icon: Icons.call_outlined),
              (label: l10n.t('decision'), icon: Icons.balance_outlined),
              (label: l10n.t('assistant'), icon: Icons.auto_awesome_outlined),
              (label: l10n.t('quests'), icon: Icons.workspace_premium_outlined),
              (label: l10n.t('intel'), icon: Icons.insights_outlined),
              (label: l10n.t('memory'), icon: Icons.memory_outlined),
              (label: l10n.t('settings'), icon: Icons.settings_outlined),
            ];

            return Scaffold(
              appBar: AppBar(
                toolbarHeight: 72,
                titleSpacing: 0,
                title: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/images/zyroai-logo.jpg',
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.t('appName'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(items[_index].label, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _themeName.replaceAll('-', ' '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              drawer: Drawer(
                backgroundColor: const Color(0xFF0B121D),
                child: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF16243F), Color(0xFF0D1627)]),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/images/zyroai-logo.jpg',
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Text(l10n.t('appName')),
                          subtitle: Text(items[_index].label),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _drawerChip(l10n.t('premiumUi')),
                            const SizedBox(width: 8),
                            _drawerChip(l10n.t('aiTools')),
                          ],
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _index == index ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                leading: Icon(item.icon),
                                title: Text(item.label),
                                selected: _index == index,
                                onTap: () {
                                  setState(() => _index = index);
                                  Navigator.of(context).pop();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: pages[_index],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _drawerChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text),
    );
  }
}
















