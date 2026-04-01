import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_theme.dart';


class QrCodesScreen extends StatefulWidget {
  const QrCodesScreen({super.key});
  @override
  State<QrCodesScreen> createState() => _QrCodesScreenState();
}

class _QrCodesScreenState extends State<QrCodesScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _qrCodes = [];
  String? _restaurantId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final r = await _sb
        .from('restaurants')
        .select('id')
        .eq('owner_id', user.id)
        .maybeSingle();
    if (r == null) {
      setState(() => _loading = false);
      return;
    }
    _restaurantId = r['id'] as String;
    await _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _sb
          .from('tables')
          .select()
          .eq('restaurant_id', _restaurantId!)
          .order('table_number'),
      _sb.from('qr_codes').select().eq('restaurant_id', _restaurantId!),
    ]);
    if (!mounted) return;
    setState(() {
      _tables = List<Map<String, dynamic>>.from(results[0]);
      _qrCodes = List<Map<String, dynamic>>.from(results[1]);
      _loading = false;
    });
  }

  String? _qrForTable(String tableId) {
    final qr = _qrCodes.where((q) => q['table_id'] == tableId).toList();
    return qr.isNotEmpty ? qr.first['id'] as String : null;
  }

  Future<void> _generateQr(Map<String, dynamic> table) async {
    final qrData =
        'https://yourdomain.com/menu?restaurant=$_restaurantId&table=${table['id']}';
    final existing =
        _qrCodes.where((q) => q['table_id'] == table['id']).toList();
    if (existing.isNotEmpty) {
      _showQrDialog(table, existing.first['id'] as String, qrData);
      return;
    }
    final row = await _sb
        .from('qr_codes')
        .insert({
          'restaurant_id': _restaurantId,
          'table_id': table['id'],
          'qr_data': qrData,
          'label': 'Table ${table['table_number']}',
          'is_active': true
        })
        .select()
        .single();
    setState(() => _qrCodes.add(row));
    _showQrDialog(table, row['id'] as String, qrData);
  }

  void _showQrDialog(Map<String, dynamic> table, String qrId, String qrData) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('QR Code — Table ${table['table_number']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.textDark)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 3),
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white),
                    child: const Center(
                        child: Icon(Icons.qr_code_2,
                            size: 130, color: AppColors.textDark))),
                const SizedBox(height: 12),
                Text(
                    'Table ${table['table_number']} — ${table['section'] ?? 'Main Hall'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textDark)),
                const SizedBox(height: 6),
                Text(qrData,
                    style: AppText.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('💡 Add qr_flutter package for real QR codes',
                    style: TextStyle(fontSize: 10, color: AppColors.textLight),
                    textAlign: TextAlign.center),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close',
                        style: TextStyle(color: AppColors.textMid))),
                ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _snack('QR Downloaded!');
                    },
                    icon: const Icon(Icons.download_outlined, size: 15),
                    label: const Text('Download')),
              ],
            ));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
Widget build(BuildContext context) {
  final cols = Responsive.gridCount(context, mobile: 2, tablet: 3, desktop: 4);
  // ← No AdminLayout wrapper
  return _loading
      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
      : Padding(
          padding: Responsive.padding(context),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ... everything inside child: stays exactly the same
                    Responsive.isMobile(context)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('QR Codes',
                                                style: AppText.h1),
                                            Text('${_tables.length} tables',
                                                style: AppText.body)
                                          ]),
                                      ElevatedButton.icon(
                                          onPressed: () async {
                                            for (final t in _tables) {
                                              await _generateQr(t);
                                            }
                                            _snack('All QR Codes generated!');
                                          },
                                          icon: const Icon(
                                              Icons.qr_code_outlined,
                                              size: 14),
                                          label: const Text('All')),
                                    ]),
                              ])
                        : Row(children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('QR Codes', style: AppText.h1),
                                  Text(
                                      'Generate and manage QR codes for ${_tables.length} tables',
                                      style: AppText.body)
                                ]),
                            const Spacer(),
                            ElevatedButton.icon(
                                onPressed: () async {
                                  for (final t in _tables) {
                                    await _generateQr(t);
                                  }
                                  _snack('All QR Codes generated!');
                                },
                                icon: const Icon(Icons.qr_code_outlined,
                                    size: 15),
                                label: const Text('Generate All')),
                          ]),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _tables.isEmpty
                          ? const Center(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                  Icon(Icons.qr_code_2,
                                      size: 56, color: AppColors.textLight),
                                  SizedBox(height: 12),
                                  Text('No tables found', style: AppText.h3),
                                  SizedBox(height: 6),
                                  Text('Add tables first in Tables Management',
                                      style: AppText.body)
                                ]))
                          : GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: cols,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio:
                                          Responsive.isMobile(context)
                                              ? 0.75
                                              : 0.88),
                              itemCount: _tables.length,
                              itemBuilder: (_, i) {
                                final table = _tables[i];
                                final hasQr =
                                    _qrForTable(table['id'] as String) != null;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: hasQr
                                              ? AppColors.primary
                                                  .withOpacity(0.3)
                                              : AppColors.border),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: AppColors.shadow,
                                            blurRadius: 8,
                                            offset: Offset(0, 2))
                                      ]),
                                  child: Column(children: [
                                    Text(
                                        (table['section'] ?? 'MAIN')
                                            .toString()
                                            .toUpperCase(),
                                        style: AppText.label),
                                    const SizedBox(height: 4),
                                    Text('Table ${table['table_number']}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: AppColors.textDark)),
                                    Text('${table['seats']} Seats',
                                        style: AppText.bodySmall),
                                    const SizedBox(height: 8),
                                    Container(
                                        width: 70,
                                        height: 70,
                                        decoration: BoxDecoration(
                                            color: hasQr
                                                ? AppColors.primary
                                                    .withOpacity(0.07)
                                                : AppColors.contentBg,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: hasQr
                                                    ? AppColors.primary
                                                        .withOpacity(0.3)
                                                    : AppColors.border)),
                                        child: Icon(Icons.qr_code_2,
                                            size: 48,
                                            color: hasQr
                                                ? AppColors.primary
                                                : AppColors.textLight)),
                                    const SizedBox(height: 6),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: hasQr
                                                ? AppColors.statusAvailBg
                                                : AppColors.contentBg,
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        child: Text(
                                            hasQr
                                                ? 'Generated'
                                                : 'Not Generated',
                                            style: TextStyle(
                                                color: hasQr
                                                    ? AppColors.statusAvailable
                                                    : AppColors.textLight,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700))),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 30,
                                      child: ElevatedButton(
                                          onPressed: () => _generateQr(table),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: hasQr
                                                  ? AppColors.contentBg
                                                  : AppColors.primary,
                                              foregroundColor: hasQr
                                                  ? AppColors.primary
                                                  : Colors.white,
                                              elevation: 0,
                                              padding: EdgeInsets.zero,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(7),
                                                  side: hasQr
                                                      ? const BorderSide(
                                                          color:
                                                              AppColors.primary)
                                                      : BorderSide.none)),
                                          child: Text(
                                              hasQr ? 'View QR' : 'Generate',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                    ),
                                  ]),
                                );
                              },
                            ),
                    ),
                  ]),
      
    );
  }
}
