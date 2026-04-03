import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _logsFuture = widget.api.fetchCallLogs();
  }

  Future<void> _submitLog() async {
    if (_callerCtrl.text.isEmpty || _transcriptCtrl.text.isEmpty) return;
    await widget.api.submitCallLog(_callerCtrl.text.trim(), _transcriptCtrl.text.trim());
    _callerCtrl.clear();
    _transcriptCtrl.clear();
    setState(() => _logsFuture = widget.api.fetchCallLogs());
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
        children: [
          TextField(controller: _callerCtrl, decoration: const InputDecoration(labelText: 'Caller Name')),
          const SizedBox(height: 8),
          TextField(controller: _transcriptCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Call transcript')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _submitLog, child: const Text('Analyze')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _genReply, child: const Text('Auto-reply')),
          ]),
          if (_autoReply.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_autoReply)),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final logs = snapshot.data!;
                if (logs.isEmpty) return const Center(child: Text('No call logs yet'));
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(log['caller'].toString()),
                        subtitle: Text('Sentiment: ${log['sentiment']} | Urgency: ${log['urgency']}'),
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
