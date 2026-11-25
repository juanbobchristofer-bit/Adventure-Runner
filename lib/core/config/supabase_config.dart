/// Konfigurasi koneksi Supabase (mendukung override lewat --dart-define untuk CI/CD).
/// Hanya menggunakan Publishable / Anon Key sisi client yang aman dengan Row Level Security (RLS).
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zeapegimpvrtkezzdrdc.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_6bAjS6rsDbzwWhRsYbWKtg_rqb2WJHf',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
