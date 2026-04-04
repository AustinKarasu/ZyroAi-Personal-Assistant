import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chief_l10n.dart';
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
    try {
      await widget.api.createTask(
        title: title,
        urgency: 5,
        importance: 5,
        energyCost: 3,
      );
      _titleCtrl.clear();
      await _refresh();
    } finally {
      if (mounted) setState(() => _savingTask = false);
    }
  }

  Future<void> _setMode(String mode) async {
    setState(() => _updatingMode = true);
    try {
      await widget.api.setMode(mode);
      await _refresh();
    } finally {
      if (mounted) setState(() => _updatingMode = false);
    }
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
    final l10n = ChiefL10nScope.of(context);
    final timeLabel =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';
    final dateLabel = '${_now.day}/${_now.month}/${_now.year}';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF06090E), Color(0xFF0D1522), Color(0xFF09111D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Dashboard failed: ${snapshot.error}', textAlign: TextAlign.center),
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

          final workspace = (snapshot.data!['workspace'] as Map).cast<String, dynamic>();
          final dashboard = (snapshot.data!['dashboard'] as Map).cast<String, dynamic>();
          final overview = (workspace['overview'] as Map?)?.cast<String, dynamic>() ?? {};
          final profile = (workspace['profile'] as Map?)?.cast<String, dynamic>() ?? {};
          final weather = (workspace['weather'] as Map?)?.cast<String, dynamic>();
          final steps = (workspace['steps'] as Map?)?.cast<String, dynamic>() ?? {};
          final reports = ((workspace['reports'] as Map?)?['latest'] as Map?)?.cast<String, dynamic>() ?? {};
          final weeklyReport = (reports['weekly'] as Map?)?.cast<String, dynamic>() ?? {};
          final weeklyHighlights = (weeklyReport['highlights'] as List<dynamic>? ?? const []).cast<String>();
          final kpis = (workspace['kpis'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          final focusBlocks = (workspace['focusBlocks'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          final agenda = (workspace['agenda'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          final notifications = (workspace['notifications'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          final tasks = (dashboard['topPriorities'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _heroCard(
                  context,
                  title: '${profile['name'] ?? l10n.t('appName')} is in ${overview['liveMode'] ?? l10n.t('dashboard')} mode',
                  subtitle: overview['automationStatus']?.toString() ??
                      'Automation is stable and your workspace is synchronized.',
                  dateLabel: dateLabel,
                  timeLabel: timeLabel,
                  timezoneLabel: profile['timezone']?.toString() ?? 'Local timezone',
                  score: '${overview['executiveScore'] ?? '--'}',
                ),
                const SizedBox(height: 14),
                _quickTaskComposer(context),
                const SizedBox(height: 14),
                _modeStrip(context, overview['liveMode']?.toString() ?? 'Executive'),
                const SizedBox(height: 14),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: kpis.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.18,
                  ),
                  itemBuilder: (context, index) {
                    final item = kpis[index];
                    return _metricCard(
                      context,
                      label: item['label']?.toString() ?? 'Metric',
                      value: item['value']?.toString() ?? '--',
                      detail: item['delta']?.toString() ?? '',
                    );
                  },
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  title: 'Today at a Glance',
                  subtitle: weather != null ? 'Live weather and movement are active' : 'Weather cache ready',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _glanceTile(
                              context,
                              icon: Icons.wb_sunny_outlined,
                              title: 'Weather',
                              detail: weather == null
                                  ? 'Refresh weather from Intelligence after allowing location.'
                                  : '${weather['summary']} • ${weather['temperatureC']} C',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _glanceTile(
                              context,
                              icon: Icons.directions_walk_outlined,
                              title: 'Footsteps',
                              detail:
                                  '${steps['count'] ?? 0} / ${steps['goal'] ?? 8000} • ${steps['progress'] ?? 0}% complete',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _glanceTile(
                        context,
                        icon: Icons.auto_awesome_motion_outlined,
                        title: 'Weekly Brief',
                        detail: weeklyHighlights.isEmpty
                            ? 'Your next weekly executive summary will appear here.'
                            : weeklyHighlights.first,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  title: l10n.t('topPriorities'),
                  subtitle: tasks.isEmpty ? 'No open priorities yet' : '${tasks.length} tasks ranked by the priority engine',
                  action: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.t('refresh')),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await widget.api.clearTasks();
                          await _refresh();
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text(l10n.t('clear')),
                      ),
                    ],
                  ),
                  child: tasks.isEmpty
                      ? _emptyState('Add a high-impact task and ZyroAi will place it into your command queue.')
                      : Column(
                          children: tasks.map((task) {
                            final status = task['status']?.toString() ?? 'todo';
                            final priority = task['priority_score']?.toString() ?? '0';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.flag_outlined),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          task['title']?.toString() ?? 'Untitled task',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Priority $priority | ${status.replaceAll('_', ' ')}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton(
                                    onPressed: () => _toggleTaskStatus(task),
                                    child: const Text('Advance'),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  title: 'Live Focus Blocks',
                  subtitle: '${focusBlocks.length} blocks generated',
                  child: focusBlocks.isEmpty
                      ? _emptyState('Once you have a few ranked tasks, ZyroAi will generate protected focus sessions here.')
                      : Column(
                          children: focusBlocks.map((block) {
                            return _timelineTile(
                              context,
                              title: block['note']?.toString() ?? 'Focus session ready',
                              subtitle:
                                  'Starts in ${block['startInMinutes'] ?? 0} min • ${block['durationMinutes'] ?? 0} minute session',
                              icon: Icons.psychology_alt_outlined,
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  title: 'Agenda Timeline',
                  subtitle: '${agenda.length} meetings scheduled',
                  child: agenda.isEmpty
                      ? _emptyState('Your next meetings and action-ready prep will appear here.')
                      : Column(
                          children: agenda.map((meeting) {
                            final startAt = DateTime.tryParse(meeting['start_at']?.toString() ?? '');
                            return _timelineTile(
                              context,
                              title: meeting['title']?.toString() ?? 'Meeting',
                              subtitle:
                                  '${startAt != null ? '${startAt.day}/${startAt.month} ${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')}' : 'Scheduled'} • ${meeting['owner'] ?? 'Owner'}',
                              icon: Icons.event_outlined,
                            );
                          }).toList(),
                        ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  title: 'Alert Stack',
                  subtitle: '${notifications.length} live updates',
                  child: notifications.isEmpty
                      ? _emptyState('Alerts, automation changes, and activity signals will surface here.')
                      : Column(
                          children: notifications.take(6).map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _severityColor(item['severity']?.toString()).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _severityColor(item['severity']?.toString()).withValues(alpha: 0.24),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title']?.toString() ?? 'Alert',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(item['detail']?.toString() ?? ''),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _heroCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String dateLabel,
    required String timeLabel,
    required String timezoneLabel,
    required String score,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14191F), Color(0xFF0E1828), Color(0xFF0B1117)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ChiefL10nScope.of(context).t('executiveDashboard'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(score, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    Text('Score', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip(Icons.calendar_today_outlined, dateLabel),
              _heroChip(Icons.schedule_outlined, timeLabel),
              _heroChip(Icons.public_outlined, timezoneLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickTaskComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Drop a high-impact task into ZyroAi',
                prefixIcon: Icon(Icons.bolt_outlined),
              ),
              onSubmitted: (_) => _addTask(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _savingTask ? null : _addTask,
            icon: const Icon(Icons.add_task_outlined),
            label: Text(_savingTask ? 'Saving...' : ChiefL10nScope.of(context).t('create')),
          ),
        ],
      ),
    );
  }

  Widget _modeStrip(BuildContext context, String activeMode) {
    const modes = ['Executive', 'Deep Work', 'Available', 'Travel'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: modes.map((mode) {
          final active = activeMode == mode;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(
              onPressed: _updatingMode ? null : () => _setMode(mode),
              style: FilledButton.styleFrom(
                backgroundColor: active
                    ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.04),
                foregroundColor: active ? Theme.of(context).colorScheme.secondary : Colors.white,
              ),
              child: Text(mode),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required String label,
    required String value,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF121821), Color(0xFF0B1016)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _glanceTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(label),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
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

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'critical':
        return const Color(0xFFFF7A7A);
      case 'success':
        return const Color(0xFF63D6A6);
      case 'warning':
        return const Color(0xFFF3CC78);
      default:
        return const Color(0xFF8EB9FF);
    }
  }
}
