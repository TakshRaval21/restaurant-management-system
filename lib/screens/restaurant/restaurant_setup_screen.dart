import 'dart:typed_data';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart'; 
import '../../core/config/app_theme.dart';
import '../../core/config/routes.dart';


class SetupRestaurantScreen extends StatefulWidget {
  const SetupRestaurantScreen({super.key});
  @override
  State<SetupRestaurantScreen> createState() => _SetupRestaurantScreenState();
}

class _SetupRestaurantScreenState extends State<SetupRestaurantScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _specialityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '8.00');
  final _openCtrl = TextEditingController(text: '09:00');
  final _closeCtrl = TextEditingController(text: '23:00');
  String _currency = 'USD';
  String _timezone = 'UTC';
  bool _isLive = true;
  bool _saving = false;
  bool _uploading = false;

  final List<Uint8List> _images = [];
  final List<String> _imgNames = [];

  LatLng _location = const LatLng(21.1702, 72.8311);
  final _mapCtrl = MapController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _currencies = [
    'USD',
    'EUR',
    'GBP',
    'INR',
    'AED',
    'SGD',
    'AUD',
    'CAD'
  ];
  static const _timezones = [
    'UTC',
    'Asia/Kolkata',
    'America/New_York',
    'Europe/London',
    'Asia/Dubai',
    'Asia/Singapore',
    'Australia/Sydney',
    'America/Los_Angeles'
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _emailCtrl,
      _specialityCtrl,
      _addressCtrl,
      _taxCtrl,
      _openCtrl,
      _closeCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      for (final img in picked) {
        final bytes = await img.readAsBytes();
        if (bytes.isEmpty) continue;
        setState(() {
          _images.add(bytes);
          _imgNames.add(img.name);
        });
      }
    } catch (e) {
      _snack('Failed to pick images: $e', isError: true);
    }
  }

  Future<List<String>> _uploadImages() async {
    final urls = <String>[];
    for (int i = 0; i < _images.length; i++) {
      final path =
          'restaurants/${DateTime.now().millisecondsSinceEpoch}_$i.png';
      try {
        await _sb.storage.from('Restaurant-images').uploadBinary(
            path, _images[i],
            fileOptions: const FileOptions(contentType: 'image/png'));
        urls.add(_sb.storage.from('Restaurant-images').getPublicUrl(path));
      } catch (e) {
        _snack('Image ${i + 1} upload failed: $e', isError: true);
      }
    }
    return urls;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      _snack('Please add at least one restaurant image.', isError: true);
      return;
    }
    final user = _sb.auth.currentUser;
    if (user == null) {
      _snack('Session expired. Please log in again.', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      setState(() => _uploading = true);
      final imageUrls = await _uploadImages();
      setState(() => _uploading = false);
      final restaurantRow = await _sb
          .from('restaurants')
          .insert({
            'owner_id': user.id,
            'name': _nameCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'email': _emailCtrl.text.trim(),
            'address': _addressCtrl.text.trim(),
            'speciality': _specialityCtrl.text.trim(),
            'currency': _currency,
            'tax_rate': double.tryParse(_taxCtrl.text) ?? 8.0,
            'opening_time': _openCtrl.text.trim(),
            'closing_time': _closeCtrl.text.trim(),
            'timezone': _timezone,
            'logo_url': imageUrls.isNotEmpty ? imageUrls.first : null,
            'image_urls': imageUrls,
            'latitude': _location.latitude,
            'longitude': _location.longitude,
            'is_live': _isLive,
          })
          .select('id')
          .single();
      final restaurantId = restaurantRow['id'] as String;
    await _sb.from('employees').insert({
        'restaurant_id': restaurantId,
        'user_id': user.id,
        'full_name': _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : user.email?.split('@').first ?? 'Owner',
        'email': user.email ?? '',
        'role': 'owner',
        'status': 'active'
      });
      await RestaurantService.instance.init(); 
      _snack('Restaurant set up successfully! Welcome aboard 🎉');
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    } catch (e) {
      _snack('Failed to save: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _discard() async {
    final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Discard Setup?',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark)),
                  content: const Text(
                      'All information entered will be lost and you will be signed out.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Continue Setup',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        child: const Text('Discard')),
                  ],
                )) ??
        false;
    if (confirm && mounted) {
      await _sb.auth.signOut();
      if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? AppColors.red : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    final isTablet = screenW >= 600 && screenW < 1100;
    final twoCol = screenW >= 1000;
    final hPad = isMobile
        ? 16.0
        : isTablet
            ? 24.0
            : 40.0;

    return Scaffold(
      backgroundColor: AppColors.contentBg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildTopBar(isMobile),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 40),
              child: Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPageHeader(),
                      const SizedBox(height: 24),
                      twoCol
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Expanded(flex: 58, child: _leftColumn()),
                                  const SizedBox(width: 22),
                                  Expanded(flex: 42, child: _rightColumn()),
                                ])
                          : Column(children: [
                              _leftColumn(),
                              const SizedBox(height: 18),
                              _rightColumn(),
                            ]),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _leftColumn() => Column(children: [
        _buildGeneralInfoCard(),
        const SizedBox(height: 18),
        _buildBusinessSettingsCard(),
        const SizedBox(height: 18),
        _buildLocationCard(),
      ]);

  Widget _rightColumn() => Column(children: [
        _buildImagesCard(),
        const SizedBox(height: 18),
        _buildPublishCard(),
      ]);

  Widget _buildTopBar(bool isMobile) => Container(
        height: 60,
        color: AppColors.sidebarBg,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28),
        child: Row(children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(9)),
              child:
                  const Icon(Icons.restaurant, color: Colors.white, size: 17)),
          const SizedBox(width: 9),
          const Text('RestoAdmin',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          if (!isMobile) ...[
            const SizedBox(width: 22),
            ...[1, 2, 3]
                .map((n) => Row(mainAxisSize: MainAxisSize.min, children: [
                      if (n > 1)
                        Container(
                            width: 20,
                            height: 1.5,
                            color: Colors.white.withOpacity(0.25)),
                      Row(children: [
                        Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle),
                            child: Center(
                                child: Text('$n',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700)))),
                        const SizedBox(width: 5),
                        Text(['Basic Info', 'Settings', 'Publish'][n - 1],
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11)),
                      ]),
                    ]))
                ,
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.15))),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 13, color: Colors.white60),
              const SizedBox(width: 5),
              Text(isMobile ? '2 min setup' : 'First-time setup · ~2 minutes',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 11)),
            ]),
          ),
        ]),
      );

  Widget _buildPageHeader() => Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.store_outlined,
                color: AppColors.primary, size: 19)),
        const SizedBox(width: 12),
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Restaurant Setup', style: AppText.h1),
          Text(
              "Let's configure your restaurant — everything can be updated later.",
              style: AppText.body),
        ])),
      ]);

  Widget _buildGeneralInfoCard() => _SetupCard(
      title: 'General Information',
      icon: Icons.business_outlined,
      child: Column(children: [
        _SetupField(_nameCtrl, 'Restaurant Name', 'e.g. The Golden Grill',
            Icons.restaurant_outlined,
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
        const SizedBox(height: 12),
        LayoutBuilder(
            builder: (ctx, c) => c.maxWidth > 400
                ? Row(children: [
                    Expanded(
                        child: _SetupField(_phoneCtrl, 'Phone', '+1 555 0000',
                            Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) =>
                                v!.trim().isEmpty ? 'Required' : null)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _SetupField(_emailCtrl, 'Email',
                            'info@resto.com', Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress))
                  ])
                : Column(children: [
                    _SetupField(_phoneCtrl, 'Phone', '+1 555 0000',
                        Icons.phone_outlined,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),
                    _SetupField(_emailCtrl, 'Email', 'info@resto.com',
                        Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress)
                  ])),
        const SizedBox(height: 12),
        _SetupField(_specialityCtrl, 'Specialities',
            'Italian, Seafood, Steaks...', Icons.local_dining_outlined),
        const SizedBox(height: 12),
        _SetupField(_addressCtrl, 'Full Address', '123 Culinary Ave, Food City',
            Icons.location_on_outlined,
            maxLines: 3,
            validator: (v) => v!.trim().isEmpty ? 'Required' : null),
      ]));

  Widget _buildBusinessSettingsCard() => _SetupCard(
      title: 'Business Settings',
      icon: Icons.settings_outlined,
      child: Column(children: [
        LayoutBuilder(
            builder: (ctx, c) => c.maxWidth > 400
                ? Row(children: [
                    Expanded(
                        child: _SetupDropdown(
                            'Currency',
                            _currency,
                            _currencies,
                            (v) => setState(() => _currency = v!),
                            Icons.payments_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _SetupField(_taxCtrl, 'Tax Rate (%)', '8.00',
                            Icons.percent_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                        ]))
                  ])
                : Column(children: [
                    _SetupDropdown(
                        'Currency',
                        _currency,
                        _currencies,
                        (v) => setState(() => _currency = v!),
                        Icons.payments_outlined),
                    const SizedBox(height: 12),
                    _SetupField(_taxCtrl, 'Tax Rate (%)', '8.00',
                        Icons.percent_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true))
                  ])),
        const SizedBox(height: 12),
        LayoutBuilder(
            builder: (ctx, c) => c.maxWidth > 400
                ? Row(children: [
                    Expanded(
                        child: _SetupField(_openCtrl, 'Opening Time', '09:00',
                            Icons.wb_sunny_outlined)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _SetupField(_closeCtrl, 'Closing Time', '23:00',
                            Icons.nightlight_outlined))
                  ])
                : Column(children: [
                    _SetupField(_openCtrl, 'Opening Time', '09:00',
                        Icons.wb_sunny_outlined),
                    const SizedBox(height: 12),
                    _SetupField(_closeCtrl, 'Closing Time', '23:00',
                        Icons.nightlight_outlined)
                  ])),
        const SizedBox(height: 12),
        _SetupDropdown('Timezone', _timezone, _timezones,
            (v) => setState(() => _timezone = v!), Icons.access_time_outlined),
      ]));

  Widget _buildLocationCard() => _SetupCard(
        title: 'Location Pin',
        icon: Icons.map_outlined,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: AppColors.statusAvailBg,
              borderRadius: BorderRadius.circular(20)),
          child: Text(
              '${_location.latitude.toStringAsFixed(3)}, ${_location.longitude.toStringAsFixed(3)}',
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.statusAvailable,
                  fontWeight: FontWeight.w600)),
        ),
        child: Column(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                  height: 260,
                  child: FlutterMap(
                    mapController: _mapCtrl,
                    options: MapOptions(
                        initialCenter: _location,
                        initialZoom: 13,
                        onTap: (_, point) => setState(() => _location = point)),
                    children: [
                      TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      MarkerLayer(markers: [
                        Marker(
                            point: _location,
                            width: 40,
                            height: 40,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: AppColors.primary
                                                    .withOpacity(0.4),
                                                blurRadius: 8)
                                          ]),
                                      child: const Icon(Icons.store,
                                          size: 13, color: Colors.white)),
                                  Container(
                                      width: 2,
                                      height: 7,
                                      color: AppColors.primary.withOpacity(0.8))
                                ]))
                      ]),
                    ],
                  ))),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.statusAvailable.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.touch_app_outlined,
                  size: 14, color: AppColors.statusAvailable),
              SizedBox(width: 8),
              Flexible(
                  child: Text('Tap the map to move your restaurant pin',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.statusAvailable,
                          fontWeight: FontWeight.w500)))
            ]),
          ),
        ]),
      );

  Widget _buildImagesCard() => _SetupCard(
      title: 'Restaurant Images',
      icon: Icons.photo_library_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
            onTap: _pickImages,
            child: _uploading
                ? Container(
                    height: 130,
                    decoration: BoxDecoration(
                        color: AppColors.contentBg,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                          SizedBox(height: 10),
                          Text('Uploading...',
                              style: TextStyle(
                                  color: AppColors.textMid, fontSize: 13))
                        ])))
                : DottedBorder(
                    borderType: BorderType.RRect,
                    radius: const Radius.circular(12),
                    dashPattern: const [6, 5],
                    color: AppColors.primary.withOpacity(0.4),
                    strokeWidth: 1.5,
                    child: Container(
                      height: 130,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12)),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(11)),
                                child: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: AppColors.primary,
                                    size: 22)),
                            const SizedBox(height: 9),
                            const Text('Tap to upload photos',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                            const SizedBox(height: 3),
                            const Text('PNG, JPG · Max 5MB each',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textLight)),
                          ]),
                    ))),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Selected',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMid)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (int i = 0; i < _images.length; i++)
              Stack(children: [
                Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: i == 0
                            ? Border.all(color: AppColors.primary, width: 2)
                            : Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(color: AppColors.shadow, blurRadius: 6)
                        ]),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.memory(_images[i], fit: BoxFit.cover))),
                if (i == 0)
                  Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(9))),
                          child: const Text('Cover',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700)))),
                Positioned(
                    right: -2,
                    top: -2,
                    child: GestureDetector(
                        onTap: () => setState(() {
                              _images.removeAt(i);
                              _imgNames.removeAt(i);
                            }),
                        child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                                color: AppColors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 11)))),
              ]),
            GestureDetector(
                onTap: _pickImages,
                child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                        color: AppColors.contentBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border)),
                    child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 18, color: AppColors.textLight),
                          Text('Add',
                              style: TextStyle(
                                  fontSize: 9, color: AppColors.textLight))
                        ]))),
          ]),
          const SizedBox(height: 6),
          Text(
              '${_images.length} image${_images.length != 1 ? 's' : ''} · First is cover photo',
              style: AppText.bodySmall),
        ],
      ]));

  Widget _buildPublishCard() => _SetupCard(
      title: 'Publish Settings',
      icon: Icons.publish_outlined,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _isLive ? AppColors.statusAvailBg : AppColors.contentBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _isLive
                      ? AppColors.statusAvailable.withOpacity(0.3)
                      : AppColors.border)),
          child: Row(children: [
            AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: _isLive
                        ? AppColors.statusAvailable.withOpacity(0.15)
                        : AppColors.contentBg,
                    shape: BoxShape.circle),
                child: Icon(
                    _isLive
                        ? Icons.wifi_tethering
                        : Icons.wifi_tethering_off_outlined,
                    color: _isLive
                        ? AppColors.statusAvailable
                        : AppColors.textLight,
                    size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Live Status',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.textDark)),
                  const SizedBox(height: 2),
                  Text(
                      _isLive
                          ? 'Visible to customers'
                          : 'Hidden from customers',
                      style: TextStyle(
                          fontSize: 12,
                          color: _isLive
                              ? AppColors.statusAvailable
                              : AppColors.textLight))
                ])),
            Switch(
                value: _isLive,
                activeThumbColor: AppColors.statusAvailable,
                onChanged: (v) => setState(() => _isLive = v)),
          ]),
        ),
        const SizedBox(height: 14),
        const Wrap(spacing: 8, runSpacing: 8, children: [
          _InfoChip(Icons.edit_outlined, 'Editable anytime'),
          _InfoChip(Icons.lock_outline, 'Secure & private')
        ]),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: _saving
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(_uploading ? 'Uploading images...' : 'Saving...',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))
                  ])
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(Icons.check_circle_outline, size: 17),
                        SizedBox(width: 8),
                        Text('Save & Launch Dashboard',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700))
                      ]),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: TextButton(
              onPressed: _saving ? null : _discard,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMid,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Discard & Sign Out',
                  style: TextStyle(fontSize: 13))),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFE082))),
          child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: Color(0xFFBF7900)),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Name, phone, address and at least one image are required.',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFBF7900),
                            height: 1.5))),
              ]),
        ),
      ]));
}

