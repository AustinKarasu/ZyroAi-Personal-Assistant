import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';

class DecisionScreen extends StatefulWidget {
  const DecisionScreen({super.key, required this.api});

  final ApiService api;

  @override
  State<DecisionScreen> createState() => _DecisionScreenState();
}

class _DecisionScreenState extends State<DecisionScreen> {
  final _titleCtrl = TextEditingController();
  final List<_DecisionOptionForm> _forms = [
    _DecisionOptionForm(name: TextEditingController(text: 'Option A'), pros: TextEditingController(), cons: TextEditingController()),
    _DecisionOptionForm(name: TextEditingController(text: 'Option B'), pros: TextEditingController(), cons: TextEditingController()),
  ];

  Map<String, dynamic>? _result;
  bool _loading = false;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = 'What should I focus on this week?';
    _forms[0].pros.text = 'higher ROI,less context switch';
    _forms[0].cons.text = 'requires deep focus';
    _forms[1].pros.text = 'quick wins,easier to delegate';
    _forms[1].cons.text = 'lower strategic impact';
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await widget.api.fetchDecisionHistory();
      if (!mounted) return;
      setState(() => _history = rows);
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final form in _forms) {
      form.dispose();
    }
    super.dispose();
  }

  Future<void> _runDecision() async {
    if (_titleCtrl.text.trim().isEmpty || _forms.length < 2) return;
    setState(() => _loading = true);
    try {
      final options = _forms
          .where((form) => form.name.text.trim().isNotEmpty)
          .map(
            (form) => {
              'name': form.name.text.trim(),
              'pros': form.pros.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(),
              'cons': form.cons.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList(),
            },
          )
          .toList();

      if (options.length < 2) {
        throw Exception('Add at least two options');
      }

      final response = await widget.api.runDecision(title: _titleCtrl.text.trim(), options: options);
      if (!mounted) return;
      setState(() => _result = response);
      await _loadHistory();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Decision failed: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addOption() {
    setState(() {
      _forms.add(_DecisionOptionForm(name: TextEditingController(text: 'Option ${_forms.length + 1}'), pros: TextEditingController(), cons: TextEditingController()));
    });
  }

  void _removeOption(int index) {
    if (_forms.length <= 2) return;
    final removed = _forms.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = (_result?['breakdown'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final maxScore = breakdown.isEmpty ? 1.0 : breakdown.map((entry) => (entry['score'] as num).toDouble()).fold<double>(0, (a, b) => b > a ? b : a).abs().clamp(1, 1000);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Decision Cockpit', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Compare options with pros/cons and confidence scoring.'),
                const SizedBox(height: 14),
                TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Decision title')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_forms.length, (index) {
          final form = _forms[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Option ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        if (_forms.length > 2)
                          IconButton(onPressed: () => _removeOption(index), icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                    TextField(controller: form.name, decoration: const InputDecoration(labelText: 'Name')),
                    const SizedBox(height: 8),
                    TextField(controller: form.pros, decoration: const InputDecoration(labelText: 'Pros (comma separated)')),
                    const SizedBox(height: 8),
                    TextField(controller: form.cons, decoration: const InputDecoration(labelText: 'Cons (comma separated)')),
                  ],
                ),
              ),
            ),
          );
        }),
        Row(
          children: [
            OutlinedButton.icon(onPressed: _addOption, icon: const Icon(Icons.add), label: const Text('Add Option')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.api.clearDecisionHistory();
                await _loadHistory();
                if (!mounted) return;
                setState(() => _result = null);
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear History'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _loading ? null : _runDecision,
              icon: const Icon(Icons.auto_graph_outlined),
              label: Text(_loading ? 'Running...' : 'Run Decision'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_result != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recommended: ${_result?['recommendation']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('Confidence: ${_result?['confidence']}%'),
                  const SizedBox(height: 14),
                  ...breakdown.map((entry) {
                    final score = (entry['score'] as num).toDouble();
                    final normalized = (score.abs() / maxScore).clamp(0, 1).toDouble();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${entry['name']} • score ${score.toStringAsFixed(1)}'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: normalized, minHeight: 8, borderRadius: BorderRadius.circular(10)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recent Decisions', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._history.take(4).map(
                        (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('${row['title']} • ${row['recommendation']} (${row['confidence']}%)'),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DecisionOptionForm {
  _DecisionOptionForm({
    required this.name,
    required this.pros,
    required this.cons,
  });

  final TextEditingController name;
  final TextEditingController pros;
  final TextEditingController cons;

  void dispose() {
    name.dispose();
    pros.dispose();
    cons.dispose();
  }
}
