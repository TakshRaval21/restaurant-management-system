import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: "https://sikcimlkhkzhkopujhhl.supabase.co",
      anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNpa2NpbWxraGt6aGtvcHVqaGhsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2MzYyMjEsImV4cCI6MjA4OTIxMjIyMX0.FA7g_P8lksrQ32Ye34R7A_Fx2410d9eRJ_ff_aTE2lw",
    );
  }
}