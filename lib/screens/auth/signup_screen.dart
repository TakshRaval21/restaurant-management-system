// lib/screens/auth/signup_screen.dart
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _fullNameCtrl    = TextEditingController();
  final _restaurantCtrl  = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _passwordCtrl    = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _formKey         = GlobalKey<FormState>();
  final _sb              = Supabase.instance.client;

  bool _obscurePass    = true;
  bool _obscureConfirm = true;
  bool _loading        = false;
  bool _googleLoading  = false;
  bool _appleLoading   = false;
  bool _agreedToTerms  = false;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    for (final c in [_fullNameCtrl, _restaurantCtrl, _emailCtrl, _passwordCtrl, _confirmPassCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  String _redirectUrl() => 'http://localhost:54872';

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) { _snack('Please agree to the Terms of Service.', isError: true); return; }
    setState(() => _loading = true);
    try {
      final response = await _sb.auth.signUp(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text.trim(),
      );
      final user = response.user;
      if (user != null) {
        await _sb.from('profiles').upsert({
          'id':       user.id,
          'email':    _emailCtrl.text.trim(),
          'username': _fullNameCtrl.text.trim(),
        });
        _snack('Account created! Welcome aboard 🎉');

        if (!mounted) return; 
        Navigator.pushReplacementNamed(context, '/setuprestaurant');
      } else {
        _snack('Check your email to confirm your account.');
      }
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await _sb.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? _redirectUrl() : 'io.supabase.restoadmin://login-callback',
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
      _snack('Google sign-in failed. Please try again.', isError: true);
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _appleLoading = true);
    try {
      await _sb.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? _redirectUrl() : 'io.supabase.restoadmin://login-callback',
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    } catch (e) {
      _snack('Apple sign-in failed. Please try again.', isError: true);
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  void _showTerms() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("Terms of Service", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF141F1D))),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: controller,
                children: const [
                  _PolicySection(
                    title: "1. Account Terms",
                    content: "You are responsible for maintaining the security of your account and password. RestoAdmin cannot and will not be liable for any loss or damage from your failure to comply with this security obligation.",
                  ),
                  _PolicySection(
                    title: "2. Proper Use",
                    content: "This software is for restaurant management purposes only. You may not use the service for any illegal or unauthorized purpose, including data scraping or interfering with the system's performance.",
                  ),
                  _PolicySection(
                    title: "3. Accuracy of Data",
                    content: "The restaurant owner is solely responsible for the accuracy of menu prices, tax calculations (GST/VAT), and billing information generated through the app.",
                  ),
                  _PolicySection(
                    title: "4. Modifications",
                    content: "RestoAdmin reserves the right to modify or discontinue the service with or without notice at any time.",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E8B80), foregroundColor: Colors.white),
                child: const Text("I Understand"),
              ),
            )
          ],
        ),
      ),
    ),
  );
}




