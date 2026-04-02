// lib/screens/kitchen/kitchen_display_screen.dart
import 'dart:async';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart';
import '../../core/config/app_theme.dart';


class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});
  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _orders = [];
  String? _restaurantId;
  bool _loading = true;
  bool _realtimeConnected = false;
  bool _disposed = false;
  RealtimeChannel? _channel;
  Timer? _timer;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.unsubscribe();
    _channel = null;
    _timer?.cancel();
    _timer = null;
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  Future<void> _init() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final r = await _sb.from('restaurants').select('id')
        .eq('owner_id', user.id).maybeSingle();
    if (_disposed || !mounted) return;
    if (r == null) { _safeSetState(() => _loading = false); return; }
    _restaurantId = r['id'] as String;
    await _load();
    if (_disposed || !mounted) return;
    _subscribeRealtime();
    // ── FIX: rebuild every second so elapsed timers tick live ──
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _safeSetState(() {});
    });
  }

  void _subscribeRealtime() {
    _channel = _sb.channel('kitchen-live-$_restaurantId')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: _restaurantId!,
          ),
          callback: (payload) {
            if (_disposed || !mounted) return;
            final event = payload.eventType;
            if (event == PostgresChangeEvent.delete) {
              final oldId = payload.oldRecord['id'] as String?;
              if (oldId != null) {
                _safeSetState(() => _orders.removeWhere((o) => o['id'] == oldId));
              }
            } else {
              _load();
            }
          })
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (payload) {
            if (_disposed || !mounted) return;
            _load();
          })
      ..subscribe((status, [error]) {
  debugPrint('Kitchen realtime status: $status error: $error'); // ← add this
  if (_disposed || !mounted) return;
  _safeSetState(() =>
      _realtimeConnected = status == RealtimeSubscribeStatus.subscribed);
});
  }

  Future<void> _load() async {
    if (_disposed || _restaurantId == null) return;
    final data = await _sb
        .from('orders')
        .select('*, order_items(*), tables(table_number, section)')
        .eq('restaurant_id', _restaurantId!)
        .inFilter('status', ['pending', 'confirmed', 'preparing'])
        .order('created_at');
    if (_disposed || !mounted) return;
    _safeSetState(() {
      _orders = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  Future<void> _updateOrderStatus(String id, String status) async {
    await _sb.from('orders').update({'status': status}).eq('id', id);
    if (_disposed || !mounted) return;
    if (status == 'ready') {
      _safeSetState(() => _orders.removeWhere((o) => o['id'] == id));
    }
  }

  Future<void> _updateItemStatus(String itemId, String status) async {
    await _sb.from('order_items').update({'status': status}).eq('id', itemId);
    if (_disposed || !mounted) return;
    await _load();
  }

DateTime? _parseUtc(String? raw) {
  if (raw == null) return null;
  
  DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  if (!parsed.isUtc) {
    parsed = DateTime.utc(
      parsed.year, parsed.month, parsed.day,
      parsed.hour, parsed.minute, parsed.second, parsed.millisecond,
    );
  }

  return parsed.toLocal();
}

  String _elapsed(String? createdAt) {
    final dt = _parseUtc(createdAt);
    if (dt == null) return '0m';
    final diff = DateTime.now().difference(dt);
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ${diff.inSeconds.remainder(60)}s';
    return '${diff.inSeconds}s';
  }

  Color _elapsedColor(String? createdAt) {
    final dt = _parseUtc(createdAt);
    if (dt == null) return AppColors.green;
    final mins = DateTime.now().difference(dt).inMinutes;
    if (mins > 20) return AppColors.red;
    if (mins > 10) return AppColors.orange;
    return AppColors.green;
  }

  @override
Widget build(BuildContext context) {
  final isMobile = Responsive.isMobile(context);
  // ← No AdminLayout wrapper
  return _loading
      ? Center(  child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
      : Column(children: [
          // ── Header ──
          Container(
            color: AppColors.sidebarBg,
            // ... everything inside child: stays exactly the same
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 24, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.soup_kitchen_outlined,
                        color: AppColors.primary, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                      child: Text('Kitchen Display',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: isMobile ? 15 : 18),
                          overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.15))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                              color: AppColors.green, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text('${_orders.length} Active',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (_realtimeConnected
                                ? AppColors.green
                                : AppColors.red)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: (_realtimeConnected
                                    ? AppColors.green
                                    : AppColors.red)
                                .withOpacity(0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Opacity(
                          opacity:
                              _realtimeConnected ? _pulseAnim.value : 1.0,
                          child: Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                  color: _realtimeConnected
                                      ? AppColors.green
                                      : AppColors.red,
                                  shape: BoxShape.circle)),
                        ),
                        const SizedBox(width: 5),
                        Text(_realtimeConnected ? 'LIVE' : 'OFFLINE',
                            style: TextStyle(
                                color: _realtimeConnected
                                    ? AppColors.green
                                    : AppColors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  if (!isMobile)
                    const Row(children: [
                      _LegendDot(AppColors.green, '<10m'),
                      SizedBox(width: 10),
                      _LegendDot(AppColors.orange, '10-20m'),
                      SizedBox(width: 10),
                      _LegendDot(AppColors.red, '>20m'),
                    ]),
                ]),
              ),

              // ── Orders grid ──────────────────────────────────
              Expanded(
                child: _orders.isEmpty
                    ? _buildEmpty()
                    : GridView.builder(
                        padding: const EdgeInsets.all(14),
                        gridDelegate:
                            SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isMobile ? 600 : 380,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: isMobile ? 1.3 : 0.82,
                        ),
                        itemCount: _orders.length,
                        itemBuilder: (_, i) => _KitchenCard(
                          order: _orders[i],
                          elapsed: _elapsed(_orders[i]['created_at']),
                          elapsedColor:
                              _elapsedColor(_orders[i]['created_at']),
                          onMarkReady: () =>
                              _updateOrderStatus(_orders[i]['id'], 'ready'),
                          onMarkPreparing: () => _updateOrderStatus(
                              _orders[i]['id'], 'preparing'),
                          onItemDone: (itemId) =>
                              _updateItemStatus(itemId, 'ready'),
                        ),
                      ),
              ),
            ]
    );
  }

  Widget _buildEmpty() =>
      Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline,
                size: 44, color: AppColors.green)),
        const SizedBox(height: 16),
        const Text('All caught up!', style: AppText.h2),
        const SizedBox(height: 6),
        const Text('New orders appear here in real-time', style: AppText.body),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: _pulseAnim.value,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                      color: AppColors.green, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              const Text('Listening for new orders...',
                  style: TextStyle(fontSize: 12, color: AppColors.textMid)),
            ]),
          ),
        ),
      ]));
}

