import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart';
import '../../core/config/app_theme.dart';


class RestaurantSettingsScreen extends StatefulWidget {
  const RestaurantSettingsScreen({super.key});
  @override
  State<RestaurantSettingsScreen> createState() =>
      _RestaurantSettingsScreenState();
}

class _RestaurantSettingsScreenState extends State<RestaurantSettingsScreen> {
  final _sb = Supabase.instance.client;
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _tax = TextEditingController();
  final _open = TextEditingController();
  final _close = TextEditingController();
  String _currency = 'USD';
  String _timezone = 'UTC';
  String? _restaurantId;
  bool _loading = true;
  bool _saving = false;

  static const _currencies = [
    'USD', 'EUR', 'GBP', 'INR', 'AED', 'SGD', 'AUD', 'CAD'
  ];
  static const _timezones = [
    'UTC', 'Asia/Kolkata', 'America/New_York', 'Europe/London',
    'Asia/Dubai', 'Asia/Singapore', 'Australia/Sydney', 'America/Los_Angeles'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _tax, _open, _close]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final row = await _sb
        .from('restaurants')
        .select()
        .eq('owner_id', user.id)
        .maybeSingle();
    if (row != null && mounted) {
      _restaurantId = row['id'] as String;
      _name.text = row['name'] ?? '';
      _address.text = row['address'] ?? '';
      _phone.text = row['phone'] ?? '';
      _email.text = row['email'] ?? '';
      _tax.text = row['tax_rate']?.toString() ?? '8.00';
      _open.text = row['opening_time'] ?? '09:00';
      _close.text = row['closing_time'] ?? '23:00';
      setState(() {
        _currency = row['currency'] ?? 'USD';
        _timezone = row['timezone'] ?? 'UTC';
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    final user = _sb.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'tax_rate': double.tryParse(_tax.text) ?? 8.0,
        'opening_time': _open.text.trim(),
        'closing_time': _close.text.trim(),
        'currency': _currency,
        'timezone': _timezone
      };
      if (_restaurantId != null) {
        await _sb.from('restaurants').update(payload).eq('id', _restaurantId!);
      } else {
        await _sb.from('restaurants').insert({...payload, 'owner_id': user.id});
      }
      await RestaurantService.instance.refresh(); // ✅ refresh cache after save
      _snack('Settings saved!');
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }
@override
Widget build(BuildContext context) {
  final isMobile = Responsive.isMobile(context);
  // ← No AdminLayout wrapper
  return _loading
      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
      : SingleChildScrollView(
          padding: Responsive.padding(context),
          child: Form(
            key: _key,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ... everything inside child: stays exactly the same
                      _pageHeader(),
                      const SizedBox(height: 24),
                      _sectionCard(
                          title: 'Basic Information',
                          icon: Icons.store_outlined,
                          children: [
                            _field(_name, 'Restaurant Name',
                                Icons.restaurant_outlined,
                                validator: (v) =>
                                    v!.isEmpty ? 'Required' : null),
                            const SizedBox(height: 14),
                            isMobile
                                ? Column(children: [
                                    _field(_email, 'Email Address',
                                        Icons.email_outlined,
                                        keyboardType:
                                            TextInputType.emailAddress),
                                    const SizedBox(height: 14),
                                    _field(_phone, 'Phone Number',
                                        Icons.phone_outlined,
                                        keyboardType: TextInputType.phone)
                                  ])
                                : Row(children: [
                                    Expanded(
                                        child: _field(_email, 'Email Address',
                                            Icons.email_outlined,
                                            keyboardType:
                                                TextInputType.emailAddress))
                                  ]),
                            const SizedBox(height: 14),
                            isMobile
                                ? _field(_address, 'Address',
                                    Icons.location_on_outlined)
                                : Row(children: [
                                    Expanded(
                                        child: _field(_phone, 'Phone Number',
                                            Icons.phone_outlined,
                                            keyboardType: TextInputType.phone)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _field(_address, 'Address',
                                            Icons.location_on_outlined))
                                  ]),
                          ]),
                      const SizedBox(height: 18),
                      _sectionCard(
                          title: 'Financial Settings',
                          icon: Icons.attach_money_outlined,
                          children: [
                            isMobile
                                ? Column(children: [
                                    _dropdownField(
                                        'Currency',
                                        _currency,
                                        _currencies,
                                        (v) => setState(() => _currency = v!)),
                                    const SizedBox(height: 14),
                                    _field(_tax, 'Tax Rate (%)',
                                        Icons.percent_outlined,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'[\d.]'))
                                        ])
                                  ])
                                : Row(children: [
                                    Expanded(
                                        child: _dropdownField(
                                            'Currency',
                                            _currency,
                                            _currencies,
                                            (v) => setState(
                                                () => _currency = v!))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _field(_tax, 'Tax Rate (%)',
                                            Icons.percent_outlined,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'[\d.]'))
                                        ]))
                                  ]),
                          ]),
                      const SizedBox(height: 18),
                      _sectionCard(
                          title: 'Operating Hours',
                          icon: Icons.access_time_outlined,
                          children: [
                            isMobile
                                ? Column(children: [
                                    _field(_open, 'Opening Time (HH:MM)',
                                        Icons.wb_sunny_outlined),
                                    const SizedBox(height: 14),
                                    _field(_close, 'Closing Time (HH:MM)',
                                        Icons.nightlight_outlined)
                                  ])
                                : Row(children: [
                                    Expanded(
                                        child: _field(
                                            _open,
                                            'Opening Time (HH:MM)',
                                            Icons.wb_sunny_outlined)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: _field(
                                            _close,
                                            'Closing Time (HH:MM)',
                                            Icons.nightlight_outlined))
                                  ]),
                            const SizedBox(height: 14),
                            _dropdownField('Timezone', _timezone, _timezones,
                                (v) => setState(() => _timezone = v!)),
                          ]),
                      const SizedBox(height: 24),
                      Align(
                        alignment:
                            isMobile ? Alignment.center : Alignment.centerRight,
                        child: SizedBox(
                          width: isMobile ? double.infinity : 180,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Text('Save Changes',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ]),
              ),
    );
  }

  Widget _pageHeader() =>
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Restaurant Settings', style: AppText.h1),
        SizedBox(height: 4),
        Text('Manage your restaurant profile and configuration',
            style: AppText.body)
      ]);

  Widget _sectionCard(
          {required String title,
          required IconData icon,
          required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 12,
                  offset: Offset(0, 3))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 18, color: AppColors.primary)),
            const SizedBox(width: 10),
            Text(title, style: AppText.h3)
          ]),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 16),
          ...children,
        ]),
      );

  Widget _field(TextEditingController ctrl, String label, IconData icon,
          {TextInputType? keyboardType,
          List<TextInputFormatter>? inputFormatters,
          String? Function(String?)? validator}) =>
      TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon, size: 18, color: AppColors.textLight)));

  Widget _dropdownField(String label, String value, List<String> items,
          ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: const Color(0xFFF7FBFA),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
          style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged);
}