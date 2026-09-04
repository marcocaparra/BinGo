class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  factory SupabaseConfig.fromEnvironment() {
    return const SupabaseConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  final String url;
  final String publishableKey;

  bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  List<String> get missingVariables {
    return [
      if (url.trim().isEmpty) 'SUPABASE_URL',
      if (publishableKey.trim().isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    ];
  }
}

class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException(this.missingVariables);

  final List<String> missingVariables;

  String get userMessage =>
      'Configuração do Supabase ausente: ${missingVariables.join(', ')}.';

  @override
  String toString() => userMessage;
}
