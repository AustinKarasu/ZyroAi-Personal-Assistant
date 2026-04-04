import 'package:flutter/widgets.dart';

class ChiefL10nScope extends InheritedWidget {
  const ChiefL10nScope({
    super.key,
    required this.languageCode,
    required super.child,
  });

  final String languageCode;

  static ChiefL10n of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChiefL10nScope>();
    return ChiefL10n(scope?.languageCode ?? 'en');
  }

  @override
  bool updateShouldNotify(ChiefL10nScope oldWidget) => oldWidget.languageCode != languageCode;
}

class ChiefL10n {
  ChiefL10n(this.languageCode);

  final String languageCode;

  static const Map<String, Map<String, String>> _values = {
    'appName': {
      'en': 'ZyroAi',
      'hi': 'ZyroAi',
      'es': 'ZyroAi',
      'ar': 'ZyroAi',
    },
    'dashboard': {
      'en': 'Dashboard',
      'hi': 'Dashboard',
      'es': 'Panel',
      'ar': 'Dashboard',
    },
    'comms': {
      'en': 'Comms',
      'hi': 'Sanchar',
      'es': 'Comms',
      'ar': 'Comms',
    },
    'decision': {
      'en': 'Decision',
      'hi': 'Nirnay',
      'es': 'Decision',
      'ar': 'Decision',
    },
    'assistant': {
      'en': 'Assistant',
      'hi': 'Sahayak',
      'es': 'Asistente',
      'ar': 'Assistant',
    },
    'intel': {
      'en': 'Intel',
      'hi': 'Intel',
      'es': 'Intel',
      'ar': 'Intel',
    },
    'memory': {
      'en': 'Memory',
      'hi': 'Yaad',
      'es': 'Memoria',
      'ar': 'Memory',
    },
    'quests': {
      'en': 'Quests',
      'hi': 'Quests',
      'es': 'Misiones',
      'ar': 'Quests',
    },
    'settings': {
      'en': 'Settings',
      'hi': 'Settings',
      'es': 'Ajustes',
      'ar': 'Settings',
    },
    'premiumUi': {
      'en': 'Premium UI',
      'hi': 'Premium UI',
      'es': 'UI Premium',
      'ar': 'Premium UI',
    },
    'aiTools': {
      'en': 'AI Tools',
      'hi': 'AI Tools',
      'es': 'Herramientas AI',
      'ar': 'AI Tools',
    },
    'executiveDashboard': {
      'en': 'Executive Dashboard',
      'hi': 'Executive Dashboard',
      'es': 'Panel Ejecutivo',
      'ar': 'Executive Dashboard',
    },
    'communicationsCommand': {
      'en': 'Communications Command',
      'hi': 'Communications Command',
      'es': 'Centro de Comunicaciones',
      'ar': 'Communications Command',
    },
    'decisionCockpit': {
      'en': 'Decision Cockpit',
      'hi': 'Decision Cockpit',
      'es': 'Cabina de Decisiones',
      'ar': 'Decision Cockpit',
    },
    'aiChief': {
      'en': 'AI Chief',
      'hi': 'AI Chief',
      'es': 'AI Chief',
      'ar': 'AI Chief',
    },
    'intelligenceCenter': {
      'en': 'Intelligence Center',
      'hi': 'Intelligence Center',
      'es': 'Centro de Inteligencia',
      'ar': 'Intelligence Center',
    },
    'memoryVault': {
      'en': 'Memory Vault',
      'hi': 'Memory Vault',
      'es': 'Boveda de Memoria',
      'ar': 'Memory Vault',
    },
    'zyroSettings': {
      'en': 'ZyroAi Settings',
      'hi': 'ZyroAi Settings',
      'es': 'Ajustes de ZyroAi',
      'ar': 'ZyroAi Settings',
    },
    'create': {
      'en': 'Create',
      'hi': 'Banayein',
      'es': 'Crear',
      'ar': 'Create',
    },
    'refresh': {
      'en': 'Refresh',
      'hi': 'Refresh',
      'es': 'Actualizar',
      'ar': 'Refresh',
    },
    'clear': {
      'en': 'Clear',
      'hi': 'Clear',
      'es': 'Limpiar',
      'ar': 'Clear',
    },
    'saveNow': {
      'en': 'Save Now',
      'hi': 'Save Now',
      'es': 'Guardar Ahora',
      'ar': 'Save Now',
    },
    'send': {
      'en': 'Send',
      'hi': 'Send',
      'es': 'Enviar',
      'ar': 'Send',
    },
    'updateNow': {
      'en': 'Update Now',
      'hi': 'Update Now',
      'es': 'Actualizar Ahora',
      'ar': 'Update Now',
    },
    'later': {
      'en': 'Later',
      'hi': 'Later',
      'es': 'Luego',
      'ar': 'Later',
    },
    'topPriorities': {
      'en': 'Top Priorities',
      'hi': 'Top Priorities',
      'es': 'Prioridades',
      'ar': 'Top Priorities',
    },
    'recentCalls': {
      'en': 'Recent Calls',
      'hi': 'Recent Calls',
      'es': 'Llamadas Recientes',
      'ar': 'Recent Calls',
    },
    'conversationFeed': {
      'en': 'Conversation Feed',
      'hi': 'Conversation Feed',
      'es': 'Feed de Conversacion',
      'ar': 'Conversation Feed',
    },
    'assistantReady': {
      'en': 'Assistant responded from your live workspace.',
      'hi': 'Assistant ne aapke live workspace se jawab diya.',
      'es': 'El asistente respondio desde tu espacio de trabajo en vivo.',
      'ar': 'Assistant responded from your live workspace.',
    },
    'assistantThinking': {
      'en': 'ZyroAi is thinking...',
      'hi': 'ZyroAi soch raha hai...',
      'es': 'ZyroAi esta pensando...',
      'ar': 'ZyroAi is thinking...',
    },
    'assistantFailed': {
      'en': 'Assistant request failed',
      'hi': 'Assistant request fail ho gaya',
      'es': 'La solicitud del asistente fallo',
      'ar': 'Assistant request failed',
    },
    'speechTranslator': {
      'en': 'Speech Translator',
      'hi': 'Speech Translator',
      'es': 'Traductor de Voz',
      'ar': 'Speech Translator',
    },
    'weatherMovement': {
      'en': 'Weather and Movement',
      'hi': 'Weather and Movement',
      'es': 'Clima y Movimiento',
      'ar': 'Weather and Movement',
    },
    'aiReports': {
      'en': 'AI Reports',
      'hi': 'AI Reports',
      'es': 'Reportes AI',
      'ar': 'AI Reports',
    },
    'useCurrentLocation': {
      'en': 'Use Current Location',
      'hi': 'Use Current Location',
      'es': 'Usar Ubicacion Actual',
      'ar': 'Use Current Location',
    },
    'clearHistory': {
      'en': 'Clear History',
      'hi': 'Clear History',
      'es': 'Borrar Historial',
      'ar': 'Clear History',
    },
    'support': {
      'en': 'Support',
      'hi': 'Support',
      'es': 'Soporte',
      'ar': 'Support',
    },
    'emailSupport': {
      'en': 'Email Support',
      'hi': 'Email Support',
      'es': 'Enviar Correo',
      'ar': 'Email Support',
    },
    'profile': {
      'en': 'Profile',
      'hi': 'Profile',
      'es': 'Perfil',
      'ar': 'Profile',
    },
    'appearance': {
      'en': 'Appearance',
      'hi': 'Appearance',
      'es': 'Apariencia',
      'ar': 'Appearance',
    },
    'automation': {
      'en': 'Automation',
      'hi': 'Automation',
      'es': 'Automatizacion',
      'ar': 'Automation',
    },
    'theme': {
      'en': 'Theme',
      'hi': 'Theme',
      'es': 'Tema',
      'ar': 'Theme',
    },
    'language': {
      'en': 'Language',
      'hi': 'Bhasha',
      'es': 'Idioma',
      'ar': 'Language',
    },
    'working': {
      'en': 'Working...',
      'hi': 'Working...',
      'es': 'Trabajando...',
      'ar': 'Working...',
    },
    'running': {
      'en': 'Running...',
      'hi': 'Running...',
      'es': 'Ejecutando...',
      'ar': 'Running...',
    },
  };

  String t(String key) {
    final item = _values[key];
    if (item == null) return key;
    return item[languageCode] ?? item['en'] ?? key;
  }
}
