import 'dart:async';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:admin_side/screens/billing/billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart';
import '../../core/config/app_theme.dart';

class OrdersScreen extends StatefulWidget {
  /// Called when "Generate Bill" is tapped.
  /// Passes billing context up to the layout so it can display
  /// BillingScreen in the content panel without Navigator.
  final void Function(int index)? onNavigate;

  /// Called with billing data when Generate Bill is tapped,
  /// so the layout can pass it into BillingScreen.
  final void Function({
    required String tableKey,
    required List<Map<String, dynamic>> tableOrders,
    required Map<String, List<Map<String, dynamic>>> orderItemsCache,
    required String? restaurantId,
  })? onBill;

  const OrdersScreen({super.key, this.onNavigate, this.onBill});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _orders = [];
  String? _restaurantId;
  bool _loading = true;
  bool _disposed = false;
  String _filterStatus = 'all';
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _itemsChannel;

  String? _selectedTableKey;

  static const _statuses = [
    'all', 'pending', 'confirmed', 'preparing', 'ready', 'served', 'cancelled'
  ];

  static const _statusConfig = {
    'pending':   (Color(0xFFFFF3E0), Color(0xFFBF5500), Icons.hourglass_empty_rounded),
    'confirmed': (Color(0xFFE3F2FD), Color(0xFF1565C0), Icons.check_rounded),
    'preparing': (Color(0xFFFFF8E1), Color(0xFFF57C00), Icons.soup_kitchen_rounded),
    'ready':     (Color(0xFFE8F5E9), Color(0xFF2E7D32), Icons.check_circle_rounded),
    'served':    (Color(0xFFE0F2F1), Color(0xFF00695C), Icons.restaurant_rounded),
    'cancelled': (Color(0xFFFFEBEE), Color(0xFFE53935), Icons.cancel_rounded),
  };

  final Map<String, List<Map<String, dynamic>>> _orderItemsCache = {};
  Timer? _debounce;

