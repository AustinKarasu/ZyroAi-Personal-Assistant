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

  Future<void> _save() async {
    if (_hint.text.trim().isEmpty || _note.text.trim().isEmpty) return;
    await widget.api.addMemory(_hint.text.trim(), _note.text.trim());
    _hint.clear();
    _note.clear();
    setState(() => _memory = widget.api.fetchMemory());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(controller: _hint, decoration: const InputDecoration(labelText: 'Hint')),
          const SizedBox(height: 8),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Memory note'), maxLines: 2),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () async {
                  await widget.api.clearMemory();
                  setState(() => _memory = widget.api.fetchMemory());
                },
                child: const Text('Clear History'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _memory,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final list = snapshot.data!;
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(list[i]['hint'].toString()),
                      subtitle: Text(list[i]['created_at'].toString()),
                      trailing: IconButton(
                        onPressed: () async {
                          await widget.api.deleteMemory(list[i]['id'].toString());
                          setState(() => _memory = widget.api.fetchMemory());
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
