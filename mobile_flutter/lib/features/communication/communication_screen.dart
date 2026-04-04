import 'package:flutter/material.dart';

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
  String _autoReply = '';
  String _incomingSummary = '';
  bool _submitting = false;
  bool _dndMode = false;
  bool _callAutoReply = true;

  @override
  void initState() {
    super.initState();
    _logsFuture = widget.api.fetchCallLogs();
    _loadAutomation();
  }

  Future<void> _loadAutomation() async {
    try {
      final settings = await widget.api.fetchSettings();
      final automation = ((settings['settings'] as Map)['automation'] as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _dndMode = automation['dndMode'] == true;
        _callAutoReply = automation['callAutoReply'] != false;
      });
    } catch (_) {}
  }

  Future<void> _saveAutomation() async {
    await widget.api.saveSettings({
      'automation': {
        'dndMode': _dndMode,
        'callAutoReply': _callAutoReply,
      }
    });
    await NativeTelecomService.syncCallAutomation(
      dndMode: _dndMode,
      callAutoReply: _callAutoReply,
    );
  }

  Future<void> _reload() async {
    setState(() => _logsFuture = widget.api.fetchCallLogs());
  }

  Future<void> _submitLog() async {
    if (_callerCtrl.text.isEmpty || _transcriptCtrl.text.isEmpty) return;
    setState(() => _submitting = true);
    await widget.api.submitCallLog(_callerCtrl.text.trim(), _transcriptCtrl.text.trim());
    _callerCtrl.clear();
    _transcriptCtrl.clear();
    setState(() => _submitting = false);
    await _reload();
  }

  Future<void> _simulateIncomingCall() async {
    if (_callerCtrl.text.isEmpty || _transcriptCtrl.text.isEmpty) return;
    setState(() => _submitting = true);
    final response = await widget.api.handleIncomingCall(_callerCtrl.text.trim(), _transcriptCtrl.text.trim());
    setState(() {
      _incomingSummary = response['agentReply']?.toString().isNotEmpty == true
          ? response['agentReply'].toString()
          : response['summary']?.toString() ?? 'Incoming call processed.';
      _submitting = false;
    });
    await _reload();
  }

  Future<void> _genReply() async {
    final msg = await widget.api.generateAutoReply('Alex', 'meeting', '3:00 PM');
    setState(() => _autoReply = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Communications', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile.adaptive(
              title: const Text('DND call auto-handler'),
              subtitle: Text(_dndMode && _callAutoReply
                  ? 'Incoming calls will be handled with: "The person is currently busy, drop your message for the user."'
                  : 'Enable to auto-handle incoming calls in DND mode'),
              value: _dndMode && _callAutoReply,
              onChanged: (value) async {
                setState(() {
                  _dndMode = value;
                  _callAutoReply = value;
                });
                await _saveAutomation();
              },
            ),
          ),
          const SizedBox(height: 8),
          TextField(controller: _callerCtrl, decoration: const InputDecoration(labelText: 'Caller name or number')),
          const SizedBox(height: 8),
          TextField(controller: _transcriptCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Transcript or caller message')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _submitting ? null : _submitLog, child: Text(_submitting ? 'Working...' : 'Analyze Call')),
              OutlinedButton(onPressed: _submitting ? null : _simulateIncomingCall, child: const Text('Simulate Incoming Call')),
              OutlinedButton(onPressed: _genReply, child: const Text('Generate Auto Reply')),
              OutlinedButton(
                onPressed: () async {
                  await widget.api.clearCallLogs();
                  await _reload();
                },
                child: const Text('Clear History'),
              ),
            ],
          ),
          if (_autoReply.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_autoReply))),
          ],
          if (_incomingSummary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_incomingSummary))),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Communication feed failed: ${snapshot.error}'));
                }
                final logs = snapshot.data ?? [];
                if (logs.isEmpty) return const Center(child: Text('No call activity yet.'));
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final handledByDnd = log['handled_by_dnd'] == true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(log['caller'].toString()),
                        subtitle: Text(
                          handledByDnd
                              ? 'DND handled this call. Urgency ${log['urgency']} | ${log['agent_reply'] ?? ''}'
                              : 'Sentiment: ${log['sentiment']} | Urgency: ${log['urgency']}',
                        ),
                        trailing: Icon(
                          handledByDnd ? Icons.phone_disabled_outlined : Icons.call_outlined,
                        ),
                        onLongPress: () async {
                          await widget.api.deleteCallLog(log['id'].toString());
                          await _reload();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
