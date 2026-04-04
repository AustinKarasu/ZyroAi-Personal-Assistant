import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/services/api_service.dart';

class IntelligenceScreen extends StatefulWidget {
  const IntelligenceScreen({super.key, required this.api});
  final ApiService api;

  @override
  State<IntelligenceScreen> createState() => _IntelligenceScreenState();
}

class _IntelligenceScreenState extends State<IntelligenceScreen> {
  late Future<Map<String, dynamic>> _future;
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _period = 'weekly';
  final _stepCtrl = TextEditingController(text: '500');
  final _latCtrl = TextEditingController(text: '28.6139');
  final _lonCtrl = TextEditingController(text: '77.2090');
  String _sourceLang = 'en';
  String _targetLang = 'hi';
  String _sourceLocale = 'en_US';
  String _transcript = '';
  String _translation = '';
  bool _listening = false;
  bool _busy = false;
  String _translatorStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _stepCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final workspace = await widget.api.fetchWorkspace();
    final report = await widget.api.fetchReport(_period);
    return {
      'workspace': workspace,
      'report': report['report'],
    };
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  Future<void> _addSteps() async {
    setState(() => _busy = true);
    try {
      await widget.api.logSteps(int.tryParse(_stepCtrl.text) ?? 500);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshWeather() async {
    setState(() => _busy = true);
    try {
      await widget.api.fetchWeather(
        lat: double.tryParse(_latCtrl.text),
        lon: double.tryParse(_lonCtrl.text),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePeriod(String value) async {
    setState(() => _period = value);
    await _refresh();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
        _translatorStatus = 'Stopped';
      });
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')),
      );
      return;
    }

    setState(() {
      _listening = true;
      _translatorStatus = 'Listening...';
    });
    await _speech.listen(
      localeId: _sourceLocale,
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      onResult: (result) async {
        setState(() => _transcript = result.recognizedWords);
        if (_transcript.trim().isEmpty) return;
        try {
          final response = await widget.api.translateText(
            text: _transcript,
            sourceLang: _sourceLang,
            targetLang: _targetLang,
          );
          if (!mounted) return;
          setState(() {
            _translation = response['translatedText']?.toString() ?? '';
            _translatorStatus = 'Translated';
          });
        } catch (_) {}
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Intelligence failed: ${snapshot.error}'));
          }
          if (!snapshot.hasData) return const SizedBox.shrink();

          final data = snapshot.data!;
          final workspace = (data['workspace'] as Map).cast<String, dynamic>();
          final report = (data['report'] as Map).cast<String, dynamic>();
          final overview = (workspace['overview'] as Map?)?.cast<String, dynamic>() ?? {};
          final weather = (workspace['weather'] as Map?)?.cast<String, dynamic>();
          final steps = (workspace['steps'] as Map?)?.cast<String, dynamic>() ?? {};
          final settings = (workspace['settings'] as Map?)?.cast<String, dynamic>() ?? {};
          final automation = (settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
          final highlights = (report['highlights'] as List<dynamic>? ?? const []).cast<String>();
          final metrics = (report['metrics'] as Map?)?.cast<String, dynamic>() ?? {};

          return ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF12171E), Color(0xFF111C2C), Color(0xFF090F16)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Intelligence Center', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('Reports, weather, movement analytics, and live speech translation in one intelligence layer.'),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(context, 'Score ${overview['executiveScore'] ?? '--'}'),
                        _chip(context, 'Steps ${steps['count'] ?? 0}'),
                        _chip(context, 'Tracking ${automation['autoStepTracking'] == true ? 'On' : 'Off'}'),
                        _chip(context, 'Period ${_period.toUpperCase()}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Speech Translator', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _sourceLang,
                              decoration: const InputDecoration(labelText: 'Source'),
                              items: const [
                                DropdownMenuItem(value: 'en', child: Text('English')),
                                DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                                DropdownMenuItem(value: 'es', child: Text('Spanish')),
                                DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                              ],
                              onChanged: (value) => setState(() {
                                _sourceLang = value ?? 'en';
                                _sourceLocale = switch (_sourceLang) {
                                  'hi' => 'hi_IN',
                                  'es' => 'es_ES',
                                  'ar' => 'ar_SA',
                                  _ => 'en_US',
                                };
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _targetLang,
                              decoration: const InputDecoration(labelText: 'Target'),
                              items: const [
                                DropdownMenuItem(value: 'en', child: Text('English')),
                                DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                                DropdownMenuItem(value: 'es', child: Text('Spanish')),
                                DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                              ],
                              onChanged: (value) => setState(() => _targetLang = value ?? 'hi'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: _toggleListening,
                            child: Text(_listening ? 'Stop' : 'Start Listening'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(onPressed: _refresh, child: const Text('Refresh Data')),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _transcript = '';
                              _translation = '';
                              _translatorStatus = 'Cleared';
                            }),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Status: $_translatorStatus'),
                      const SizedBox(height: 8),
                      _panelText(_transcript.isEmpty ? 'Detected speech will appear here' : _transcript),
                      const SizedBox(height: 8),
                      _panelText(_translation.isEmpty ? 'Translated text will appear here' : _translation),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Weather and Movement', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _infoTile(
                              context,
                              title: 'Weather',
                              detail: weather == null
                                  ? 'No live weather cached yet'
                                  : '${weather['summary']} at ${weather['temperatureC']} C',
                              footer: 'Use location to refresh weather',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _infoTile(
                              context,
                              title: 'Footsteps',
                              detail: '${steps['count'] ?? 0} / ${steps['goal'] ?? 8000} today',
                              footer: automation['autoStepTracking'] == true
                                  ? 'Smart tracking is active'
                                  : 'Enable smart tracking in Settings',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        minHeight: 10,
                        value: (((steps['progress'] ?? 0) as num).toDouble() / 100).clamp(0, 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _latCtrl, decoration: const InputDecoration(labelText: 'Latitude'))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _lonCtrl, decoration: const InputDecoration(labelText: 'Longitude'))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : _refreshWeather,
                              child: const Text('Refresh Weather'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _stepCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Manual steps'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonal(
                            onPressed: _busy ? null : _addSteps,
                            child: const Text('Log'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI Reports', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _period,
                        decoration: const InputDecoration(labelText: 'Period'),
                        items: const [
                          DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                          DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                        ],
                        onChanged: (value) {
                          if (value != null) _changePeriod(value);
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _metricTile(
                              title: 'Focus score',
                              value: '${metrics['focusScore'] ?? '--'}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricTile(
                              title: 'Task completion',
                              value: '${metrics['completionRate'] ?? '--'}%',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _metricTile(
                              title: 'Urgent calls',
                              value: '${metrics['urgentCalls'] ?? '--'}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _metricTile(
                              title: 'Average steps',
                              value: '${metrics['averageSteps'] ?? '--'}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...highlights.map((item) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.insights_outlined, size: 18, color: Theme.of(context).colorScheme.secondary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(item)),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text),
    );
  }

  Widget _panelText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required String title,
    required String detail,
    required String footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(detail),
          const SizedBox(height: 8),
          Text(footer, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _metricTile({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
