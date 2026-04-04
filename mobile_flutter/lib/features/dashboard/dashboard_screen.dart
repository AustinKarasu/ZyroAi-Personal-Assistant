import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _titleCtrl = TextEditingController();
  late Future<Map<String, dynamic>> _dashboardFuture;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _savingTask = false;
  bool _updatingMode = false;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _load();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final workspace = await widget.api.fetchWorkspace();
    final dashboard = await widget.api.fetchDashboard();
    return {
      'workspace': workspace,
      'dashboard': dashboard,
    };
  }

  Future<void> _refresh() async {
    setState(() => _dashboardFuture = _load());
  }

  Future<void> _addTask() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _savingTask = true);
    await widget.api.createTask(title: title, urgency: 4, importance: 4, energyCost: 3);
    _titleCtrl.clear();
    setState(() => _savingTask = false);
    await _refresh();
  }

  Future<void> _setMode(String mode) async {
    setState(() => _updatingMode = true);
    await widget.api.setMode(mode);
    setState(() => _updatingMode = false);
    await _refresh();
  }

  Future<void> _toggleTaskStatus(Map<String, dynamic> task) async {
    final current = task['status']?.toString() ?? 'todo';
    final next = switch (current) {
      'todo' => 'in_progress',
      'in_progress' => 'done',
      _ => 'todo',
    };
    await widget.api.updateTaskStatus(task['id'].toString(), next);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';
    final dateLabel = '${_now.day}/${_now.month}/${_now.year}';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF090E1A), Color(0xFF0E1A30), Color(0xFF07101F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Dashboard failed: ${snapshot.error}'),
              ),
            );
          }

          final workspace = (snapshot.data!['workspace'] as Map).cast<String, dynamic>();
          final dashboard = (snapshot.data!['dashboard'] as Map).cast<String, dynamic>();
          final kpis = (workspace['kpis'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          final tasks = (dashboard['topPriorities'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          final notifications = (workspace['notifications'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          final steps = (workspace['steps'] as Map?)?.cast<String, dynamic>() ?? {};
          final overview = (workspace['overview'] as Map?)?.cast<String, dynamic>() ?? {};

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Executive Dashboard', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text('Live operations center for tasks, mode, and momentum.'),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _infoChip(Icons.calendar_today, dateLabel),
                            const SizedBox(width: 8),
                            _infoChip(Icons.schedule, timeLabel),
                            const SizedBox(width: 8),
                            _infoChip(Icons.shield_outlined, overview['automationStatus']?.toString() ?? 'Automation stable'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(labelText: 'Create high-impact task'),
                        onSubmitted: (_) => _addTask(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _savingTask ? null : _addTask,
                      child: Text(_savingTask ? 'Saving...' : 'Create'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _updatingMode ? null : () => _setMode('Deep Work'),
                      icon: const Icon(Icons.psychology_alt_outlined),
                      label: const Text('Deep Work'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _updatingMode ? null : () => _setMode('Executive'),
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('Executive'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _updatingMode ? null : () => _setMode('Available'),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Available'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await widget.api.clearTasks();
                        await _refresh();
                      },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Clear Tasks'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: kpis.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.45,
                  ),
                  itemBuilder: (context, index) {
                    final item = kpis[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['label'].toString(), style: Theme.of(context).textTheme.bodySmall),
                            const Spacer(),
                            Text(item['value'].toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text(item['delta'].toString(), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Step Progress', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('${steps['count'] ?? 0} / ${steps['goal'] ?? 8000}'),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          minHeight: 10,
                          value: ((steps['progress'] ?? 0) as num).toDouble() / 100,
                          borderRadius: BorderRadius.circular(18),
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
                        const Text('Top Priorities', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 10),
                        if (tasks.isEmpty)
                          const Text('No tasks yet')
                        else
                          ...tasks.map((task) {
                            final status = task['status']?.toString() ?? 'todo';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                title: Text(task['title'].toString()),
                                subtitle: Text('Priority ${task['priority_score'] ?? 0} • ${status.replaceAll('_', ' ')}'),
                                trailing: OutlinedButton(
                                  onPressed: () => _toggleTaskStatus(task),
                                  child: const Text('Next'),
                                ),
                              ),
                            );
                          }),
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
                        const Text('Alerts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 8),
                        if (notifications.isEmpty)
                          const Text('No alerts right now')
                        else
                          ...notifications.take(4).map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.notifications_active_outlined, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(item['detail']?.toString() ?? item['title']?.toString() ?? 'Alert')),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
