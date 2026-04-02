import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _sb = Supabase.instance.client;

  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _rememberMe = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Email / Password ────────────────────────────────────────
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final response = await _sb.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );

      final user = response.user;
      if (user == null) {
        _snack('Sign-in failed. Please try again.', isError: true);
        return;
      }

      // ── Route based on whether this user has completed restaurant setup.
      //    If no restaurant row exists yet → send to setup.
      //    If it exists → send straight to dashboard.
      final restaurant = await _sb
          .from('restaurants')
          .select('id')
          .eq('owner_id', user.id)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          restaurant != null ? '/dashboard' : '/setuprestaurant',
          (route) => false, // remove ALL previous routes
        );
      }
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Error: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Google OAuth ────────────────────────────────────────────
  String _redirectUrl() {
    if (kIsWeb) {
      return 'https://takshraval21.github.io/restaurant-management-system';
    }
    return 'io.supabase.restoadmin://login-callback';
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo:
            kIsWeb ? _redirectUrl() : 'io.supabase.restoadmin://login-callback',
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } catch (e) {
      _snack('Google sign-in failed. Please try again.', isError: true);
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Password',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: Color(0xFF141F1D))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your email and we\'ll send you a reset link.',
              style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7B7A))),
          const SizedBox(height: 16),
          TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 14, color: Color(0xFF141F1D)),
            decoration: InputDecoration(
              hintText: 'manager@restaurant.com',
              hintStyle: const TextStyle(color: Color(0xFF9EAEAC)),
              prefixIcon: const Icon(Icons.email_outlined,
                  size: 18, color: Color(0xFF9EAEAC)),
              filled: true,
              fillColor: const Color(0xFFF4F7F6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD4E0DE))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFD4E0DE))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF2E8B80), width: 1.8)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF6B7B7A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E8B80),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final email = emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Please enter a valid email address.', isError: true);
      return;
    }

    try {
      await _sb.auth.resetPasswordForEmail(
        email,
        redirectTo:
            'http://localhost:54872/reset-password', // change for production
      );
      _snack('Reset link sent! Check your inbox.');
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Something went wrong. Try again.', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor:
          isError ? const Color(0xFFE53935) : const Color(0xFF2E8B80),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Do nothing — user cannot navigate back past login
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1917),
        body: LayoutBuilder(builder: (ctx, constraints) {
          final isWide = constraints.maxWidth >= 800;
          return Row(children: [
            if (isWide) Expanded(flex: 55, child: _LeftPanel()),
            Expanded(
              flex: isWide ? 45 : 100,
              child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                      position: _slideAnim, child: _buildForm())),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      color: const Color(0xFFF4F7F6),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    Row(children: [
                      Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                              color: const Color(0xFF2E8B80),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.restaurant,
                              color: Colors.white, size: 20)),
                      const SizedBox(width: 10),
                      const Text('RestoAdmin',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Color(0xFF141F1D))),
                    ]),
                    const SizedBox(height: 40),

                    const Text('Welcome back',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF141F1D),
                            letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text('Sign in to your restaurant dashboard',
                        style:
                            TextStyle(fontSize: 14, color: Color(0xFF6B7B7A))),
                    const SizedBox(height: 28),

                    // Email
                    _fieldLabel('Email Address'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF141F1D)),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Enter your email';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      },
                      decoration: _inputDeco(
                          'manager@restaurant.com', Icons.email_outlined),
                    ),
                    const SizedBox(height: 18),

                    // Password
                    _fieldLabel('Password'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF141F1D)),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'Enter your password';
                        if (v.length < 6) return 'Password too short';
                        return null;
                      },
                      decoration:
                          _inputDeco('••••••••', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: const Color(0xFF9EAEAC)),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Remember + Forgot
                    Row(children: [
                      SizedBox(
                          height: 22,
                          width: 22,
                          child: Checkbox(
                              value: _rememberMe,
                              activeColor: const Color(0xFF2E8B80),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5)),
                              side: const BorderSide(
                                  color: Color(0xFFD4E0DE), width: 1.5),
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v!))),
                      const SizedBox(width: 8),
                      const Text('Remember me',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6B7B7A))),
                      const Spacer(),
                      TextButton(
                          onPressed: _forgotPassword,
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF2E8B80)),
                          child: const Text('Forgot password?',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                    const SizedBox(height: 20),

                    // Sign In button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: (_loading || _googleLoading || _appleLoading)
                            ? null
                            : _signIn,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E8B80),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            disabledBackgroundColor:
                                const Color(0xFF2E8B80).withOpacity(0.6)),
                        child: _loading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: Lottie.asset(
                                  'assets/animations/loader.json',
                                  width: 200,
                                  height: 200,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : const Text('Sign in',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3)),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // OR divider
                    Row(children: [
                      const Expanded(child: Divider(color: Color(0xFFD4E0DE))),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR CONTINUE WITH',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5))),
                      const Expanded(child: Divider(color: Color(0xFFD4E0DE))),
                    ]),
                    const SizedBox(height: 16),

                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: (_loading || _googleLoading)
                            ? null
                            : _signInWithGoogle,
                        icon: _googleLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: Lottie.asset(
                                  'assets/animations/loader.json',
                                  width: 16,
                                  height: 16,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset('assets/images/google.png',
                                height: 18,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.g_mobiledata, size: 20)),
                        label: const Text('Google',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1C2B2A),
                            side: const BorderSide(color: Color(0xFFD4E0DE)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 13)),
                      )),
                    ]),
                    const SizedBox(height: 26),

                    // Sign up link
                    Center(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('New to RestoAdmin?',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6B7B7A))),
                      TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SignupScreen())),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2E8B80)),
                        child: const Text('Create account',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ])),
                    const SizedBox(height: 16),

                    Center(
                        child: Text(
                            '© 2024 RestoAdmin Solutions Inc.\nPrivacy Policy  ·  Terms of Service',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade400,
                                height: 1.8))),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) => Text(label,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C2B2A)));

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF9EAEAC)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9EAEAC)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4E0DE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4E0DE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2E8B80), width: 1.8)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE53935))),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.8)),
      );
}

