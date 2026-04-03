import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';

class DecisionScreen extends StatefulWidget {
  const DecisionScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<DecisionScreen> createState() => _DecisionScreenState();
}

class _DecisionScreenState extends State<DecisionScreen> {
  final _titleCtrl = TextEditingController(text: 'Choose Q3 product direction');
  String _result = 'No decision run yet.';
  bool _loading = false;

  Future<void> _runDecision() async {
    setState(() => _loading = true);
    try {
      final response = await widget.api.runDecision(
        title: _titleCtrl.text.trim(),
        options: [
          {
            'name': 'Launch Mobile First',
            'pros': ['fast feedback', 'lower build scope'],
            'cons': ['web clients wait']
          },
          {
            'name': 'Launch Web and Mobile Together',
            'pros': ['single marketing push'],
            'cons': ['higher delivery risk', 'longer QA']
          }
        ],
      );

      setState(() {
        _result = 'Recommend: ${response['recommendation']} (${response['confidence']}% confidence)';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Help Me Decide', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Decision title')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _loading ? null : _runDecision, child: Text(_loading ? 'Running...' : 'Run Decision')),
          const SizedBox(height: 18),
          Text(_result, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
