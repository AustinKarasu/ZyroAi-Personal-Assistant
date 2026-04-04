import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/api_service.dart';
import '../../core/services/native_telecom_service.dart';

class CommunicationScreen extends StatefulWidget {
  const CommunicationScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  late Future<List<Map<String, dynamic>>> _logsFuture;
  final _callerCtrl = TextEditingController();
  final _transcriptCtrl = TextEditingController();
  final _replyNumberCtrl = TextEditingController();
  final _replySenderCtrl = TextEditingController(text: 'Alex');
  final _replyUntilCtrl = TextEditingController(text: '3:00 PM');
  String _replyContext = 'meeting';
  String _autoReply = '';
  String _incomingSummary = '';
  bool _busy = false;
  bool _dndMode = false;
  bool _callAutoReply = true;
  bool _smsAutoReply = true;
  Map<String, dynamic> _nativeStatus = const {'supported': false, 'roleHeld': false};
  Map<String, dynamic> _integrations = const {};

  @override
  void initState() {
    super.initState();
    _logsFuture = widget.api.fetchCallLogs();
    _loadAutomation();
  }

  @override
  void dispose() {
    _callerCtrl.dispose();
    _transcriptCtrl.dispose();
    _replyNumberCtrl.dispose();
    _replySenderCtrl.dispose();
    _replyUntilCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAutomation() async {
    try {
      final settings = await widget.api.fetchSettings();
      final payload = (settings['settings'] as Map).cast<String, dynamic>();
      final automation = (payload['automation'] as Map?)?.cast<String, dynamic>() ?? {};
      final integrations = (payload['integrations'] as Map?)?.cast<String, dynamic>() ?? {};
      final nativeStatus = await NativeTelecomService.getCallScreeningStatus();
      if (!mounted) return;
      setState(() {
        _dndMode = automation['dndMode'] == true;
        _callAutoReply = automation['callAutoReply'] != false;
        _smsAutoReply = automation['smsAutoReply'] != false;
        _nativeStatus = nativeStatus;
        _integrations = integrations;
      });
    } catch (_) {}
  }

  Future<void> _saveAutomation() async {
    await widget.api.saveSettings({
      'automation': {
        'dndMode': _dndMode,
        'callAutoReply': _callAutoReply,
        'smsAutoReply': _smsAutoReply,
      }
    });
    await NativeTelecomService.syncCallAutomation(
      dndMode: _dndMode,
      callAutoReply: _callAutoReply,
      smsAutoReply: _smsAutoReply,
    );
    _nativeStatus = await NativeTelecomService.getCallScreeningStatus();
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    setState(() => _logsFuture = widget.api.fetchCallLogs());
  }

  Future<void> _submitLog() async {
    if (_callerCtrl.text.isEmpty || _transcriptCtrl.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.submitCallLog(_callerCtrl.text.trim(), _transcriptCtrl.text.trim());
      _callerCtrl.clear();
      _transcriptCtrl.clear();
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulateIncomingCall() async {
    if (_callerCtrl.text.isEmpty || _transcriptCtrl.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final response = await widget.api.handleIncomingCall(
        _callerCtrl.text.trim(),
        _transcriptCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _incomingSummary = response['agentReply']?.toString().isNotEmpty == true
            ? response['agentReply'].toString()
            : response['summary']?.toString() ?? 'Incoming call processed.';
      });
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _genReply() async {
    setState(() => _busy = true);
    try {
      final msg = await widget.api.generateAutoReply(
        _replySenderCtrl.text.trim().isEmpty ? 'Alex' : _replySenderCtrl.text.trim(),
        _replyContext,
        _replyUntilCtrl.text.trim().isEmpty ? 'later today' : _replyUntilCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _autoReply = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestNativeRole() async {
    final granted = await NativeTelecomService.requestCallScreeningRole();
    _nativeStatus = await NativeTelecomService.getCallScreeningStatus();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Native call screening is active for ZyroAi.'
              : 'Call-screening role is still not granted on this device.',
        ),
      ),
    );
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    _nativeStatus = await NativeTelecomService.getCallScreeningStatus();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status.isGranted
              ? 'SMS permission granted. ZyroAi can now send real device texts.'
              : 'SMS permission was not granted.',
        ),
      ),
    );
  }

  Future<void> _sendGeneratedSms() async {
    final number = _replyNumberCtrl.text.trim();
    if (number.isEmpty || _autoReply.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final sent = await NativeTelecomService.sendSms(
        phoneNumber: number,
        message: _autoReply.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sent ? 'SMS sent to $number.' : 'SMS could not be sent. Check SMS permission and number format.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _nativeStatus = await NativeTelecomService.getCallScreeningStatus();
      if (mounted) setState(() {});
    }
  }

  Future<void> _authorizePlatform(String platform) async {
    setState(() => _busy = true);
    try {
      final response = await widget.api.authorizeIntegration(
        platform,
        permissions: const ['read_messages', 'send_messages', 'read_status'],
      );
      if (!mounted) return;
      final integration = (response['integration'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _integrations = {
          ..._integrations,
          platform: integration,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_platformLabel(platform)} authorization saved for this device.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nativeReady = _nativeStatus['roleHeld'] == true;
    final smsReady = _nativeStatus['smsPermissionGranted'] == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF15171D), Color(0xFF111A29), Color(0xFF0B1016)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Communications Command', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Call triage, DND automation, message autopilot, and connected channel controls in one operator console.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip('DND', _dndMode ? 'On' : 'Off'),
                  _statusChip('Call shield', _callAutoReply ? 'Armed' : 'Off'),
                  _statusChip('Message autopilot', _smsAutoReply ? 'On' : 'Off'),
                  _statusChip('Native screening', nativeReady ? 'Active' : 'Needs role'),
                  _statusChip('SMS sending', smsReady ? 'Ready' : 'Needs permission'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DND Call Handling', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-handle incoming calls'),
                  subtitle: Text(
                    _dndMode && _callAutoReply
                        ? 'ZyroAi will reject supported incoming calls through Android call screening and log the caller context when DND is active.'
                        : 'Enable this to keep calls from breaking focus blocks.',
                  ),
                  value: _dndMode && _callAutoReply,
                  onChanged: (value) async {
                    setState(() {
                      _dndMode = value;
                      _callAutoReply = value;
                    });
                    await _saveAutomation();
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-draft busy message replies'),
                  subtitle: const Text('Keeps message response logic aligned with DND mode and current context.'),
                  value: _smsAutoReply,
                  onChanged: (value) async {
                    setState(() => _smsAutoReply = value);
                    await _saveAutomation();
                  },
                ),
                const SizedBox(height: 8),
                if (!nativeReady)
                  OutlinedButton.icon(
                    onPressed: _nativeStatus['supported'] == true ? _requestNativeRole : null,
                    icon: const Icon(Icons.phone_in_talk_outlined),
                    label: Text(_nativeStatus['supported'] == true ? 'Enable Native Screening' : 'Screening Not Supported'),
                  ),
                if (nativeReady) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Live behavior: Android call-screening can silence or reject supported incoming calls while DND is armed. It cannot speak a custom voice line on SIM calls, but ZyroAi will log and summarize the interruption.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      smsReady
                          ? 'Real SMS fallback is enabled. When a screened call is rejected during DND, ZyroAi can send the busy reply as a real text message.'
                          : 'Grant SMS permission to let ZyroAi send a real busy text to callers during DND.',
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: smsReady ? null : _requestSmsPermission,
                  icon: const Icon(Icons.sms_outlined),
                  label: Text(smsReady ? 'SMS Permission Active' : 'Enable SMS Replies'),
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
                const Text('Call Intake Lab', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(
                  controller: _callerCtrl,
                  decoration: const InputDecoration(labelText: 'Caller name or number'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _transcriptCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Caller transcript or message'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _submitLog,
                      icon: const Icon(Icons.analytics_outlined),
                      label: Text(_busy ? 'Working...' : 'Analyze Call'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _simulateIncomingCall,
                      icon: const Icon(Icons.call_received_outlined),
                      label: const Text('Test Incoming Call'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await widget.api.clearCallLogs();
                        await _reload();
                      },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Clear History'),
                    ),
                  ],
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
                const Text('Messaging Auto-Reply Lab', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replySenderCtrl,
                        decoration: const InputDecoration(labelText: 'Sender'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _replyUntilCtrl,
                        decoration: const InputDecoration(labelText: 'Busy until'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _replyContext,
                  decoration: const InputDecoration(labelText: 'Context'),
                  items: const [
                    DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                    DropdownMenuItem(value: 'deep_work', child: Text('Deep Work')),
                    DropdownMenuItem(value: 'driving', child: Text('Driving')),
                    DropdownMenuItem(value: 'busy', child: Text('Busy')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _replyContext = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _replyNumberCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Recipient phone number'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _genReply,
                      icon: const Icon(Icons.mark_chat_read_outlined),
                      label: const Text('Generate Reply'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _autoReply.isEmpty
                          ? null
                          : () => setState(() {
                                _autoReply = '';
                              }),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                if (_autoReply.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(_autoReply),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: (_busy || !smsReady || _replyNumberCtrl.text.trim().isEmpty)
                        ? null
                        : _sendGeneratedSms,
                    icon: const Icon(Icons.send_to_mobile_outlined),
                    label: const Text('Send Real SMS'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_incomingSummary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Latest DND Action', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_incomingSummary),
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
                const Text('Connected Channels', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                const Text(
                  'Authorize channels on this device so ZyroAi can store consent state, automation preferences, and reply context.',
                ),
                const SizedBox(height: 12),
                ...['whatsapp', 'instagram', 'facebook', 'messenger', 'x'].map((platform) {
                  final meta = (_integrations[platform] as Map?)?.cast<String, dynamic>() ?? {};
                  final connected = meta['connected'] == true;
                  final permissions = ((meta['permissions'] as List?) ?? const []).join(', ');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_platformLabel(platform), style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(
                                connected ? 'Authorized for $permissions' : 'Not authorized yet',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonal(
                          onPressed: _busy ? null : () => _authorizePlatform(platform),
                          child: Text(connected ? 'Refresh Auth' : 'Authorize'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _logsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Communication feed failed: ${snapshot.error}'));
            }
            final logs = snapshot.data ?? [];
            if (logs.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No call activity yet. Once calls are analyzed or screened, they will appear here.'),
                ),
              );
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recent Calls', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 10),
                    ...logs.map((log) {
                      final handledByDnd = log['handled_by_dnd'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: handledByDnd
                                ? Colors.orange.withValues(alpha: 0.18)
                                : Colors.blue.withValues(alpha: 0.18),
                            child: Icon(
                              handledByDnd ? Icons.phone_disabled_outlined : Icons.call_outlined,
                              size: 18,
                            ),
                          ),
                          title: Text(log['caller'].toString()),
                          subtitle: Text(
                            handledByDnd
                                ? 'DND handled this call | Urgency ${log['urgency']} | ${log['agent_reply'] ?? ''}'
                                : 'Sentiment ${log['sentiment']} | Urgency ${log['urgency']}',
                          ),
                          trailing: IconButton(
                            onPressed: () async {
                              await widget.api.deleteCallLog(log['id'].toString());
                              await _reload();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _statusChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$label: $value'),
    );
  }

  String _platformLabel(String platform) {
    switch (platform) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'instagram':
        return 'Instagram';
      case 'facebook':
        return 'Facebook';
      case 'messenger':
        return 'Messenger';
      case 'x':
        return 'X';
      default:
        return platform;
    }
  }
}
