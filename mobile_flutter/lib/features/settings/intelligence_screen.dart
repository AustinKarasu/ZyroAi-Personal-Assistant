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
  String _translatorStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _future = _load();
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
    await widget.api.logSteps(int.tryParse(_stepCtrl.text) ?? 500);
    await _refresh();
  }

  Future<void> _refreshWeather() async {
    await widget.api.fetchWeather(lat: double.tryParse(_latCtrl.text), lon: double.tryParse(_lonCtrl.text));
    await _refresh();
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speech recognition is not available on this device.')));
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
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Intelligence failed: ${snapshot.error}'));
          if (!snapshot.hasData) return const SizedBox.shrink();
          final data = snapshot.data!;
          final workspace = (data['workspace'] as Map).cast<String, dynamic>();
          final report = (data['report'] as Map).cast<String, dynamic>();
          final weather = workspace['weather'] as Map<String, dynamic>?;
          final steps = (workspace['steps'] as Map).cast<String, dynamic>();
          final highlights = (report['highlights'] as List<dynamic>).cast<String>();

          return ListView(
            children: [
              Text('Intelligence', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip('Score ${workspace['overview']['executiveScore']}'),
                _chip('Steps ${steps['count']}'),
                _chip('DND ${workspace['settings']['automation']['dndMode'] ? 'On' : 'Off'}'),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Real-time Speech Translator', style: TextStyle(fontWeight: FontWeight.w700)),
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
                          FilledButton(onPressed: _toggleListening, child: Text(_listening ? 'Stop' : 'Start Listening')),
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_transcript.isEmpty ? 'Detected speech will appear here' : _transcript),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_translation.isEmpty ? 'Translated text will appear here' : _translation),
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
                      const Text('Weather', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(weather == null ? 'No weather cached yet' : '${weather['summary']} at ${weather['temperatureC']} C'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _latCtrl, decoration: const InputDecoration(labelText: 'Latitude'))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _lonCtrl, decoration: const InputDecoration(labelText: 'Longitude'))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _refreshWeather, child: const Text('Refresh Weather')),
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
                      const Text('Footstep Tracker', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('${steps['count']} / ${steps['goal']} today (${steps['progress']}%)'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        minHeight: 8,
                        value: ((steps['progress'] ?? 0) as num).toDouble() / 100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _stepCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Add steps'))),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: _addSteps, child: const Text('Log')),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              await widget.api.clearStepHistory();
                              await _refresh();
                            },
                            child: const Text('Clear'),
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
                      const Text('AI Reports', style: TextStyle(fontWeight: FontWeight.w700)),
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
                      const SizedBox(height: 8),
                      Text('Focus score ${report['metrics']['focusScore']}'),
                      const SizedBox(height: 6),
                      Text('Task completion ${report['metrics']['taskCompletionRate']}%'),
                      const SizedBox(height: 6),
                      Text('Urgent communication ${report['metrics']['urgentCommunicationRate']}%'),
                      const SizedBox(height: 8),
                      ...highlights.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('- $item'),
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

  Widget _chip(String text) => Chip(label: Text(text));
}