// ─── Left panel ───────────────────────────────────────────────
class _LeftPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0D1917),
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/images/loginbg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF0D1917))),
          Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                const Color(0xFF0D1917).withOpacity(0.75),
                const Color(0xFF1E6B60).withOpacity(0.55)
              ]))),
          Padding(
              padding: const EdgeInsets.all(52),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(11)),
                          child: const Icon(Icons.restaurant,
                              color: Color(0xFF2E8B80), size: 22)),
                      const SizedBox(width: 12),
                      const Text('RestoAdmin',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ]),
                    const Spacer(),
                    AnimatedTextKit(
                      animatedTexts: [
                        TypewriterAnimatedText(
                            'Master your\nkitchen,\nmanage\nyour floor.',
                            textStyle: const TextStyle(
                                fontSize: 54,
                                height: 1.1,
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1),
                            speed: const Duration(milliseconds: 110))
                      ],
                      totalRepeatCount: 1,
                      displayFullTextOnTap: true,
                    ),
                    const SizedBox(height: 22),
                    const Text(
                        'Experience the future of restaurant management\nwith our premium administrative suite.',
                        style: TextStyle(
                            fontSize: 15, color: Colors.white70, height: 1.6)),
                    const SizedBox(height: 40),
                    const Wrap(spacing: 10, runSpacing: 10, children: [
                      _Pill(Icons.dashboard_outlined, 'Live Dashboard'),
                      _Pill(Icons.receipt_long_outlined, 'Order Tracking'),
                      _Pill(Icons.bar_chart_outlined, 'Analytics'),
                      _Pill(Icons.table_restaurant_outlined, 'Floor Manager'),
                    ]),
                    const SizedBox(height: 36),
                  ])),
        ]),
      );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}