  static const _billedStatuses = ['completed', 'billed'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _ordersChannel?.unsubscribe();
    _itemsChannel?.unsubscribe();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  Future<void> _init() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final r = await _sb
        .from('restaurants')
        .select('id')
        .eq('owner_id', user.id)
        .maybeSingle();
    if (_disposed || !mounted) return;
    if (r == null) {
      _safeSetState(() => _loading = false);
      return;
    }
    _restaurantId = r['id'] as String;
    await _load();
    if (_disposed || !mounted) return;

    _ordersChannel = _sb.channel('orders-live-$_restaurantId')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'restaurant_id',
              value: _restaurantId!),
          callback: (_) {
            if (!_disposed && mounted) {
              _debounce?.cancel();
              _debounce =
                  Timer(const Duration(milliseconds: 300), _load);
            }
          })
      ..subscribe();

    _itemsChannel = _sb.channel('order-items-live-$_restaurantId')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (payload) {
            if (!_disposed && mounted) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300),
                  () => _onItemChanged(payload));
            }
          })
      ..subscribe();
  }

  Future<void> _load() async {
    final data = await _sb
        .from('orders')
        .select(
            '*, tables(table_number, section), employees(full_name)')
        .eq('restaurant_id', _restaurantId!)
        .not('status', 'in', '("completed","billed")')
        .order('created_at', ascending: false)
        .limit(200);

    if (_disposed || !mounted) return;
    _safeSetState(() {
      _orders = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });

    if (_selectedTableKey != null) {
      final tableOrders = _groupedByTable[_selectedTableKey] ?? [];
      if (tableOrders.isEmpty) {
        _safeSetState(() => _selectedTableKey = null);
        return;
      }
      for (final o in tableOrders) {
        await _loadItemsForOrder(o['id'] as String);
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _onItemChanged(
      PostgresChangePayload payload) async {
    final orderId = (payload.newRecord['order_id'] ??
        payload.oldRecord['order_id']) as String?;
    if (orderId == null) return;
    await _loadItemsForOrder(orderId);
    if (mounted) setState(() {});
  }

  Future<void> _loadItemsForOrder(String orderId) async {
    final items = await _sb
        .from('order_items')
        .select()
        .eq('order_id', orderId)
        .order('created_at');
    _orderItemsCache[orderId] =
        List<Map<String, dynamic>>.from(items);
  }

  void _clearTableCache(String tableKey) {
    final tableOrders = _groupedByTable[tableKey] ?? [];
    for (final o in tableOrders) {
      _orderItemsCache.remove(o['id'] as String);
    }
  }

  List<Map<String, dynamic>> get _filtered =>
      _filterStatus == 'all'
          ? _orders
          : _orders
              .where((o) => o['status'] == _filterStatus)
              .toList();

  Map<String, List<Map<String, dynamic>>> get _groupedByTable {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final o in _filtered) {
      final table = o['tables'] as Map?;
      String key;
      if (table != null) {
        key = 'Table ${table['table_number']}';
      } else if (o['order_type'] == 'parcel') {
        final customer = o['customer_name'] as String?;
        key = customer != null && customer.isNotEmpty
            ? '📦 $customer'
            : '📦 Parcel';
      } else {
        key = 'Takeaway';
      }
      grouped.putIfAbsent(key, () => []).add(o);
    }
    final sorted = Map.fromEntries(grouped.entries.toList()
      ..sort((a, b) {
        final aActive = a.value.any((o) =>
            !['served', 'cancelled'].contains(o['status']));
        final bActive = b.value.any((o) =>
            !['served', 'cancelled'].contains(o['status']));
        if (aActive && !bActive) return -1;
        if (!aActive && bActive) return 1;
        return a.key.compareTo(b.key);
      }));
    return sorted;
  }

  Future<void> _updateStatus(String id, String status) async {
    await _sb
        .from('orders')
        .update({'status': status}).eq('id', id);
    final idx = _orders.indexWhere((o) => o['id'] == id);
    if (idx != -1) {
      _safeSetState(() => _orders[idx]['status'] = status);
    }
  }

  void _nextStatus(Map<String, dynamic> o) {
    const flow = [
      'pending',
      'confirmed',
      'preparing',
      'ready',
      'served'
    ];
    final cur = o['status'] as String? ?? 'pending';
    final idx = flow.indexOf(cur);
    if (idx >= 0 && idx < flow.length - 1) {
      _updateStatus(o['id'], flow[idx + 1]);
    }
  }

  Future<void> _selectTable(String tableKey) async {
    _safeSetState(() => _selectedTableKey = tableKey);
    final tableOrders = _groupedByTable[tableKey] ?? [];
    for (final o in tableOrders) {
      if (!_orderItemsCache.containsKey(o['id'])) {
        await _loadItemsForOrder(o['id'] as String);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final fmt = NumberFormat.currency(
        symbol: RestaurantService.instance.symbol,
        decimalDigits: 2);
    final activeCount = _orders
        .where((o) => ![
              'served',
              'cancelled',
              ..._billedStatuses
            ].contains(o['status']))
        .length;

    return _loading
        ? Center(
            child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
        : Column(children: [
            _buildHeader(isMobile, activeCount),
            const Divider(color: AppColors.divider, height: 1),
            Expanded(
              child: _filtered.isEmpty
                  ? _buildEmpty()
                  : isMobile
                      ? _buildMobileLayout(fmt)
                      : _buildDesktopLayout(fmt),
            ),
          ]);
  }

  Widget _buildHeader(bool isMobile, int activeCount) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 24, 16, isMobile ? 14 : 24, 12),
      color: AppColors.contentBg,
      child: Column(children: [
        Row(children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Orders', style: AppText.h1),
                Text(
                    '${_filtered.length} orders · $activeCount active',
                    style: AppText.body),
              ]),
          const Spacer(),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
              children: _statuses.skip(1).map((s) {
            final count =
                _orders.where((o) => o['status'] == s).length;
            final (bg, fg, icon) = _statusConfig[s] ??
                (AppColors.contentBg, AppColors.textMid,
                    Icons.circle_outlined);
            final active = _filterStatus == s;
            return GestureDetector(
              onTap: () => _safeSetState(() {
                _filterStatus =
                    s == _filterStatus ? 'all' : s;
                _selectedTableKey = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: active ? fg : bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: fg.withOpacity(active ? 1 : 0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 13,
                      color: active ? Colors.white : fg),
                  const SizedBox(width: 5),
                  Text(
                      '${s[0].toUpperCase()}${s.substring(1)} ($count)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : fg)),
                ]),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  Widget _buildDesktopLayout(NumberFormat fmt) {
    return Row(children: [
      if (_selectedTableKey != null)
        SizedBox(width: 380, child: _buildTableGrid(fmt))
      else
        Expanded(child: _buildTableGrid(fmt)),
      if (_selectedTableKey != null) ...[
        const VerticalDivider(color: AppColors.divider, width: 1),
        Expanded(child: _buildDetailPanel(fmt)),
      ],
    ]);
  }

  Widget _buildMobileLayout(NumberFormat fmt) {
    if (_selectedTableKey != null) return _buildDetailPanel(fmt);
    return _buildTableGrid(fmt);
  }

  Widget _buildTableGrid(NumberFormat fmt) {
    final grouped = _groupedByTable;
    final isMobile = Responsive.isMobile(context);
    final cols = _selectedTableKey != null
        ? 2
        : Responsive.gridCount(context,
            mobile: 2, tablet: 3, desktop: 4);

    return GridView.builder(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio:
            _selectedTableKey != null ? 0.9 : 1.1,
      ),
      itemCount: grouped.length,
      itemBuilder: (_, i) {
        final entry = grouped.entries.elementAt(i);
        final label = entry.key;
        final orders = entry.value;
        final isSelected = _selectedTableKey == label;
        return _TableGridCard(
          tableLabel: label,
          orders: orders,
          statusConfig: _statusConfig,
          fmt: fmt,
          isSelected: isSelected,
          onTap: () => _selectTable(label),
        );
      },
    );
  }

  Widget _buildDetailPanel(NumberFormat fmt) {
    final tableOrders =
        _groupedByTable[_selectedTableKey] ?? [];
    final isMobile = Responsive.isMobile(context);

    final tableTotal = tableOrders
        .where((o) => o['status'] != 'cancelled')
        .expand((o) => (_orderItemsCache[o['id']] ?? []))
        .fold<double>(
            0,
            (s, i) =>
                s +
                ((i['item_price'] as num? ?? 0) *
                    (i['quantity'] as int? ?? 1)));

    final allServed = tableOrders.isNotEmpty &&
        tableOrders
            .where((o) => o['status'] != 'cancelled')
            .every((o) =>
                ['served', 'ready'].contains(o['status']));

    const priority = [
      'preparing',
      'confirmed',
      'pending',
      'ready',
      'served',
      'cancelled'
    ];
    String topStatus = 'served';
    for (final p in priority) {
      if (tableOrders.any((o) => o['status'] == p)) {
        topStatus = p;
        break;
      }
    }
    final (_, accentFg, _) = _statusConfig[topStatus] ??
        (AppColors.contentBg, AppColors.primary,
            Icons.circle_outlined);

    final isParcel =
        _selectedTableKey?.startsWith('📦') ?? false;

    return Container(
      color: AppColors.contentBg,
      child: Column(children: [
        Container(
          padding:
              const EdgeInsets.fromLTRB(20, 16, 20, 14),
          color: AppColors.cardBg,
          child: Row(children: [
            if (isMobile)
              GestureDetector(
                onTap: () => _safeSetState(
                    () => _selectedTableKey = null),
                child: Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.contentBg,
                      borderRadius: BorderRadius.circular(9),
                      border:
                          Border.all(color: AppColors.border)),
                  child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 14,
                      color: AppColors.textMid),
                ),
              ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: isParcel
                      ? const Color(0xFF7B3FF2)
                          .withOpacity(0.12)
                      : accentFg.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(
                isParcel
                    ? Icons.inventory_2_outlined
                    : Icons.table_restaurant_rounded,
                color: isParcel
                    ? const Color(0xFF7B3FF2)
                    : accentFg,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
              Text(_selectedTableKey!,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark)),
              Text(
                  '${tableOrders.length} order${tableOrders.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMid)),
            ])),
            if (allServed) ...[
              Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                Text(
                    RestaurantService.instance
                        .formatPrice(tableTotal),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isParcel
                            ? const Color(0xFF7B3FF2)
                            : accentFg)),
                const Text('Table Total',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMid)),
              ]),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                // ── KEY FIX: instead of Navigator.push with a
                //    full Scaffold, call onBill() to pass billing
                //    data up to the layout, then onNavigate(8) to
                //    switch the content panel to BillingScreen. ──
                onPressed: () {
                  final key = _selectedTableKey!;
                  widget.onBill?.call(
                    tableKey: key,
                    tableOrders: tableOrders,
                    orderItemsCache: _orderItemsCache,
                    restaurantId: _restaurantId,
                  );
                  _clearTableCache(key);
                  _safeSetState(
                      () => _selectedTableKey = null);
                  widget.onNavigate?.call(8);
                },
                icon: const Icon(Icons.receipt_long_rounded,
                    size: 15),
                label: const Text('Generate Bill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isParcel
                      ? const Color(0xFF7B3FF2)
                      : const Color(0xFF00695C),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ]),
        ),

        const Divider(color: AppColors.divider, height: 1),

        Expanded(
          child: tableOrders.isEmpty
              ? const Center(
                  child:
                      Text('No orders for this table'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: tableOrders.length,
                  itemBuilder: (_, i) {
                    final o = tableOrders[i];
                    final items =
                        _orderItemsCache[o['id']] ?? [];
                    return _OrderDetailCard(
                      order: o,
                      items: items,
                      statusConfig: _statusConfig,
                      fmt: fmt,
                      onStatusChange: (s) =>
                          _updateStatus(o['id'], s),
                      onNextStatus: () => _nextStatus(o),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _buildEmpty() => Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.receipt_long_outlined,
                size: 36, color: AppColors.primary)),
        const SizedBox(height: 14),
        const Text('No orders found', style: AppText.h4),
        const SizedBox(height: 6),
        const Text('Orders will appear here in real time',
            style: AppText.body),
      ]));
}

// ─────────────────────────────────────────────────────────────
//  Table Grid Card
// ─────────────────────────────────────────────────────────────
class _TableGridCard extends StatelessWidget {
  final String tableLabel;
  final List<Map<String, dynamic>> orders;
  final Map<String, (Color, Color, IconData)> statusConfig;
  final NumberFormat fmt;
  final bool isSelected;
  final VoidCallback onTap;

  const _TableGridCard({
    required this.tableLabel,
    required this.orders,
    required this.statusConfig,
    required this.fmt,
    required this.isSelected,
    required this.onTap,
  });

  bool get _hasActive => orders.any((o) => ![
        'served',
        'cancelled',
        'completed',
        'billed'
      ].contains(o['status']));

  bool get _isParcel => tableLabel.startsWith('📦');

  @override
  Widget build(BuildContext context) {
    const priority = [
      'preparing',
      'confirmed',
      'pending',
      'ready',
      'served',
      'cancelled'
    ];
    String topStatus = 'served';
    for (final p in priority) {
      if (orders.any((o) => o['status'] == p)) {
        topStatus = p;
        break;
      }
    }
    final (bg, fg, icon) = statusConfig[topStatus] ??
        (AppColors.contentBg, AppColors.textMid,
            Icons.circle_outlined);

    final activeOrders = orders
        .where((o) => ![
              'served',
              'cancelled',
              'completed',
              'billed'
            ].contains(o['status']))
        .toList();

    final cardFg = _isParcel ? const Color(0xFF7B3FF2) : fg;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? cardFg.withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected
                  ? cardFg
                  : (_hasActive
                      ? cardFg.withOpacity(0.35)
                      : AppColors.border),
              width: isSelected ? 2 : 1.5),
          boxShadow: [
            BoxShadow(
                color: isSelected
                    ? cardFg.withOpacity(0.15)
                    : AppColors.shadow,
                blurRadius: isSelected ? 16 : 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: _hasActive
                            ? cardFg.withOpacity(0.12)
                            : AppColors.contentBg,
                        borderRadius:
                            BorderRadius.circular(10)),
                    child: Icon(
                      _isParcel
                          ? Icons.inventory_2_outlined
                          : Icons.table_restaurant_rounded,
                      color: _hasActive
                          ? cardFg
                          : AppColors.textLight,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  if (_hasActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: cardFg.withOpacity(0.12),
                          borderRadius:
                              BorderRadius.circular(20)),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon,
                                size: 9, color: cardFg),
                            const SizedBox(width: 3),
                            Text(
                                topStatus[0].toUpperCase() +
                                    topStatus.substring(1),
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: cardFg)),
                          ]),
                    ),
                ]),
                const SizedBox(height: 10),
                Text(tableLabel,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                const SizedBox(height: 4),
                Text(
                  activeOrders.isEmpty
                      ? 'No active orders'
                      : '${activeOrders.length} active order${activeOrders.length != 1 ? 's' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: _hasActive
                          ? cardFg
                          : AppColors.textLight,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (activeOrders.isNotEmpty) ...[
                  Row(
                      children:
                          activeOrders.take(4).map((o) {
                    final s =
                        o['status'] as String? ?? 'pending';
                    final (_, sfg, _) = statusConfig[s] ??
                        (AppColors.contentBg,
                            AppColors.textMid,
                            Icons.circle_outlined);
                    return Container(
                      width: 8,
                      height: 8,
                      margin:
                          const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                          color: sfg,
                          shape: BoxShape.circle),
                    );
                  }).toList()),
                  const SizedBox(height: 8),
                ],
                Row(children: [
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 18,
                      color: isSelected
                          ? cardFg
                          : AppColors.textLight),
                ]),
              ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Order Detail Card
// ─────────────────────────────────────────────────────────────
class _OrderDetailCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  final Map<String, (Color, Color, IconData)> statusConfig;
  final NumberFormat fmt;
  final void Function(String) onStatusChange;
  final VoidCallback onNextStatus;

  const _OrderDetailCard({
    required this.order,
    required this.items,
    required this.statusConfig,
    required this.fmt,
    required this.onStatusChange,
    required this.onNextStatus,
  });

  @override
  State<_OrderDetailCard> createState() =>
      _OrderDetailCardState();
}

