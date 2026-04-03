import 'package:flutter/material.dart';

import '../../core/models/task_item.dart';
import '../../core/services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<TaskItem>> _tasksFuture;
  final _titleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tasksFuture = widget.api.fetchDashboardTasks();
  }

  Future<void> _addTask() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    await widget.api.createTask(title: _titleCtrl.text.trim(), urgency: 4, importance: 4, energyCost: 3);
    _titleCtrl.clear();
    setState(() => _tasksFuture = widget.api.fetchDashboardTasks());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0C1424), Color(0xFF121F38)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Executive Dashboard', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Add priority task'))),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addTask, child: const Text('Create')),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<TaskItem>>(
                future: _tasksFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  final tasks = snapshot.data ?? [];
                  if (tasks.isEmpty) return const Center(child: Text('No tasks yet.'));
                  return ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => Card(
                      child: ListTile(
                        title: Text(tasks[i].title),
                        subtitle: Text('Priority score: ${tasks[i].priorityScore}'),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
