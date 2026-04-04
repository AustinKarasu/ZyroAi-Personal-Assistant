import 'package:flutter/material.dart';

import '../../core/chief_l10n.dart';
import '../../core/services/api_service.dart';

class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final response = await widget.api.fetchQuests();
    return (response['quests'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  Future<void> _toggleQuest(Map<String, dynamic> quest, bool nextValue) async {
    setState(() => _busy = true);
    try {
      await widget.api.toggleQuest(quest['id'].toString(), nextValue);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(nextValue ? 'Quest completed.' : 'Quest reopened.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Quest update failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ChiefL10nScope.of(context);

    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Quests failed: ${snapshot.error}', textAlign: TextAlign.center),
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

        final questsPayload = snapshot.data ?? {};
        final items = (questsPayload['items'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0).compareTo((b['order'] as num?)?.toInt() ?? 0));
        final completed = items.where((item) => item['completed'] == true).length;
        final progress = items.isEmpty ? 0.0 : completed / items.length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF161A1A), Color(0xFF0F2018), Color(0xFF0A1112)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.t('quests'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('Daily wellness missions generated from your current routine, movement goals, and healthy-lifestyle patterns.'),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip('${items.length} live quests'),
                        _chip('$completed completed'),
                        _chip('${(progress * 100).round()}% progress'),
                        _chip((questsPayload['source'] ?? 'smart-local').toString()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      minHeight: 10,
                      value: progress,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.t('refresh')),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Refreshes from the backend once the daily set changes.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No quests are ready yet. Pull to refresh and ZyroAi will generate today\'s set.'),
                  ),
                )
              else
                ...items.map((quest) {
                  final done = quest['completed'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: done
                                    ? Colors.green.withValues(alpha: 0.18)
                                    : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(done ? Icons.check : Icons.flag_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    quest['title']?.toString() ?? 'Quest',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(quest['detail']?.toString() ?? ''),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _chip((quest['category'] ?? 'wellness').toString()),
                                      _chip((quest['target'] ?? 'daily').toString()),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Switch.adaptive(
                              value: done,
                              onChanged: _busy ? null : (value) => _toggleQuest(quest, value),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text),
    );
  }
}