class _LegendDot extends StatelessWidget {
  final Color color; final String label;
  const _LegendDot(this.color, this.label);
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.75), fontSize: 11)),
      ]);
}

class _KitchenCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String elapsed;
  final Color elapsedColor;
  final VoidCallback onMarkReady, onMarkPreparing;
  final void Function(String) onItemDone;

  const _KitchenCard({
    required this.order, required this.elapsed,
    required this.elapsedColor, required this.onMarkReady,
    required this.onMarkPreparing, required this.onItemDone,
  });

  // ── handles parcel orders with customer name ──
  String _tableLabel(Map<String, dynamic> order, Map? table) {
    final orderType = order['order_type'] as String? ?? 'dine_in';
    if (orderType == 'parcel') {
      final customerName = order['customer_name'] as String?;
      return customerName != null && customerName.isNotEmpty
          ? '📦 $customerName'
          : '📦 Parcel';
    }
    return table != null ? 'Table ${table['table_number']}' : 'Takeaway';
  }

  @override
  Widget build(BuildContext context) {
    final table  = order['tables'] as Map?;
    final status = order['status'] as String? ?? 'pending';
    final items  = List<Map<String, dynamic>>.from(order['order_items'] ?? []);
    final isParcel = order['order_type'] == 'parcel';

    items.sort((a, b) {
      final aDone = (a['status'] == 'ready' || a['status'] == 'served') ? 1 : 0;
      final bDone = (b['status'] == 'ready' || b['status'] == 'served') ? 1 : 0;
      return aDone.compareTo(bDone);
    });

    final doneCount    = items.where((i) => i['status'] == 'ready' || i['status'] == 'served').length;
    final pendingCount = items.length - doneCount;
    final allDone      = pendingCount == 0 && items.isNotEmpty;
    final progress     = items.isEmpty ? 0.0 : doneCount / items.length;

    final (statusColor, statusBg, statusLabel, statusIcon) = switch (status) {
      'preparing' => (AppColors.orange, AppColors.statusOccupBg, 'Preparing', Icons.soup_kitchen_outlined),
      'confirmed' => (AppColors.primary, AppColors.primary.withOpacity(0.08), 'Confirmed', Icons.check_outlined),
      _ => (AppColors.textMid, AppColors.contentBg, 'Pending', Icons.hourglass_empty_outlined),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: elapsedColor.withOpacity(0.35), width: 1.5),
        boxShadow: [BoxShadow(
            color: elapsedColor.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(children: [

        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
              color: elapsedColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Order #${order['order_number']}',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 15, color: AppColors.textDark)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: elapsedColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Icon(Icons.timer_outlined, size: 12, color: elapsedColor),
                  const SizedBox(width: 4),
                  Text(elapsed, style: TextStyle(
                      color: elapsedColor, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isParcel
                        ? const Color(0xFF7B3FF2).withOpacity(0.3)
                        : AppColors.border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isParcel
                        ? Icons.inventory_2_outlined
                        : Icons.table_restaurant_outlined,
                    size: 12,
                    color: isParcel
                        ? const Color(0xFF7B3FF2)
                        : AppColors.textMid,
                  ),
                  const SizedBox(width: 5),
                  Text(_tableLabel(order, table),
                      style: TextStyle(fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isParcel
                              ? const Color(0xFF7B3FF2)
                              : AppColors.textDark)),
                  if (table != null && table['section'] != null) ...[
                    const SizedBox(width: 4),
                    Text('· ${table['section']}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMid)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: statusBg, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(statusIcon, size: 11, color: statusColor),
                  const SizedBox(width: 4),
                  Text(statusLabel, style: TextStyle(
                      color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ]),
        ),

        // Progress bar
        LinearProgressIndicator(
          value: progress,
          minHeight: 3,
          backgroundColor: AppColors.divider,
          color: allDone ? AppColors.green : elapsedColor,
        ),

        // Summary row
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Row(children: [
            Text('${items.length} item${items.length != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(width: 6),
            if (doneCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.statusAvailBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$doneCount done',
                    style: const TextStyle(fontSize: 9.5,
                        fontWeight: FontWeight.w700, color: AppColors.green)),
              ),
            if (pendingCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.orangeBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$pendingCount pending',
                    style: const TextStyle(fontSize: 9.5,
                        fontWeight: FontWeight.w700, color: AppColors.orange)),
              ),
            ],
          ]),
        ),

        const Divider(color: AppColors.divider, height: 1),

        // Items list
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item  = items[i];
            final done  = item['status'] == 'ready' || item['status'] == 'served';
            final notes = item['notes'] as String?;
            return GestureDetector(
              onTap: done ? null : () => onItemDone(item['id'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: done ? AppColors.statusAvailBg : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: done
                          ? AppColors.green.withOpacity(0.3)
                          : AppColors.border),
                ),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? AppColors.green : Colors.transparent,
                        border: Border.all(
                            color: done ? AppColors.green : AppColors.border,
                            width: 2)),
                    child: done
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 24, height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.green.withOpacity(0.15)
                              : AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${item['quantity']}',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800,
                                color: done ? AppColors.green : AppColors.primary)),
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: Text(item['item_name'] ?? '',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: done ? AppColors.textLight : AppColors.textDark,
                              decoration: done ? TextDecoration.lineThrough : null))),
                    ]),
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        const SizedBox(width: 31),
                        const Icon(Icons.note_outlined,
                            size: 11, color: AppColors.orange),
                        const SizedBox(width: 4),
                        Expanded(child: Text(notes,
                            style: const TextStyle(fontSize: 11,
                                color: AppColors.orange,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                  ])),
                  Text(
    (item['total_price'] != null)
      ? RestaurantService.instance.formatPrice(
          (item['total_price'] as num).toDouble())
     : '',
    
  
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: done ? AppColors.textLight : AppColors.textMid)),
                ]),
              ),
            );
          },
        )),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: status == 'confirmed'
              ? SizedBox(width: double.infinity, height: 38,
                  child: ElevatedButton.icon(
                    onPressed: onMarkPreparing,
                    icon: const Icon(Icons.soup_kitchen_outlined, size: 15),
                    label: const Text('Start Preparing',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white, elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ))
              : SizedBox(width: double.infinity, height: 38,
                  child: ElevatedButton.icon(
                    onPressed: onMarkReady,
                    icon: const Icon(Icons.check_circle_outline, size: 15),
                    label: const Text('Mark Ready',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white, elevation: 0,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  )),
        ),
      ]),
    );
  }
}