import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/chief_l10n.dart';
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
  final _stepCtrl = TextEditingController(text: '500');
  final _latCtrl = TextEditingController(text: '28.6139');
  final _lonCtrl = TextEditingController(text: '77.2090');
  String _period = 'weekly';
  String _sourceLang = 'en';
  String _targetLang = 'hi';
  String _sourceLocale = 'en_US';
  String _transcript = '';
  String _translation = '';
  String _translatorStatus = 'Idle';
  String _lastTranslatedTranscript = '';
  bool _listening = false;
  bool _busy = false;

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
    final workspaceFuture = widget.api.fetchWorkspace();
    final reportFuture = widget.api.fetchReport(_period);
    final workspace = await workspaceFuture;
    Map<String, dynamic> report = {};

    try {
      final reportResponse = await reportFuture;
      report = (reportResponse['report'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {
      final reports = ((workspace['reports'] as Map?)?['latest'] as Map?)?.cast<String, dynamic>() ?? {};
      report = (reports[_period] as Map?)?.cast<String, dynamic>() ??
          {
            'period': _period,
            'metrics': <String, dynamic>{},
            'highlights': <dynamic>[],
            'coaching': <dynamic>[],
          };
    }

    return {
      'workspace': workspace,
      'report': report,
    };
  }

  void _showStatus(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  Future<void> _addSteps() async {
    setState(() => _busy = true);
    try {
      final amount = int.tryParse(_stepCtrl.text.trim()) ?? 500;
      await widget.api.logSteps(amount);
      await _refresh();
      _showStatus('$amount steps added to today.');
    } catch (error) {
      _showStatus('Step logging failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearSteps() async {
    setState(() => _busy = true);
    try {
      await widget.api.clearStepHistory();
      await _refresh();
      _showStatus('Step history cleared.');
    } catch (error) {
      _showStatus('Unable to clear step history: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshWeather() async {
    setState(() => _busy = true);
    try {
      await widget.api.fetchWeather(
        lat: double.tryParse(_latCtrl.text.trim()),
        lon: double.tryParse(_lonCtrl.text.trim()),
      );
      await _refresh();
      _showStatus('Weather refreshed.');
    } catch (error) {
      _showStatus('Weather refresh failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _busy = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        _showStatus('Location permission is required for live weather.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      _latCtrl.text = position.latitude.toStringAsFixed(6);
      _lonCtrl.text = position.longitude.toStringAsFixed(6);
      await _refreshWeather();
    } catch (error) {
      _showStatus('Unable to read current location: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePeriod(String value) async {
    setState(() => _period = value);
    await _refresh();
    _showStatus('${value[0].toUpperCase()}${value.substring(1)} report loaded.');
  }

  Future<void> _translateTranscript(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || clean == _lastTranslatedTranscript) return;

    try {
      final response = await widget.api.translateText(
        text: clean,
        sourceLang: _sourceLang,
        targetLang: _targetLang,
      );
      if (!mounted) return;
      setState(() {
        _translation = response['translatedText']?.toString() ?? '';
        _translatorStatus = 'Translated';
        _lastTranslatedTranscript = clean;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _translatorStatus = 'Translation unavailable');
      _showStatus('Translation failed: $error');
    }
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() {
        _listening = false;
        _translatorStatus = 'Stopped';
      });
      _showStatus('Speech capture stopped.');
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      _showStatus('Speech recognition is not available on this device.');
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
        if (!mounted) return;
        final recognized = result.recognizedWords.trim();
        setState(() => _transcript = recognized);
        if (recognized.isEmpty) return;
        if (!result.finalResult && recognized.length < 12) return;
        await _translateTranscript(recognized);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ChiefL10nScope.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<Map<String, dynamic>>(
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
                    Text('Intelligence failed: ${snapshot.error}', textAlign: TextAlign.center),
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
          if (!snapshot.hasData) return const SizedBox.shrink();

          final data = snapshot.data!;
          final workspace = (data['workspace'] as Map).cast<String, dynamic>();
          final report = (data['report'] as Map?)?.cast<String, dynamic>() ?? {};
          final overview = (workspace['overview'] as Map?)?.cast<String, dynamic>() ?? {};
          final weather = (workspace['weather'] as Map?)?.cast<String, dynamic>();
          final steps = (workspace['steps'] as Map?)?.cast<String, dynamic>() ?? {};
          final settings = (workspace['settings'] as Map?)?.cast<String, dynamic>() ?? {};
          final automation = (settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
          final highlights = (report['highlights'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
          final coaching = (report['coaching'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
          final metrics = (report['metrics'] as Map?)?.cast<String, dynamic>() ?? {};
          final focusScore = (metrics['focusScore'] as num?)?.toDouble() ?? 0;
          final completionRate = (metrics['completionRate'] as num?)?.toDouble() ?? 0;
          final urgentCalls = (metrics['urgentCalls'] as num?)?.toDouble() ?? 0;
          final averageSteps = (metrics['averageSteps'] as num?)?.toDouble() ?? 0;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
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
                      Text(l10n.t('intelligenceCenter'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('Reports, weather, movement analytics, and live speech translation in one executive layer.'),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip('Score ${overview['executiveScore'] ?? '--'}'),
                          _chip('Steps ${steps['count'] ?? 0}'),
                          _chip('Tracking ${automation['autoStepTracking'] == true ? 'On' : 'Off'}'),
                          _chip('Period ${_period.toUpperCase()}'),
                          _chip(weather == null ? 'Weather Cache' : weather['summary']?.toString() ?? 'Weather'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.t('refresh')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _useCurrentLocation,
                      icon: const Icon(Icons.my_location_outlined),
                      label: Text(l10n.t('useCurrentLocation')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _clearSteps,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(l10n.t('clearHistory')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.t('speechTranslator'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
                                onChanged: (value) {
                                  final next = value ?? 'en';
                                  setState(() {
                                    _sourceLang = next;
                                    _sourceLocale = switch (next) {
                                      'hi' => 'hi_IN',
                                      'es' => 'es_ES',
                                      'ar' => 'ar_SA',
                                      _ => 'en_US',
                                    };
                                  });
                                },
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
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _toggleListening,
                              child: Text(_listening ? 'Stop Listening' : 'Start Listening'),
                            ),
                            OutlinedButton(
                              onPressed: _transcript.trim().isEmpty ? null : () => _translateTranscript(_transcript),
                              child: const Text('Translate Now'),
                            ),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                _transcript = '';
                                _translation = '';
                                _lastTranslatedTranscript = '';
                                _translatorStatus = 'Cleared';
                              }),
                              child: Text(l10n.t('clear')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Status: $_translatorStatus'),
                        const SizedBox(height: 8),
                        _panelText(_transcript.isEmpty ? 'Detected speech will appear here.' : _transcript),
                        const SizedBox(height: 8),
                        _panelText(_translation.isEmpty ? 'Translated text will appear here.' : _translation),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 680;
                    final infoChildren = [
                      Expanded(
                        child: _infoTile(
                          context,
                          title: 'Weather',
                          detail: weather == null
                              ? 'No live weather cached yet.'
                              : '${weather['summary']} at ${weather['temperatureC']} C',
                          footer: 'Lat ${_latCtrl.text} | Lon ${_lonCtrl.text}',
                        ),
                      ),
                      const SizedBox(width: 10, height: 10),
                      Expanded(
                        child: _infoTile(
                          context,
                          title: 'Footsteps',
                          detail: '${steps['count'] ?? 0} / ${steps['goal'] ?? 8000} today',
                          footer: automation['autoStepTracking'] == true
                              ? 'Smart tracking is active.'
                              : 'Enable smart tracking in Settings.',
                        ),
                      ),
                    ];

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.t('weatherMovement'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            const SizedBox(height: 10),
                            if (isCompact)
                              Column(
                                children: [
                                  _infoTile(
                                    context,
                                    title: 'Weather',
                                    detail: weather == null
                                        ? 'No live weather cached yet.'
                                        : '${weather['summary']} at ${weather['temperatureC']} C',
                                    footer: 'Lat ${_latCtrl.text} | Lon ${_lonCtrl.text}',
                                  ),
                                  const SizedBox(height: 10),
                                  _infoTile(
                                    context,
                                    title: 'Footsteps',
                                    detail: '${steps['count'] ?? 0} / ${steps['goal'] ?? 8000} today',
                                    footer: automation['autoStepTracking'] == true
                                        ? 'Smart tracking is active.'
                                        : 'Enable smart tracking in Settings.',
                                  ),
                                ],
                              )
                            else
                              Row(children: infoChildren),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              minHeight: 10,
                              value: (((steps['progress'] ?? 0) as num).toDouble() / 100).clamp(0, 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            const SizedBox(height: 12),
                            if (isCompact) ...[
                              TextField(controller: _latCtrl, decoration: const InputDecoration(labelText: 'Latitude')),
                              const SizedBox(height: 8),
                              TextField(controller: _lonCtrl, decoration: const InputDecoration(labelText: 'Longitude')),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: _busy ? null : _refreshWeather,
                                child: const Text('Refresh Weather'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _stepCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Manual steps'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.tonal(
                                onPressed: _busy ? null : _addSteps,
                                child: const Text('Log Steps'),
                              ),
                            ] else ...[
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.t('aiReports'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
                            if (value != null) {
                              _changePeriod(value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _metricBar(context, title: 'Focus score', value: focusScore, suffix: ''),
                        const SizedBox(height: 10),
                        _metricBar(context, title: 'Task completion', value: completionRate, suffix: '%'),
                        const SizedBox(height: 10),
                        _metricBar(context, title: 'Urgent calls', value: urgentCalls * 10, suffix: ''),
                        const SizedBox(height: 10),
                        _metricBar(context, title: 'Average steps', value: (averageSteps / 100).clamp(0, 100), suffix: ''),
                        const SizedBox(height: 14),
                        const Text('Highlights', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (highlights.isEmpty)
                          _panelText('No report highlights yet. Refresh to generate the latest report.')
                        else
                          ...highlights.map((item) => _bulletCard(context, item, Icons.insights_outlined)),
                        const SizedBox(height: 10),
                        const Text('Coaching', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        if (coaching.isEmpty)
                          _panelText('Coaching suggestions will appear as more live data is collected.')
                        else
                          ...coaching.map((item) => _bulletCard(context, item, Icons.psychology_alt_outlined)),
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

  Widget _chip(String text) {
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

  Widget _metricBar(
    BuildContext context, {
    required String title,
    required double value,
    required String suffix,
  }) {
    final normalized = (value / 100).clamp(0, 1).toDouble();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title)),
              Text('${value.round()}$suffix', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            minHeight: 8,
            value: normalized,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
    );
  }

  Widget _bulletCard(BuildContext context, String text, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
