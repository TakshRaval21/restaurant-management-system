import 'dart:async';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart';
import '../../core/config/app_theme.dart';

class BillingScreen extends StatefulWidget {
  final String? tableKey;
  final List<Map<String, dynamic>>? tableOrders;
  final Map<String, List<Map<String, dynamic>>>? orderItemsCache;
  final String? restaurantId;

  const BillingScreen({
    super.key,
    this.tableKey,
    this.tableOrders,
    this.orderItemsCache,
    this.restaurantId,
  });

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _readyOrders = [];
  List<Map<String, dynamic>> _completedBills = [];
  List<Map<String, dynamic>>? _hydratedTableOrders;

  String? _restaurantId;
  Map<String, dynamic>? _restaurantInfo;
  bool _loading = true;
  bool _billDialogShown = false;
  bool _collecting = false;

  late final TabController _tabController;

  NumberFormat get _fmt => NumberFormat.currency(
      symbol: RestaurantService.instance.symbol, decimalDigits: 2);
  double get _gstRate => RestaurantService.instance.taxRate / 100;

  static const _methods = ['cash', 'card', 'upi', 'online', 'split'];
  static const _methodIcons = {
    'cash': Icons.payments_rounded,
    'card': Icons.credit_card_rounded,
    'upi': Icons.smartphone_rounded,
    'online': Icons.language_rounded,
    'split': Icons.call_split_rounded,
  };
  static const _methodColors = {
    'cash': Color(0xFF2E7D32),
    'card': Color(0xFF1565C0),
    'upi': Color(0xFF6A1B9A),
    'online': Color(0xFF00695C),
    'split': Color(0xFFBF5500),
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _restaurantId = widget.restaurantId;
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Parse UTC timestamps correctly ─────────────────────────
  DateTime? _parseUtc(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    // Supabase sometimes omits Z — force UTC interpretation
    final normalized = s.endsWith('Z') ? s : '${s}Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }

  Future<void> _init() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    if (_restaurantId == null) {
      final r = await _sb
          .from('restaurants')
          .select('id, name, address, phone')
          .eq('owner_id', user.id)
          .maybeSingle();
      if (r == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _restaurantId = r['id'] as String;
      _restaurantInfo = r;
    } else {
      final r = await _sb
          .from('restaurants')
          .select('id, name, address, phone')
          .eq('id', _restaurantId!)
          .maybeSingle();
      _restaurantInfo = r;
    }

    if (widget.tableOrders != null) {
      await _hydrateTableOrders();
    }

    await _load();
  }

  Future<void> _hydrateTableOrders() async {
    final orders = widget.tableOrders!;
    final hydrated = <Map<String, dynamic>>[];

    for (final order in orders) {
      final orderId = order['id'] as String?;
      if (orderId == null) {
        hydrated.add(order);
        continue;
      }

      List<Map<String, dynamic>>? items =
          widget.orderItemsCache?[orderId];
      if (items == null || items.isEmpty) {
        try {
          final raw = await _sb
              .from('order_items')
              .select()
              .eq('order_id', orderId)
              .order('created_at');
          items = List<Map<String, dynamic>>.from(raw);
        } catch (_) {
          items = [];
        }
      }

      hydrated.add({...order, 'order_items': items});
    }

    if (mounted) setState(() => _hydratedTableOrders = hydrated);
  }

  Future<void> _load() async {
    // ── FIX: fetch today's payments separately with date filter
    //    so we get accurate counts regardless of timezone handling ──
    final now = DateTime.now();
    final todayStartUtc = DateTime(now.year, now.month, now.day)
        .toUtc()
        .toIso8601String();
    final tomorrowStartUtc = DateTime(now.year, now.month, now.day + 1)
        .toUtc()
        .toIso8601String();

    final results = await Future.wait([
      // All payments (for history tab)
      _sb
          .from('payments')
          .select(
              '*, orders(order_number, total_amount, tables(table_number))')
          .eq('restaurant_id', _restaurantId!)
          .eq('status', 'completed')
          .order('paid_at', ascending: false)
          .limit(200),

      // Today's payments only — filtered at DB level
      _sb
          .from('payments')
          .select('id, amount_paid, paid_at')
          .eq('restaurant_id', _restaurantId!)
          .eq('status', 'completed')
          .gte('paid_at', todayStartUtc)
          .lt('paid_at', tomorrowStartUtc),

      // Ready/served orders for pending bills
      _sb
          .from('orders')
          .select('*, tables(table_number), order_items(*)')
          .eq('restaurant_id', _restaurantId!)
          .inFilter('status', ['ready', 'served']),
    ]);

    if (!mounted) return;

    // Deduplicate payments
    final rawPayments =
        List<Map<String, dynamic>>.from(results[0]);
    final seenIds = <String>{};
    final uniquePayments = rawPayments.where((p) {
      final id = p['id']?.toString() ?? '';
      return seenIds.add(id);
    }).toList();

    // Today's payments from the DB-filtered query
    final todayPayments =
        List<Map<String, dynamic>>.from(results[1]);

    // Hydrate order_items if join returned empty
    final rawReady =
        List<Map<String, dynamic>>.from(results[2]);
    final hydratedReady = <Map<String, dynamic>>[];
    for (final order in rawReady) {
      final orderId = order['id'] as String?;
      List<Map<String, dynamic>> items =
          List<Map<String, dynamic>>.from(
              order['order_items'] ?? []);
      if (items.isEmpty && orderId != null) {
        try {
          final fetched = await _sb
              .from('order_items')
              .select()
              .eq('order_id', orderId)
              .order('created_at');
          items = List<Map<String, dynamic>>.from(fetched);
        } catch (_) {}
      }
      hydratedReady.add({...order, 'order_items': items});
    }

    setState(() {
      _payments = uniquePayments;
      _completedBills = uniquePayments;
      _readyOrders = hydratedReady;
      // Store today's stats directly from DB-filtered result
      _todayPaymentsCountVal = todayPayments.length;
      _todayRevenueVal = todayPayments.fold<double>(
          0.0,
          (s, p) =>
              s + ((p['amount_paid'] as num?)?.toDouble() ?? 0));
      _loading = false;
    });
  }

  // ── Today stats — set directly from DB query, no local parsing ──
  double _todayRevenueVal = 0;
  int _todayPaymentsCountVal = 0;

  Map<String, List<Map<String, dynamic>>> get _groupedTableOrders {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final order in _readyOrders) {
      final table = order['tables'] as Map?;
      String tableNum;
      if (table != null) {
        tableNum = table['table_number'].toString();
      } else if (order['order_type'] == 'parcel') {
        final customer = order['customer_name'] as String?;
        tableNum = customer != null && customer.isNotEmpty
            ? '📦 $customer'
            : '📦 Parcel #${order['order_number']}';
      } else {
        tableNum = 'Takeaway #${order['order_number']}';
      }
      groups.putIfAbsent(tableNum, () => []).add(order);
    }
    return groups;
  }

  List<Map<String, dynamic>> _mergeItemsFromOrders(
      List<Map<String, dynamic>> orders) {
    final merged = <String, Map<String, dynamic>>{};
    for (final order in orders) {
      final items = List<Map<String, dynamic>>.from(
          order['order_items'] ?? []);
      for (final item in items) {
        final name =
            (item['item_name'] as String?)?.trim() ?? 'Item';
        final price =
            (item['item_price'] as num? ?? 0).toDouble();
        final qty = (item['quantity'] as int? ?? 1);
        final key = name.toLowerCase();
        if (merged.containsKey(key)) {
          merged[key]!['quantity'] =
              (merged[key]!['quantity'] as int) + qty;
          merged[key]!['total'] =
              (merged[key]!['total'] as double) + price * qty;
        } else {
          merged[key] = {
            'item_name': name,
            'quantity': qty,
            'price': price,
            'total': price * qty,
          };
        }
      }
    }
    return merged.values.toList();
  }

  Map<String, double> _calculateTotals(
      List<Map<String, dynamic>> mergedItems) {
    final subtotal = mergedItems.fold<double>(
        0.0, (sum, i) => sum + (i['total'] as double? ?? 0.0));
    final gst = double.parse(
        (subtotal * _gstRate).toStringAsFixed(2));
    final grandTotal =
        double.parse((subtotal + gst).toStringAsFixed(2));
    return {
      'subtotal': subtotal,
      'gst': gst,
      'grandTotal': grandTotal
    };
  }

  String _pdfMoney(double amount) =>
      '${RestaurantService.instance.symbol} ${NumberFormat('#,##0.00').format(amount)}';

  // ── PDF — clean black & white, no colors ───────────────────
  Future<void> _generatePdfBill({
    required String tableNumber,
    required List<Map<String, dynamic>> mergedItems,
    required Map<String, double> totals,
    required String method,
    required List<String> orderIds,
  }) async {
    final notoRegular = await PdfGoogleFonts.notoSansRegular();
    final notoBold = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document();
    final now = DateTime.now();
    final dtStr = DateFormat('dd MMM yyyy').format(now);
    final timeStr = DateFormat('hh:mm a').format(now);
    final restName =
        _restaurantInfo?['name'] ?? 'Restaurant';
    final restAddr = _restaurantInfo?['address'] as String?;
    final restPhone = _restaurantInfo?['phone'] as String?;

    // ── Pure black & white palette ──
    const black = PdfColors.black;
    const white = PdfColors.white;
    const grey100 = PdfColor.fromInt(0xFFF5F5F5); // very light stripe
    const grey300 = PdfColor.fromInt(0xFFDDDDDD); // divider
    const grey600 = PdfColor.fromInt(0xFF666666); // secondary text

    final isParcel = tableNumber.startsWith('📦');
    final pdfLabel = isParcel ? 'PARCEL' : 'TABLE';
    final pdfValue =
        isParcel ? tableNumber.replaceFirst('📦 ', '') : tableNumber;

    pw.TextStyle reg(double sz, PdfColor c) =>
        pw.TextStyle(font: notoRegular, fontSize: sz, color: c);
    pw.TextStyle bold(double sz, PdfColor c) =>
        pw.TextStyle(font: notoBold, fontSize: sz, color: c);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 20 * PdfPageFormat.mm,
          marginRight: 20 * PdfPageFormat.mm,
          marginTop: 15 * PdfPageFormat.mm,
          marginBottom: 15 * PdfPageFormat.mm,
        ),
        build: (pw.Context ctx) => pw.Center(
          child: pw.Container(
            width: 170 * PdfPageFormat.mm,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: grey300, width: 1),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [

                // ── Restaurant header ──
                pw.Container(
                  color: black,
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 18, 16, 18),
                  child: pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.center,
                      children: [
                    pw.Text(restName,
                        textAlign: pw.TextAlign.center,
                        style: bold(18, white)),
                    if (restAddr != null) ...[
                      pw.SizedBox(height: 5),
                      pw.Text(restAddr,
                          textAlign: pw.TextAlign.center,
                          style: reg(8, grey300)),
                    ],
                    if (restPhone != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('Ph: $restPhone',
                          textAlign: pw.TextAlign.center,
                          style: reg(8, grey300)),
                    ],
                  ]),
                ),

                // ── Table / date row ──
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 12, 16, 12),
                  child: pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.start,
                      children: [
                    pw.Column(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                        children: [
                      pw.Text(pdfLabel,
                          style: bold(7, grey600)),
                      pw.SizedBox(height: 3),
                      pw.Text(pdfValue,
                          style: bold(20, black)),
                    ]),
                    pw.Column(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.end,
                        children: [
                      pw.Text('DATE',
                          style: bold(7, grey600)),
                      pw.SizedBox(height: 3),
                      pw.Text(dtStr,
                          style: bold(9, black)),
                      pw.Text(timeStr,
                          style: reg(9, grey600)),
                    ]),
                  ]),
                ),

                // ── Order IDs ──
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 6, 16, 6),
                  child: pw.Text(
                      'Orders: ${orderIds.join('  •  ')}',
                      style: reg(7.5, grey600)),
                ),

                pw.Container(height: 1, color: grey300),

                // ── Column header ──
                pw.Container(
                  color: grey100,
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 8, 16, 8),
                  child: pw.Row(children: [
                    pw.Expanded(
                        flex: 10,
                        child: pw.Text('ITEM',
                            style: bold(7.5, black))),
                    pw.SizedBox(
                        width: 24,
                        child: pw.Text('QTY',
                            textAlign: pw.TextAlign.center,
                            style: bold(7.5, black))),
                    pw.SizedBox(
                        width: 40,
                        child: pw.Text('RATE',
                            textAlign: pw.TextAlign.right,
                            style: bold(7.5, black))),
                    pw.SizedBox(
                        width: 48,
                        child: pw.Text('AMOUNT',
                            textAlign: pw.TextAlign.right,
                            style: bold(7.5, black))),
                  ]),
                ),

                pw.Container(height: 1, color: grey300),

                // ── Items ──
                ...mergedItems.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  final price = item['price'] as double;
                  final total = item['total'] as double;
                  // Alternate very light background for readability
                  final bg = idx % 2 == 0 ? white : grey100;
                  return pw.Container(
                    color: bg,
                    padding: const pw.EdgeInsets.fromLTRB(
                        16, 9, 16, 9),
                    child: pw.Row(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                        children: [
                      pw.Expanded(
                          flex: 10,
                          child: pw.Text(
                              item['item_name'] as String,
                              style: reg(9.5, black))),
                      pw.SizedBox(
                          width: 24,
                          child: pw.Text('x${item['quantity']}',
                              textAlign: pw.TextAlign.center,
                              style: reg(9.5, grey600))),
                      pw.SizedBox(
                          width: 40,
                          child: pw.Text(_pdfMoney(price),
                              textAlign: pw.TextAlign.right,
                              style: reg(8.5, grey600))),
                      pw.SizedBox(
                          width: 48,
                          child: pw.Text(_pdfMoney(total),
                              textAlign: pw.TextAlign.right,
                              style: bold(9.5, black))),
                    ]),
                  );
                }),

                pw.Container(height: 1, color: grey300),

                // ── Totals ──
                pw.Container(
                  color: grey100,
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 12, 16, 12),
                  child: pw.Column(children: [
                    pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceBetween,
                        children: [
                      pw.Text('Subtotal',
                          style: reg(9.5, grey600)),
                      pw.Text(_pdfMoney(totals['subtotal']!),
                          style: reg(9.5, black)),
                    ]),
                    pw.SizedBox(height: 6),
                    pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceBetween,
                        children: [
                      pw.Text(
                          'Tax @ ${RestaurantService.instance.taxRate.toStringAsFixed(0)}%',
                          style: reg(9.5, grey600)),
                      pw.Text(_pdfMoney(totals['gst']!),
                          style: reg(9.5, black)),
                    ]),
                  ]),
                ),

                pw.Container(height: 1.5, color: black),

                // ── Grand total ──
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 14, 16, 14),
                  child: pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                    pw.Text('GRAND TOTAL',
                        style: bold(13, black)),
                    pw.Text(_pdfMoney(totals['grandTotal']!),
                        style: bold(16, black)),
                  ]),
                ),

                pw.Container(height: 1, color: grey300),

                // ── Payment method ──
                pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(
                      16, 10, 16, 10),
                  child: pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                    pw.Text('Payment Mode',
                        style: reg(9, grey600)),
                    pw.Container(
                      padding:
                          const pw.EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                      decoration: pw.BoxDecoration(
                        border:
                            pw.Border.all(color: black, width: 1),
                        borderRadius:
                            pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(method.toUpperCase(),
                          style: bold(9, black)),
                    ),
                  ]),
                ),

                pw.Container(height: 1, color: grey300),

                // ── Footer ──
                pw.SizedBox(height: 18),
                pw.Center(
                  child: pw.Column(children: [
                    pw.Text('- - - - - - - - - - - - - - -',
                        style: reg(8, grey300)),
                    pw.SizedBox(height: 6),
                    pw.Text('THANK YOU',
                        textAlign: pw.TextAlign.center,
                        style: bold(11, black)),
                    pw.SizedBox(height: 4),
                    pw.Text('Please visit us again!',
                        textAlign: pw.TextAlign.center,
                        style: reg(8.5, grey600)),
                    pw.SizedBox(height: 6),
                    pw.Text('- - - - - - - - - - - - - - -',
                        style: reg(8, grey300)),
                  ]),
                ),
                pw.SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name:
          'Bill_${isParcel ? "Parcel" : "Table"}${pdfValue}_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf',
    );
  }

  // ── Collect payment ─────────────────────────────────────────
  Future<bool> _collectTablePayment({
    required List<Map<String, dynamic>> tableOrders,
    required double subtotal,
    required double gstAmt,
    required double amountPaid,
    required String method,
  }) async {
    final orderIds =
        tableOrders.map((o) => o['id'] as String).toList();
    final tableId =
        tableOrders.first['table_id'] as String?;

    try {
      final existing = await _sb
          .from('payments')
          .select('id')
          .eq('order_id', orderIds.first)
          .eq('status', 'completed')
          .maybeSingle();
      if (existing != null) {
        await _markOrdersCompleted(orderIds);
        await _resetTable(tableId);
        return true;
      }
    } catch (_) {}

    final ok = await _markOrdersCompleted(orderIds);
    if (!ok) return false;

    try {
      await _sb.from('payments').insert({
        'restaurant_id': _restaurantId,
        'amount_paid': amountPaid,
        'payment_method': method.toLowerCase(),
        'status': 'completed',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
        'order_id': orderIds.first,
      });
    } on PostgrestException catch (e) {
      if (mounted) _showDbError('Payments', e.message);
      return false;
    }

    await _resetTable(tableId);
    return true;
  }

  Future<bool> _markOrdersCompleted(
      List<String> orderIds) async {
    try {
      await _sb
          .from('orders')
          .update({'status': 'completed'}).inFilter('id', orderIds);
      return true;
    } on PostgrestException catch (e) {
      if (mounted) _showDbError('Orders', e.message);
      return false;
    }
  }

  Future<void> _resetTable(String? tableId) async {
    if (tableId == null) return;
    try {
      await _sb.from('tables').update({
        'status': 'available',
        'current_total': 0,
      }).eq('id', tableId);
    } catch (_) {}
  }

  void _showDbError(String table, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.error_outline,
              color: AppColors.red, size: 22),
          const SizedBox(width: 8),
          Text('$table Error',
              style: const TextStyle(fontSize: 16)),
        ]),
        content: Text(message,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textMid)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'))
        ],
      ),
    );
  }

  // ── Bill dialog ─────────────────────────────────────────────
  Future<void> _showTableBillDialog(String tableNumber,
      List<Map<String, dynamic>> tableOrders) async {
    final mergedItems = _mergeItemsFromOrders(tableOrders);
    final totals = _calculateTotals(mergedItems);
    String method = 'cash';
    final orderIds = tableOrders
        .map((o) => '#${o['order_number'] ?? '-'}')
        .toList();
    final billOpenedAt = DateTime.now();
    final isParcel = tableNumber.startsWith('📦');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          StatefulBuilder(builder: (ctx, setDlg) {
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                maxWidth: 520, maxHeight: 860),
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                    22, 20, 22, 18),
                decoration: BoxDecoration(
                  color: isParcel
                      ? const Color(0xFF4A1F9E)
                      : const Color(0xFF004D40),
                ),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color:
                            Colors.white.withOpacity(0.15),
                        borderRadius:
                            BorderRadius.circular(12)),
                    child: Icon(
                        isParcel
                            ? Icons.inventory_2_outlined
                            : Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                    Text(
                        _restaurantInfo?['name'] ??
                            'Restaurant',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(
                      isParcel
                          ? tableNumber
                          : 'Table $tableNumber',
                      style: const TextStyle(
                          color: Color(0xFFB2DFDB),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                        'Orders: ${orderIds.join(', ')}',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11)),
                  ])),
                  Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                    Text(
                        DateFormat('dd MMM yyyy')
                            .format(billOpenedAt),
                        style: const TextStyle(
                            color: Color(0xFFB2DFDB),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    Text(
                        DateFormat('hh:mm a')
                            .format(billOpenedAt),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () {
                        _collecting = false;
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: Colors.white
                                .withOpacity(0.15),
                            borderRadius:
                                BorderRadius.circular(7)),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 15),
                      ),
                    ),
                  ]),
                ]),
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                    Container(
                      decoration: BoxDecoration(
                          border: Border.all(
                              color: AppColors.divider),
                          borderRadius:
                              BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        Container(
                          color: const Color(0xFFF0F4F3),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10),
                          child: const Row(children: [
                            Expanded(
                                flex: 4,
                                child: Text('ITEM',
                                    style: AppText.label)),
                            SizedBox(
                                width: 36,
                                child: Text('QTY',
                                    style: AppText.label,
                                    textAlign:
                                        TextAlign.center)),
                            SizedBox(
                                width: 58,
                                child: Text('RATE',
                                    style: AppText.label,
                                    textAlign:
                                        TextAlign.right)),
                            SizedBox(
                                width: 68,
                                child: Text('AMOUNT',
                                    style: AppText.label,
                                    textAlign:
                                        TextAlign.right)),
                          ]),
                        ),
                        const Divider(
                            height: 1,
                            color: AppColors.divider),
                        if (mergedItems.isEmpty)
                          Container(
                            padding:
                                const EdgeInsets.all(24),
                            child: const Center(
                              child: Text('No items found.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          AppColors.textMid)),
                            ),
                          )
                        else
                          ...mergedItems.asMap().entries.map(
                              (entry) {
                            final i = entry.value;
                            final isEven =
                                entry.key % 2 == 0;
                            return Container(
                              color: isEven
                                  ? Colors.white
                                  : const Color(0xFFFAFCFB),
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10),
                              child: Row(children: [
                                Expanded(
                                    flex: 4,
                                    child: Text(
                                        i['item_name']
                                            as String,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w600,
                                            fontSize: 13,
                                            color: AppColors
                                                .textDark))),
                                SizedBox(
                                    width: 36,
                                    child: Text(
                                        '${i['quantity']}',
                                        textAlign:
                                            TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors
                                                .textDark))),
                                SizedBox(
                                    width: 58,
                                    child: Text(
                                        _fmt.format(i['price']
                                            as double),
                                        textAlign:
                                            TextAlign.right,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors
                                                .textMid))),
                                SizedBox(
                                    width: 68,
                                    child: Text(
                                        _fmt.format(i['total']
                                            as double),
                                        textAlign:
                                            TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w700,
                                            fontSize: 13,
                                            color: AppColors
                                                .textDark))),
                              ]),
                            );
                          }),

                        Container(
                          padding: const EdgeInsets.fromLTRB(
                              14, 12, 14, 14),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5F8F7),
                            border: Border(
                                top: BorderSide(
                                    color: AppColors.divider)),
                          ),
                          child: Column(children: [
                            _totalRow('Subtotal',
                                _fmt.format(totals['subtotal']!)),
                            const SizedBox(height: 6),
                            _totalRow(
                                'Tax (${RestaurantService.instance.taxRate.toStringAsFixed(0)}%)',
                                _fmt.format(totals['gst']!)),
                            const Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 10),
                                child: Divider(
                                    height: 1,
                                    color: AppColors.divider)),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment
                                        .spaceBetween,
                                children: [
                              const Text('GRAND TOTAL',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.w800,
                                      fontSize: 15,
                                      color:
                                          AppColors.textDark)),
                              Text(
                                  _fmt.format(
                                      totals['grandTotal']!),
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.w900,
                                      fontSize: 20,
                                      color: isParcel
                                          ? const Color(
                                              0xFF7B3FF2)
                                          : const Color(
                                              0xFF004D40))),
                            ]),
                          ]),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 22),
                    const Text('Payment Method',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textDark)),
                    const SizedBox(height: 12),

                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _methods.map((m) {
                        final sel = method == m;
                        final clr =
                            _methodColors[m] ?? AppColors.primary;
                        return GestureDetector(
                          onTap: () =>
                              setDlg(() => method = m),
                          child: AnimatedContainer(
                            duration: const Duration(
                                milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 11),
                            decoration: BoxDecoration(
                              color: sel
                                  ? clr
                                  : clr.withOpacity(0.06),
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                  color: sel
                                      ? clr
                                      : clr.withOpacity(0.3),
                                  width: sel ? 2 : 1),
                              boxShadow: sel
                                  ? [
                                      BoxShadow(
                                          color: clr
                                              .withOpacity(0.25),
                                          blurRadius: 8,
                                          offset:
                                              const Offset(0, 3))
                                    ]
                                  : [],
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Icon(_methodIcons[m],
                                  color: sel ? Colors.white : clr,
                                  size: 17),
                              const SizedBox(width: 7),
                              Text(
                                '${m[0].toUpperCase()}${m.substring(1)}',
                                style: TextStyle(
                                    color: sel
                                        ? Colors.white
                                        : clr,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ]),
                ),
              ),

              // Action bar
              Container(
                padding: const EdgeInsets.fromLTRB(
                    20, 14, 20, 16),
                decoration: const BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: AppColors.divider))),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _generatePdfBill(
                          tableNumber: tableNumber,
                          mergedItems: mergedItems,
                          totals: totals,
                          method: method,
                          orderIds: orderIds,
                        );
                      },
                      icon: const Icon(
                          Icons.print_rounded,
                          size: 18),
                      label: const Text('Print'),
                      style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(
                                  vertical: 14),
                          side: BorderSide(
                              color: isParcel
                                  ? const Color(0xFF7B3FF2)
                                  : const Color(0xFF004D40)),
                          foregroundColor: isParcel
                              ? const Color(0xFF7B3FF2)
                              : const Color(0xFF004D40),
                          textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child:
                        StatefulBuilder(builder: (_, setBtnState) {
                      return ElevatedButton.icon(
                        onPressed: _collecting
                            ? null
                            : () async {
                                setBtnState(
                                    () => _collecting = true);
                                final ok =
                                    await _collectTablePayment(
                                  tableOrders: tableOrders,
                                  subtotal: totals['subtotal']!,
                                  gstAmt: totals['gst']!,
                                  amountPaid:
                                      totals['grandTotal']!,
                                  method: method,
                                );
                                if (ok && mounted) {
                                  _collecting = false;
                                  Navigator.pop(ctx);
                                  _snack(
                                      '✓ Payment collected for $tableNumber');
                                  await _load();
                                } else {
                                  setBtnState(
                                      () => _collecting = false);
                                }
                              },
                        icon: _collecting
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                  child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
                            : const Icon(
                                Icons.check_circle_rounded,
                                size: 18),
                        label: Text(_collecting
                            ? 'Processing...'
                            : 'Collect ${_fmt.format(totals['grandTotal']!)}'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: isParcel
                                ? const Color(0xFF7B3FF2)
                                : const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: (isParcel
                                    ? const Color(0xFF7B3FF2)
                                    : const Color(0xFF004D40))
                                .withOpacity(0.6),
                            disabledForegroundColor:
                                Colors.white70,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      );
                    }),
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // ── Reprint ─────────────────────────────────────────────────
  Future<void> _reprintBill(
      Map<String, dynamic> payment) async {
    final order = payment['orders'] as Map?;
    final table = order?['tables'] as Map?;
    final tableNumber =
        table?['table_number']?.toString() ?? 'Takeaway';
    final method =
        payment['payment_method'] as String? ?? 'cash';
    final amountPaid =
        (payment['amount_paid'] as num?)?.toDouble() ?? 0;
    final subtotal = amountPaid / (1 + _gstRate);
    final gst = amountPaid - subtotal;

    final orderId = payment['order_id'] as String?;
    List<Map<String, dynamic>> items = [];
    if (orderId != null) {
      try {
        final raw = await _sb
            .from('order_items')
            .select()
            .eq('order_id', orderId);
        items = List<Map<String, dynamic>>.from(raw);
      } catch (_) {}
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final name =
          (item['item_name'] as String?)?.trim() ?? 'Item';
      final price =
          (item['item_price'] as num? ?? 0).toDouble();
      final qty = (item['quantity'] as int? ?? 1);
      final key = name.toLowerCase();
      if (merged.containsKey(key)) {
        merged[key]!['quantity'] =
            (merged[key]!['quantity'] as int) + qty;
        merged[key]!['total'] =
            (merged[key]!['total'] as double) + price * qty;
      } else {
        merged[key] = {
          'item_name': name,
          'quantity': qty,
          'price': price,
          'total': price * qty
        };
      }
    }

    await _generatePdfBill(
      tableNumber: tableNumber,
      mergedItems: merged.values.toList(),
      totals: {
        'subtotal': subtotal,
        'gst': gst,
        'grandTotal': amountPaid
      },
      method: method,
      orderIds: ['#${order?['order_number'] ?? '-'}'],
    );
  }

  // ── Helpers ─────────────────────────────────────────────────
  Widget _totalRow(String label, String value) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMid)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark)),
        ]);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? AppColors.red
            : const Color(0xFF004D40),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10))));
  }

  // ── Table card ───────────────────────────────────────────────
  Widget _buildTableCard(String tableNumber,
      List<Map<String, dynamic>> tableOrders) {
    final mergedItems = _mergeItemsFromOrders(tableOrders);
    final totals = _calculateTotals(mergedItems);
    final isParcel = tableNumber.startsWith('📦');

    return GestureDetector(
      onTap: () =>
          _showTableBillDialog(tableNumber, tableOrders),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: (isParcel
                      ? const Color(0xFF7B3FF2)
                      : const Color(0xFF004D40))
                  .withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
                color: (isParcel
                        ? const Color(0xFF7B3FF2)
                        : const Color(0xFF004D40))
                    .withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: isParcel
                      ? const Color(0xFF7B3FF2)
                          .withOpacity(0.1)
                      : const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(
                isParcel
                    ? Icons.inventory_2_outlined
                    : Icons.table_restaurant_rounded,
                color: isParcel
                    ? const Color(0xFF7B3FF2)
                    : const Color(0xFF004D40),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
              Text(
                isParcel
                    ? tableNumber
                    : 'Table $tableNumber',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textDark),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                  '${tableOrders.length} order${tableOrders.length > 1 ? 's' : ''} · ${mergedItems.length} items',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMid)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: isParcel
                      ? const Color(0xFF7B3FF2)
                          .withOpacity(0.1)
                      : const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('Ready to Pay',
                  style: TextStyle(
                      fontSize: 10,
                      color: isParcel
                          ? const Color(0xFF7B3FF2)
                          : const Color(0xFF004D40),
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          ...mergedItems.take(3).map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: isParcel
                            ? const Color(0xFF7B3FF2)
                                .withOpacity(0.1)
                            : const Color(0xFFE0F2F1),
                        borderRadius:
                            BorderRadius.circular(5)),
                    child: Text('${i['quantity']}',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isParcel
                                ? const Color(0xFF7B3FF2)
                                : const Color(0xFF004D40))),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                      child: Text(
                          i['item_name'] as String,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textDark),
                          overflow: TextOverflow.ellipsis)),
                  Text(_fmt.format(i['total'] as double),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark)),
                ]),
              )),
          if (mergedItems.length > 3)
            Text('+ ${mergedItems.length - 3} more items',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMid)),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('GRAND TOTAL',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textMid,
                      fontWeight: FontWeight.w600)),
              Text(_fmt.format(totals['grandTotal']!),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: isParcel
                          ? const Color(0xFF7B3FF2)
                          : const Color(0xFF004D40))),
              Text(
                  'incl. ${RestaurantService.instance.taxRate.toStringAsFixed(0)}% tax',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMid)),
            ]),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showTableBillDialog(
                  tableNumber, tableOrders),
              icon:
                  const Icon(Icons.receipt_rounded, size: 16),
              label: const Text('View & Pay'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: isParcel
                      ? const Color(0xFF7B3FF2)
                      : const Color(0xFF004D40),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Bills history tab ────────────────────────────────────────
  Widget _buildBillsHistoryTab() {
    if (_completedBills.isEmpty) {
      return Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                color: Color(0xFFE0F2F1),
                shape: BoxShape.circle),
            child: const Icon(Icons.receipt_long_rounded,
                size: 32, color: Color(0xFF004D40)),
          ),
          const SizedBox(height: 14),
          const Text('No past bills yet', style: AppText.h4),
          const SizedBox(height: 6),
          const Text('Completed bills will appear here',
              style: AppText.body),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _completedBills.length,
      itemBuilder: (_, i) {
        final bill = _completedBills[i];
        final order = bill['orders'] as Map?;
        final table = order?['tables'] as Map?;
        final tableLabel = table != null
            ? 'Table ${table['table_number']}'
            : '#${order?['order_number'] ?? '—'}';
        final method =
            bill['payment_method'] as String? ?? 'cash';
        final amount =
            (bill['amount_paid'] as num?)?.toDouble() ?? 0;
        final dt = _parseUtc(bill['paid_at']);
        final clr = _methodColors[method] ?? AppColors.primary;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_long_rounded,
                  color: Color(0xFF004D40), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
              Text(tableLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.textDark)),
              const SizedBox(height: 3),
              Row(children: [
                Icon(
                    _methodIcons[method] ??
                        Icons.payments_outlined,
                    size: 12,
                    color: clr),
                const SizedBox(width: 4),
                Text(method.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: clr)),
                const SizedBox(width: 10),
                if (dt != null)
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a')
                        .format(dt),
                    style: AppText.bodySmall,
                  ),
              ]),
            ])),
            Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
              Text(_fmt.format(amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF004D40))),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _reprintBill(bill),
                icon: const Icon(Icons.print_rounded,
                    size: 13),
                label: const Text('Reprint'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF004D40),
                    side: const BorderSide(
                        color: Color(0xFF004D40)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.tableKey != null &&
        _hydratedTableOrders != null &&
        !_loading &&
        !_billDialogShown) {
      _billDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTableBillDialog(
            widget.tableKey!, _hydratedTableOrders!);
      });
    }

    final cols = Responsive.gridCount(context,
        mobile: 1, tablet: 2, desktop: 3);
    final groupedOrders = _groupedTableOrders;

    return _loading
        ? Center(
                  child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
            : Column(children: [
            Container(
              color: AppColors.cardBg,
              padding:
                  const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                const Text('Billing', style: AppText.h1),
                const SizedBox(height: 2),
                const Text(
                    'Collect payments and manage invoices',
                    style: AppText.body),
                const SizedBox(height: 16),
                TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelColor: const Color(0xFF004D40),
                  unselectedLabelColor: AppColors.textMid,
                  indicatorColor: const Color(0xFF004D40),
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                  tabs: [
                    Tab(
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        const Icon(
                            Icons.receipt_outlined,
                            size: 16),
                        const SizedBox(width: 7),
                        const Text('Pending Bills'),
                        if (groupedOrders.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFF004D40),
                                borderRadius:
                                    BorderRadius.circular(
                                        10)),
                            child: Text(
                                '${groupedOrders.length}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w800)),
                          ),
                        ],
                      ]),
                    ),
                    Tab(
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        const Icon(
                            Icons.history_rounded,
                            size: 16),
                        const SizedBox(width: 7),
                        const Text('Bills History'),
                        if (_completedBills.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1),
                            decoration: BoxDecoration(
                                color: AppColors.textMid
                                    .withOpacity(0.15),
                                borderRadius:
                                    BorderRadius.circular(
                                        10)),
                            child: Text(
                                '${_completedBills.length}',
                                style: const TextStyle(
                                    color: AppColors.textMid,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w800)),
                          ),
                        ],
                      ]),
                    ),
                  ],
                ),
              ]),
            ),
            const Divider(
                color: AppColors.divider, height: 1),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    padding: Responsive.padding(context),
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                      LayoutBuilder(
                          builder: (ctx, constraints) {
                        final cardCols =
                            Responsive.isMobile(context)
                                ? 1
                                : 3;
                        const spacing = 12.0;
                        final cardW = (constraints.maxWidth -
                                spacing * (cardCols - 1)) /
                            cardCols;
                        return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                          SizedBox(
                              width:
                                  cardW.clamp(120.0, 400.0),
                              child: _StatCard2(
                                  label: "Today's Revenue",
                                  value: _fmt.format(
                                      _todayRevenueVal),
                                  icon: Icons
                                      .currency_rupee_sharp,
                                  color: AppColors.green)),
                          SizedBox(
                              width:
                                  cardW.clamp(120.0, 400.0),
                              child: _StatCard2(
                                  label: 'Pending Bills',
                                  value:
                                      '${groupedOrders.length}',
                                  icon:
                                      Icons.receipt_outlined,
                                  color: AppColors.orange)),
                          SizedBox(
                              width:
                                  cardW.clamp(120.0, 400.0),
                              child: _StatCard2(
                                  label: 'Payments Today',
                                  value:
                                      '$_todayPaymentsCountVal',
                                  icon: Icons
                                      .check_circle_outline,
                                  color: AppColors.primary)),
                        ]);
                      }),
                      const SizedBox(height: 24),

                      if (groupedOrders.isNotEmpty) ...[
                        Row(children: [
                          const Text('Ready for Billing',
                              style: AppText.h2),
                          const SizedBox(width: 10),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFFE0F2F1),
                                borderRadius:
                                    BorderRadius.circular(
                                        20)),
                            child: Text(
                                '${groupedOrders.length}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color:
                                        Color(0xFF004D40),
                                    fontWeight:
                                        FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio:
                                      Responsive.isMobile(
                                              context)
                                          ? 1.6
                                          : 1.2),
                          itemCount: groupedOrders.length,
                          itemBuilder: (_, i) {
                            final tableNum =
                                groupedOrders.keys
                                    .elementAt(i);
                            final orders =
                                groupedOrders[tableNum]!;
                            return _buildTableCard(
                                tableNum, orders);
                          },
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 60),
                          alignment: Alignment.center,
                          child: Column(children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFE0F2F1),
                                  shape: BoxShape.circle),
                              child: const Icon(
                                  Icons
                                      .check_circle_outline_rounded,
                                  size: 32,
                                  color: Color(0xFF004D40)),
                            ),
                            const SizedBox(height: 14),
                            const Text('All cleared!',
                                style: AppText.h4),
                            const SizedBox(height: 6),
                            const Text(
                                'No pending payments right now.',
                                style: AppText.body),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ]),
                  ),
                  _buildBillsHistoryTab(),
                ],
              ),
            ),
          ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  Stat Card
// ─────────────────────────────────────────────────────────────
class _StatCard2 extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatCard2({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color, size: 21)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
            Text(label,
                style: AppText.bodySmall,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppColors.textDark))),
          ])),
        ]),
      );
}