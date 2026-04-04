import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/chief_l10n.dart';
import '../../core/services/api_service.dart';
import '../../core/services/motion_tracking_service.dart';
import '../../core/services/native_telecom_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _messageCtrl = TextEditingController();
  late Future<Map<String, dynamic>> _workspaceFuture;
  final List<Map<String, String>> _pendingMessages = [];
  bool _loading = false;
  String _assistantStatus = 'Ready';

  @override
  void initState() {
    super.initState();
    _workspaceFuture = widget.api.fetchWorkspace();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _workspaceFuture = widget.api.fetchWorkspace());
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _messageCtrl.text).trim();
    if (text.isEmpty || _loading) return;
    final l10n = ChiefL10nScope.of(context);

    setState(() {
      _loading = true;
      _assistantStatus = l10n.t('assistantThinking');
      _pendingMessages
        ..clear()
        ..add({'role': 'user', 'text': text});
      if (preset == null) {
        _messageCtrl.clear();
      }
    });

    try {
      final response = await widget.api.chat(text);
      final action = response['action']?.toString();
      if (!mounted) return;
      final settingsPayload = await widget.api.fetchSettings();
      final settings = (settingsPayload['settings'] as Map).cast<String, dynamic>();
      final automation = (settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
      if (Platform.isAndroid) {
        await NativeTelecomService.syncCallAutomation(
          dndMode: automation['dndMode'] == true,
          callAutoReply: automation['callAutoReply'] != false,
          smsAutoReply: automation['smsAutoReply'] != false,
        );
      }
      await MotionTrackingService.instance.refreshConfig();
      if (!mounted) return;
      setState(() {
        _assistantStatus = action?.isNotEmpty == true
            ? 'Action completed: $action'
            : l10n.t('assistantReady');
        _pendingMessages.clear();
        _workspaceFuture = widget.api.fetchWorkspace();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _assistantStatus = l10n.t('assistantFailed');
        _pendingMessages.add({
          'role': 'assistant',
          'text': 'Assistant request failed: $error',
        });
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _workspaceFuture,
      builder: (context, snapshot) {
        final l10n = ChiefL10nScope.of(context);
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Assistant failed: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.t('refresh')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final workspace = snapshot.data!;
        final overview = (workspace['overview'] as Map?)?.cast<String, dynamic>() ?? {};
        final settings = (workspace['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        final automation = (settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
        final assistant = (workspace['assistant'] as Map?)?.cast<String, dynamic>() ?? {};
        final suggestions = (assistant['suggestions'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();
        final persistedMessages = (assistant['messages'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((entry) => {
                  'role': entry['role']?.toString() ?? 'assistant',
                  'text': entry['content']?.toString() ?? '',
                })
            .toList();
        final conversation = [...persistedMessages, ..._pendingMessages];
        final steps = (workspace['steps'] as Map?)?.cast<String, dynamic>() ?? {};
        final weather = (workspace['weather'] as Map?)?.cast<String, dynamic>();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF15181F), Color(0xFF0F1826), Color(0xFF0A1017)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('aiChief'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Executive operator for planning, prioritization, DND commands, communication drafts, and decision support.',
                    style: TextStyle(fontSize: 16, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusChip(context, 'Mode', overview['liveMode']?.toString() ?? 'Executive'),
                      _statusChip(context, 'DND', automation['dndMode'] == true ? 'Armed' : 'Off'),
                      _statusChip(context, 'Steps', '${steps['count'] ?? 0}'),
                      _statusChip(
                        context,
                        'Weather',
                        weather == null ? 'Cache ready' : weather['summary']?.toString() ?? 'Live',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _toolRail(context),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(l10n.t('aiTools'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        TextButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(l10n.t('refresh')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suggestions.map((item) {
                        return ActionChip(
                          label: Text(item),
                          onPressed: () => _sendMessage(item),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _messageCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Ask ZyroAi',
                        hintText: 'Example: Turn on DND, plan my next three hours, and tell me what to handle first.',
                        prefixIcon: Icon(Icons.auto_awesome_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _sendMessage,
                            icon: const Icon(Icons.send_outlined),
                            label: Text(_loading ? l10n.t('working') : l10n.t('send')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: conversation.isEmpty
                              ? null
                              : () => setState(() {
                                    _pendingMessages.clear();
                                    _assistantStatus = 'Conversation cleared';
                                  }),
                          child: Text(l10n.t('clear')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _assistantStatus,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(l10n.t('conversationFeed'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          '${conversation.length} messages',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (conversation.isEmpty)
                      _emptyState('Start a conversation and ZyroAi will answer here with action-aware guidance.')
                    else
                      ...conversation.map((entry) {
                        final isAssistant = entry['role'] == 'assistant';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Align(
                            alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isAssistant
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isAssistant ? 'ZyroAi' : 'You',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(entry['text'] ?? ''),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolRail(BuildContext context) {
    final tools = [
      ('Daily Brief', 'Plan my afternoon with priorities and meetings', Icons.today_outlined),
      ('Weather + Steps', 'How is the weather and step progress?', Icons.cloud_outlined),
      ('Busy Reply', 'Draft a polite busy reply', Icons.mark_chat_read_outlined),
      ('Weekly Review', 'Generate my weekly report', Icons.insights_outlined),
    ];

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = tools[index];
          return SizedBox(
            width: 220,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _sendMessage(item.$2),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.$3, color: Theme.of(context).colorScheme.secondary),
                    const Spacer(),
                    Text(item.$1, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(item.$2, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text('$label: $value'),
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
