import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_theme.dart';
import 'core/config/routes.dart';
import 'core/config/supabase_config.dart';
import 'core/services/restaurant_service.dart';
import 'screens/auth/login_screen.dart';
import 'layouts/admin_layout.dart';
import 'screens/restaurant/restaurant_setup_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      title: 'RestoAdmin',
      theme: AppTheme.theme,
      routes: AppRoutes.routes,

      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }

          final session = snapshot.data?.session;

          if (session != null) {
            return const _RestaurantGate();
          }

          // Not signed in
          return const LoginScreen();
        },
      ),
    );
  }
}


class _RestaurantGate extends StatefulWidget {
  const _RestaurantGate();
  @override
  State<_RestaurantGate> createState() => _RestaurantGateState();
}

class _RestaurantGateState extends State<_RestaurantGate> {
  bool _loading = true;
  bool _hasRestaurant = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final user = supabase.auth.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final r = await supabase
          .from('restaurants')
          .select('id')
          .eq('owner_id', user.id)
          .limit(1)
          .maybeSingle();

            if (r != null) {
      await RestaurantService.instance.init(); // ✅ ADD THIS LINE
    }

      if (mounted) setState(() { _hasRestaurant = r != null; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _SplashScreen();
    return _hasRestaurant
        ? const AdminLayout() 
        : const SetupRestaurantScreen();
  }
}


class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D1917),
    body: Center(
      child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),
    ),
  );
}