void _showPrivacy() {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("Privacy Policy", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF141F1D))),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: controller,
                children: const [
                  _PolicySection(
                    title: "1. Information We Collect",
                    content: "We collect your email address, full name, and restaurant details (name, location, currency) to provide the management service.",
                  ),
                  _PolicySection(
                    title: "2. How We Use Data",
                    content: "Your data is used to manage orders, generate bills, and synchronize the kitchen display. We do not sell your personal or business data to third parties.",
                  ),
                  _PolicySection(
                    title: "3. Data Storage",
                    content: "We use Supabase for secure cloud storage. While we take every precaution, no method of electronic storage is 100% secure.",
                  ),
                  _PolicySection(
                    title: "4. Your Rights",
                    content: "You can request to delete your account and all associated restaurant data at any time by contacting support or using the delete option in settings.",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E8B80), foregroundColor: Colors.white),
                child: const Text("Close"),
              ),
            )
          ],
        ),
      ),
    ),
  );
}


  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? const Color(0xFFE53935) : const Color(0xFF2E8B80),
      behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1917),
      body: LayoutBuilder(builder: (ctx, constraints) {
        final isWide = constraints.maxWidth >= 900;
        return Row(children: [
          if (isWide) Expanded(flex: 50, child: _LeftPanel()),
          Expanded(flex: isWide ? 50 : 100,
              child: FadeTransition(opacity: _fadeAnim,
                  child: SlideTransition(position: _slideAnim, child: _buildForm()))),
        ]);
      }),
    );
  }

  Widget _buildForm() {
    return Container(
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFF2E8B80), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.restaurant, color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                const Text('RestoAdmin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF141F1D))),
              ]),
              const SizedBox(height: 36),
              const Text('Create your account', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF141F1D), letterSpacing: -0.5)),
              const SizedBox(height: 6),
              const Text('Start managing your restaurant today.', style: TextStyle(fontSize: 14, color: Color(0xFF6B7B7A))),
              const SizedBox(height: 30),

              _Row2([
                _Field(_fullNameCtrl, 'Full Name', 'John Doe', Icons.person_outline, validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                _Field(_restaurantCtrl, 'Restaurant Name', 'The Golden Bistro', Icons.store_outlined, validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              ]),
              const SizedBox(height: 16),
              _Field(_emailCtrl, 'Email Address', 'you@restaurant.com', Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) { if (v == null || v.trim().isEmpty) return 'Required'; if (!v.contains('@')) return 'Enter a valid email'; return null; }),
              const SizedBox(height: 16),
              _Row2([
                _Field(_passwordCtrl, 'Password', '••••••••', Icons.lock_outline,
                    obscure: _obscurePass, onToggleObscure: () => setState(() => _obscurePass = !_obscurePass),
                    validator: (v) { if (v == null || v.trim().isEmpty) return 'Required'; if (v.length < 6) return 'Min 6 chars'; return null; }),
                _Field(_confirmPassCtrl, 'Confirm Password', '••••••••', Icons.lock_outline,
                    obscure: _obscureConfirm, onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) { if (v != _passwordCtrl.text) return 'Passwords do not match'; return null; }),
              ]),
              const SizedBox(height: 18),

              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, height: 22, child: Checkbox(value: _agreedToTerms, activeColor: const Color(0xFF2E8B80), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)), side: const BorderSide(color: Color(0xFFD4E0DE), width: 1.5), onChanged: (v) => setState(() => _agreedToTerms = v!))),
                const SizedBox(width: 8),
                Expanded(child: RichText(text:TextSpan(style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7B7A), height: 1.5), children: [
                  TextSpan(text: "I agree to RestoAdmin's "),
                  TextSpan(
              text: "Terms of Service",
              style:  TextStyle(color: Color(0xFF2E8B80), fontWeight: FontWeight.bold),
              recognizer: TapGestureRecognizer()..onTap = _showTerms,
            ),
                  const TextSpan(text: " and "),
            TextSpan(
              text: "Privacy Policy",
              style: const TextStyle(color: Color(0xFF2E8B80), fontWeight: FontWeight.bold),
              recognizer: TapGestureRecognizer()..onTap = _showPrivacy, 
            ),
                ]))),
              ]),
              const SizedBox(height: 22),

              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: (_loading || _googleLoading || _appleLoading) ? null : _signUp,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E8B80), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), disabledBackgroundColor: const Color(0xFF2E8B80).withOpacity(0.6)),
                  child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Get Started →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                ),
              ),
              const SizedBox(height: 20),

              Row(children: [
                const Expanded(child: Divider(color: Color(0xFFD4E0DE))),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('OR CONTINUE WITH', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
                const Expanded(child: Divider(color: Color(0xFFD4E0DE))),
              ]),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: (_loading || _googleLoading || _appleLoading) ? null : _signInWithGoogle,
                  icon: _googleLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF2E8B80), strokeWidth: 2)) : Image.asset('assets/images/google.png', height: 18, errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 20)),
                  label: const Text('Google', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1C2B2A), side: const BorderSide(color: Color(0xFFD4E0DE)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 13)),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: (_loading || _googleLoading || _appleLoading) ? null : _signInWithApple,
                  icon: _appleLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.apple, size: 18),
                  label: const Text('Apple', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF141F1D), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 13)),
                )),
              ]),
              const SizedBox(height: 24),

              Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Already have an account?', style: TextStyle(fontSize: 13, color: Color(0xFF6B7B7A))),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF2E8B80)),
                  child: const Text('Sign in', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ])),
            ])),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl; final String label, hint; final IconData icon;
  final TextInputType? keyboardType; final bool obscure; final VoidCallback? onToggleObscure; final String? Function(String?)? validator;
  const _Field(this.ctrl, this.label, this.hint, this.icon, {this.keyboardType, this.obscure = false, this.onToggleObscure, this.validator});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1C2B2A))),
    const SizedBox(height: 6),
    TextFormField(controller: ctrl, keyboardType: keyboardType, obscureText: obscure, validator: validator,
      style: const TextStyle(fontSize: 13.5, color: Color(0xFF141F1D)),
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF9EAEAC)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9EAEAC)),
        suffixIcon: onToggleObscure != null ? IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: const Color(0xFF9EAEAC)), onPressed: onToggleObscure) : null,
        filled: true, fillColor: const Color(0xFFF7FBFA), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border:             OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFD4E0DE))),
        enabledBorder:      OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFD4E0DE))),
        focusedBorder:      OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFF2E8B80), width: 1.8)),
        errorBorder:        OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE53935))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.8)),
      )),
  ]);
}

class _Row2 extends StatelessWidget {
  final List<Widget> children; const _Row2(this.children);
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start,
      children: children.expand((w) => [Expanded(child: w), const SizedBox(width: 14)]).toList()..removeLast());
}

class _LeftPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFF0D1917),
    child: Stack(fit: StackFit.expand, children: [
      Image.asset('assets/images/signupbg.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0D1917))),
      Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF0D1917).withOpacity(0.80), const Color(0xFF1E6B60).withOpacity(0.60)]))),
      Padding(padding: const EdgeInsets.all(52), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.restaurant, color: Color(0xFF2E8B80), size: 22)),
          const SizedBox(width: 12),
          const Text('RestoAdmin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const Spacer(),
        AnimatedTextKit(animatedTexts: [TypewriterAnimatedText('Launch your\nrestaurant,\nlead the\nexperience.', textStyle: const TextStyle(fontSize: 54, height: 1.1, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -1), speed: const Duration(milliseconds: 110))], totalRepeatCount: 1, displayFullTextOnTap: true),
        const SizedBox(height: 22),
        const Text('Build your restaurant empire with\nour intelligent management suite.', style: TextStyle(fontSize: 15.5, color: Colors.white70, height: 1.6)),
        const SizedBox(height: 40),
        const Row(children: [_Bubble('500+', 'Restaurants'), SizedBox(width: 16), _Bubble('99.9%', 'Uptime'), SizedBox(width: 16), _Bubble('24/7', 'Support')]),
        const SizedBox(height: 36),
      ])),
    ]),
  );
}

class _Bubble extends StatelessWidget {
  final String value, label; const _Bubble(this.value, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.15))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
    ]),
  );
}


class _PolicySection extends StatelessWidget {
  final String title, content;
  const _PolicySection({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF141F1D))),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(fontSize: 14, color: Color(0xFF6B7B7A), height: 1.5)),
        ],
      ),
    );
  }
}