class _OrderDetailCardState extends State<_OrderDetailCard> {
  bool _expanded = true;

  DateTime? _parseUtc(String? raw) {
    if (raw == null) return null;
    final normalized =
        raw.endsWith('Z') ? raw : '${raw}Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final status =
        widget.order['status'] as String? ?? 'pending';
    final (bg, fg, icon) = widget.statusConfig[status] ??
        (AppColors.contentBg, AppColors.textMid,
            Icons.circle_outlined);
    final isDone = [
      'served',
      'cancelled',
      'completed',
      'billed'
    ].contains(status);
    final emp = widget.order['employees'] as Map?;
    final dt = _parseUtc(widget.order['created_at']);
    final fmt = widget.fmt;

    final itemsTotal = widget.items.fold<double>(
        0,
        (s, i) =>
            s +
            ((i['item_price'] as num? ?? 0) *
                (i['quantity'] as int? ?? 1)));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDone
                ? AppColors.border
                : fg.withOpacity(0.25),
            width: isDone ? 1 : 1.5),
        boxShadow: [
          BoxShadow(
              color: isDone
                  ? AppColors.shadow
                  : fg.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        InkWell(
          onTap: () =>
              setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(14)),
          child: Container(
            padding:
                const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
                color: isDone
                    ? AppColors.contentBg
                    : bg.withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.border.withOpacity(0.5)
                        : fg.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    '#${widget.order['order_number']}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDone
                            ? AppColors.textLight
                            : fg)),
              ),
              const SizedBox(width: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size: 13,
                    color: isDone
                        ? AppColors.textLight
                        : fg),
                const SizedBox(width: 4),
                Text(
                    status[0].toUpperCase() +
                        status.substring(1),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDone
                            ? AppColors.textLight
                            : fg)),
              ]),
              const Spacer(),
              if (dt != null) ...[
                const Icon(Icons.access_time_rounded,
                    size: 12, color: AppColors.textLight),
                const SizedBox(width: 4),
                Text(DateFormat('hh:mm a').format(dt),
                    style: AppText.bodySmall),
                const SizedBox(width: 8),
              ],
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textMid),
              ),
            ]),
          ),
        ),

        if (emp != null ||
            widget.order['customer_name'] != null)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                    color: widget.order['order_type'] ==
                            'parcel'
                        ? const Color(0xFF7B3FF2)
                            .withOpacity(0.1)
                        : AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(
                  widget.order['order_type'] == 'parcel'
                      ? Icons.person_outline_rounded
                      : Icons.person_rounded,
                  size: 13,
                  color: widget.order['order_type'] ==
                          'parcel'
                      ? const Color(0xFF7B3FF2)
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                  widget.order['order_type'] == 'parcel'
                      ? (widget.order['customer_name'] ??
                          'Customer')
                      : (emp?['full_name'] ?? 'Unknown'),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMid)),
              const SizedBox(width: 6),
              Text(
                  _orderType(
                      widget.order['order_type']),
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textLight)),
            ]),
          ),

        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding:
                const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: widget.items.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: AppColors.contentBg,
                        borderRadius:
                            BorderRadius.circular(10)),
                    child: const Center(
                        child: Text('Loading items...',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textLight))),
                  )
                : Column(children: [
                    const Padding(
                      padding:
                          EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Row(children: [
                        SizedBox(width: 32),
                        Expanded(
                            child: Text('ITEM',
                                style: AppText.label)),
                        SizedBox(
                            width: 40,
                            child: Text('QTY',
                                style: AppText.label,
                                textAlign:
                                    TextAlign.center)),
                        SizedBox(
                            width: 70,
                            child: Text('PRICE',
                                style: AppText.label,
                                textAlign:
                                    TextAlign.right)),
                      ]),
                    ),
                    ...widget.items.asMap().entries.map(
                        (entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      final itemDone =
                          item['status'] == 'ready' ||
                              item['status'] == 'served';
                      final lineTotal =
                          (item['item_price'] as num? ?? 0)
                                  .toDouble() *
                              (item['quantity'] as int? ??
                                  1);
                      return AnimatedContainer(
                        duration: Duration(
                            milliseconds: 150 + idx * 30),
                        margin:
                            const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                            color: itemDone
                                ? AppColors.contentBg
                                : isDone
                                    ? AppColors.contentBg
                                    : fg.withOpacity(0.04),
                            borderRadius:
                                BorderRadius.circular(9),
                            border: Border.all(
                                color: itemDone
                                    ? AppColors.green
                                        .withOpacity(0.25)
                                    : AppColors.border)),
                        child: Row(children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: itemDone
                                    ? AppColors.green
                                        .withOpacity(0.12)
                                    : fg.withOpacity(0.12),
                                borderRadius:
                                    BorderRadius.circular(7)),
                            child: itemDone
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: AppColors.green)
                                : Text(
                                    '${item['quantity']}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            FontWeight.w800,
                                        color: fg)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              Text(item['item_name'] ?? '',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.w700,
                                      fontSize: 13,
                                      color: itemDone
                                          ? AppColors.textLight
                                          : AppColors.textDark,
                                      decoration: itemDone
                                          ? TextDecoration
                                              .lineThrough
                                          : null)),
                              if ((item['notes'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(
                                          top: 2),
                                  child: Row(children: [
                                    const Icon(
                                        Icons.notes_rounded,
                                        size: 10,
                                        color:
                                            AppColors.orange),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                          item['notes']
                                              as String,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AppColors
                                                  .orange,
                                              fontWeight:
                                                  FontWeight
                                                      .w600)),
                                    ),
                                  ]),
                                ),
                            ]),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                                '×${item['quantity']}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: itemDone
                                        ? AppColors.textLight
                                        : AppColors.textMid,
                                    fontWeight:
                                        FontWeight.w600)),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text(
                                fmt.format(lineTotal),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w800,
                                    color: itemDone
                                        ? AppColors.textLight
                                        : AppColors.textDark)),
                          ),
                        ]),
                      );
                    }),
                  ]),
          ),
          secondChild: const SizedBox.shrink(),
        ),

        Padding(
          padding:
              const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(children: [
            const Divider(
                color: AppColors.divider, height: 1),
            const SizedBox(height: 10),

            if (status == 'served') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius:
                        BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00695C)
                            .withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.receipt_rounded,
                      size: 16,
                      color: Color(0xFF00695C)),
                  const SizedBox(width: 8),
                  const Text('Order Total',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00695C))),
                  const Spacer(),
                  Text(fmt.format(itemsTotal),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00695C))),
                ]),
              ),
              const SizedBox(height: 10),
            ],

            if (!isDone)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        widget.onStatusChange('cancelled'),
                    icon: const Icon(Icons.close_rounded,
                        size: 15),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.red,
                        side: BorderSide(
                            color: AppColors.red
                                .withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: widget.onNextStatus,
                    icon: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 15),
                    label: Text(
                        '→ ${_nextStatusLabel(status)}'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: fg,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(9)),
                        textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
          ]),
        ),
      ]),
    );
  }

  String _nextStatusLabel(String s) => switch (s) {
        'pending' => 'Confirm Order',
        'confirmed' => 'Start Preparing',
        'preparing' => 'Mark Ready',
        'ready' => 'Mark Served',
        _ => 'Next',
      };

  String _orderType(String? t) => switch (t) {
        'takeaway' => '🥡 Takeaway',
        'delivery' => '🛵 Delivery',
        'parcel' => '📦 Parcel',
        _ => '🍽️ Dine-in',
      };
}