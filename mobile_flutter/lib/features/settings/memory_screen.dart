import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _hint = TextEditingController();
  final _note = TextEditingController();
  late Future<List<Map<String, dynamic>>> _memory;

  @override
  void initState() {
    super.initState();
    _memory = widget.api.fetchMemory();
  }

  @override
  void dispose() {
    _hint.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_hint.text.trim().isEmpty || _note.text.trim().isEmpty) return;
    await widget.api.addMemory(_hint.text.trim(), _note.text.trim());
    _hint.clear();
    _note.clear();
    setState(() => _memory = widget.api.fetchMemory());
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF15171D), Color(0xFF111A29), Color(0xFF0A1017)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Memory Vault', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Store personal context that ZyroAi can use for proactive reminders and better decision support.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(controller: _hint, decoration: const InputDecoration(labelText: 'Hint or title')),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Memory note'),
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Save Memory'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await widget.api.clearMemory();
                        setState(() => _memory = widget.api.fetchMemory());
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
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _memory,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Memory failed: ${snapshot.error}'));
            }
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No memories saved yet. Add anniversaries, preferences, or critical personal notes here.'),
                ),
              );
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stored Memories', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 10),
                    ...list.map(
                      (entry) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.memory_outlined, size: 18)),
                          title: Text(entry['hint'].toString()),
                          subtitle: Text(entry['created_at'].toString()),
                          trailing: IconButton(
                            onPressed: () async {
                              await widget.api.deleteMemory(entry['id'].toString());
                              setState(() => _memory = widget.api.fetchMemory());
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