class _SetupField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final String? Function(String?)? validator;
  const _SetupField(this.ctrl, this.label, this.hint, this.icon,
      {this.keyboardType,
      this.inputFormatters,
      this.maxLines = 1,
      this.validator});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        const SizedBox(height: 5),
        TextFormField(
            controller: ctrl,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLines: maxLines,
            validator: validator,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(fontSize: 13, color: AppColors.textLight),
              prefixIcon: maxLines == 1
                  ? Icon(icon, size: 17, color: AppColors.textLight)
                  : null,
              filled: true,
              fillColor: const Color(0xFFF7FBFA),
              contentPadding: EdgeInsets.symmetric(
                  horizontal: maxLines > 1 ? 14 : 0,
                  vertical: maxLines > 1 ? 14 : 0),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.8)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: AppColors.red)),
            )),
      ]);
}

class _SetupDropdown extends StatelessWidget {
  final String label, value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final IconData icon;
  const _SetupDropdown(
      this.label, this.value, this.items, this.onChanged, this.icon);
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          initialValue: value,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 17, color: AppColors.textLight),
            filled: true,
            fillColor: const Color(0xFFF7FBFA),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.8)),
            contentPadding: EdgeInsets.zero,
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ]);
}

class _SetupCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _SetupCard(
      {required this.title,
      required this.icon,
      required this.child,
      this.trailing});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 3))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 16, color: AppColors.primary)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),
          child,
        ]),
      );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: AppColors.contentBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: AppColors.textMid),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMid,
                  fontWeight: FontWeight.w500))
        ]),
      );
}
