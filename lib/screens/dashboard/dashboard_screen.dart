import 'dart:async';
import 'dart:math' as math;
import 'package:admin_side/core/config/routes.dart';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart'; // ✅
import '../../core/config/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _sb = Supabase.instance.client;
  int _ordersToday = 0;
  double _revenueToday = 0;
  int _activeTables = 0;
  int _totalTables = 0;
  int _kitchenOrders = 0;
  List<double> _weeklyRevenue = List.filled(7, 0);
  double _weeklyTotal = 0;
  List<int> _weeklyOrders = List.filled(7, 0);
  int _ordersTotal = 0;
  List<Map<String, dynamic>> _liveTables = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
    super.dispose();
  }

  Future<void> _load() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final restaurant = await _sb
        .from('restaurants')
        .select('id')
        .eq('owner_id', user.id)
        .limit(1)
        .maybeSingle();
    if (restaurant == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final rid = restaurant['id'] as String;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr =
        DateTime(weekStart.year, weekStart.month, weekStart.day)
            .toIso8601String();
    final results = await Future.wait([
      _sb
          .from('orders')
          .select('id, total_amount, status')
          .eq('restaurant_id', rid)
          .gte('created_at', todayStart),
      _sb
          .from('tables')
          .select(
              'id, table_number, seats, status, section, guest_name, duration_text, current_total, reservation_time')
          .eq('restaurant_id', rid)
          .order('table_number'),
      _sb
          .from('orders')
          .select('created_at, total_amount, status')
          .eq('restaurant_id', rid)
          .gte('created_at', weekStartStr),
    ]);
    final todayOrders = results[0] as List;
    _ordersToday = todayOrders.length;
    _revenueToday = todayOrders.fold(
        0.0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));
    _kitchenOrders = todayOrders
        .where((o) => o['status'] == 'preparing' || o['status'] == 'confirmed')
        .length;
    final tables = results[1] as List<dynamic>;
    _liveTables = List<Map<String, dynamic>>.from(tables);
    _activeTables = _liveTables.where((t) => t['status'] == 'occupied').length;
    _totalTables = _liveTables.length;
    final weekOrders = results[2] as List;
    final revenue = List<double>.filled(7, 0);
    final orders = List<int>.filled(7, 0);
    for (final o in weekOrders) {
      final d = DateTime.parse(o['created_at'] as String).toLocal();
      final idx = d.weekday - 1;
      if (idx >= 0 && idx < 7) {
        revenue[idx] += (o['total_amount'] as num?)?.toDouble() ?? 0;
        orders[idx] += 1;
      }
    }
    _weeklyRevenue = revenue;
    _weeklyOrders = orders;
    _weeklyTotal = revenue.fold(0, (a, b) => a + b);
    _ordersTotal = orders.fold(0, (a, b) => a + b);
    if (mounted) setState(() => _loading = false);
  }

  void _subscribeRealtime() {
    _channel = _sb.channel('dashboard-live')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (mounted) _load();
          })
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tables',
          callback: (_) {
            if (mounted) _load();
          })
      ..subscribe();
  }

  // build() — remove AdminLayout wrapper
@override
Widget build(BuildContext context) {
  final pad = Responsive.padding(context);
  return _loading
      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
      : SingleChildScrollView(
          padding: pad,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatCards(context),
                const SizedBox(height: 20),
                _buildChartsRow(context),
                const SizedBox(height: 20),
                _buildLiveTables(context),
              ]),
        );
}

  Widget _buildStatCards(BuildContext context) {
    // ✅ Dynamic currency symbol from RestaurantService
    final fmt = NumberFormat.currency(
        symbol: RestaurantService.instance.symbol, decimalDigits: 2);
    final isMobile = Responsive.isMobile(context);
    return LayoutBuilder(builder: (ctx, constraints) {
      final cols = isMobile ? 2 : 4;
      const spacing = 12.0;
      final cardW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      final cards = [
        _StatCard(
            icon: Icons.receipt_long_outlined,
            iconBg: AppColors.primary.withOpacity(0.1),
            iconColor: AppColors.primary,
            label: 'Total Orders Today',
            value: _ordersToday.toString(),
            badge: '+12%',
            badgeColor: AppColors.green,
            badgeBg: AppColors.greenBg),
        _StatCard(
            icon: Icons.currency_rupee_sharp,
            iconBg: AppColors.primaryLight.withOpacity(0.1),
            iconColor: AppColors.primaryLight,
            label: 'Total Revenue Today',
            value: fmt.format(_revenueToday), // ✅ dynamic symbol
            badge: '+8.5%',
            badgeColor: AppColors.green,
            badgeBg: AppColors.greenBg),
        _StatCard(
            icon: Icons.table_restaurant_outlined,
            iconBg: AppColors.orange.withOpacity(0.1),
            iconColor: AppColors.orange,
            label: 'Active Tables',
            value: '$_activeTables / $_totalTables',
            badge: 'Busy',
            badgeColor: AppColors.orange,
            badgeBg: AppColors.orangeBg),
        _StatCard(
            icon: Icons.soup_kitchen_outlined,
            iconBg: AppColors.red.withOpacity(0.1),
            iconColor: AppColors.red,
            label: 'Kitchen Orders',
            value: _kitchenOrders.toString(),
            badge: 'High',
            badgeColor: AppColors.red,
            badgeBg: AppColors.redBg),
      ];
      return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: cardW.clamp(130.0, 360.0), child: c))
              .toList());
    });
  }

  Widget _buildChartsRow(BuildContext context) {
    // ✅ Dynamic currency symbol from RestaurantService
    final fmt = NumberFormat.currency(
        symbol: RestaurantService.instance.symbol, decimalDigits: 0);
    final isMobile = Responsive.isMobile(context);
    final r = _ChartCard(
        title: 'Daily Revenue',
        subtitle: 'Weekly revenue overview',
        value: fmt.format(_weeklyTotal), // ✅ dynamic symbol
        trend: '+15% from last week',
        trendPositive: true,
        chart: _LineChart(values: _weeklyRevenue));
    final o = _ChartCard(
        title: 'Orders per Day',
        subtitle: 'Peak hour analytics',
        value: _ordersTotal.toString(),
        trend: '-3% from yesterday',
        trendPositive: false,
        chart:
            _BarChart(values: _weeklyOrders.map((e) => e.toDouble()).toList()));
    if (isMobile) return Column(children: [r, const SizedBox(height: 14), o]);
    return Row(children: [
      Expanded(child: r),
      const SizedBox(width: 16),
      Expanded(child: o)
    ]);
  }

  Widget _buildLiveTables(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text('Live Table Status',
                style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark),
                overflow: TextOverflow.ellipsis)),
        TextButton(
          onPressed: () => {},
          child: Text(isMobile ? 'Manage →' : 'Manage Floor Map →',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ),
      ]),
      const SizedBox(height: 12),
      _liveTables.isEmpty
          ? const Center(
              child: Column(children: [
              Icon(Icons.inbox_outlined,
                  size: 48, color: AppColors.textLight),
              SizedBox(height: 8),
              Text('No tables found', style: AppText.h4),
              Text('Add tables in Tables Management', style: AppText.body),
            ]))
          : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isMobile ? 260 : 280,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.18,
              ),
              itemCount: _liveTables.length,
              itemBuilder: (_, i) => _LiveTableCard(
                data: _liveTables[i],
                onAction: () => Navigator.pushReplacementNamed(
                    context, AppRoutes.tableManagement),
              ),
            ),
    ]);
  }
}

// ─── Stat Card ────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor, badgeColor, badgeBg;
  final String label, value, badge;
  const _StatCard(
      {required this.icon,
      required this.iconBg,
      required this.iconColor,
      required this.label,
      required this.value,
      required this.badge,
      required this.badgeColor,
      required this.badgeBg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
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
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: iconBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 20)),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: badgeBg, borderRadius: BorderRadius.circular(20)),
                child: Text(badge,
                    style: TextStyle(
                        color: badgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 12),
          Text(label,
              style: AppText.bodySmall, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      letterSpacing: -0.5))),
        ]),
      );
}

// ─── Chart Card ───────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title, subtitle, value, trend;
  final bool trendPositive;
  final Widget chart;
  const _ChartCard(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.trend,
      required this.trendPositive,
      required this.chart});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
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
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark),
                          overflow: TextOverflow.ellipsis),
                      Text(subtitle, style: AppText.bodySmall)
                    ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark)),
                  Text(trend,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color:
                              trendPositive ? AppColors.green : AppColors.red)),
                ]),
              ]),
          const SizedBox(height: 16),
          SizedBox(height: 120, child: chart),
          const SizedBox(height: 10),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
                  .map((d) => Text(d, style: AppText.label))
                  .toList()),
        ]),
      );
}

// ─── Charts ───────────────────────────────────────────────────
class _LineChart extends StatelessWidget {
  final List<double> values;
  const _LineChart({required this.values});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LCP(values), child: const SizedBox.expand());
}

class _LCP extends CustomPainter {
  final List<double> v;
  _LCP(this.v);
  @override
  void paint(Canvas c, Size s) {
    if (v.isEmpty) return;
    final maxV = v.reduce(math.max).clamp(1.0, double.infinity);
    final pts = <Offset>[
      for (int i = 0; i < v.length; i++)
        Offset(s.width * i / (v.length - 1),
            s.height - (v[i] / maxV) * s.height * 0.85)
    ];
    final fill = Path()..moveTo(pts.first.dx, s.height);
    for (final p in pts) {
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(pts.last.dx, s.height)
      ..close();
    c.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary.withOpacity(0.25),
                AppColors.primary.withOpacity(0.01)
              ]).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));
    final lp = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cp1 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i - 1].dy);
      final cp2 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i].dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i].dx, pts[i].dy);
    }
    c.drawPath(path, lp);
    for (final p in pts) {
      c.drawCircle(p, 3.5, Paint()..color = AppColors.primary);
      c.drawCircle(
          p,
          3.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_LCP o) => o.v != v;
}

class _BarChart extends StatelessWidget {
  final List<double> values;
  const _BarChart({required this.values});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BCP(values), child: const SizedBox.expand());
}

class _BCP extends CustomPainter {
  final List<double> v;
  _BCP(this.v);
  @override
  void paint(Canvas c, Size s) {
    if (v.isEmpty) return;
    final maxV = v.reduce(math.max).clamp(1.0, double.infinity);
    final today = DateTime.now().weekday - 1;
    final barW = (s.width / v.length) * 0.55;
    final gap = s.width / v.length;
    for (int i = 0; i < v.length; i++) {
      final barH = (v[i] / maxV) * s.height * 0.85;
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(
                  gap * i + (gap - barW) / 2, s.height - barH, barW, barH),
              const Radius.circular(5)),
          Paint()
            ..color = i == today ? AppColors.primary : const Color(0xFFDDE8E6));
    }
  }

  @override
  bool shouldRepaint(_BCP o) => o.v != v;
}

// ─────────────────────────────────────────────────────────────
//  Live Table Card
// ─────────────────────────────────────────────────────────────
class _LiveTableCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onAction;
  const _LiveTableCard({required this.data, required this.onAction});
  @override
  State<_LiveTableCard> createState() => _LiveTableCardState();
}

class _LiveTableCardState extends State<_LiveTableCard> {
  bool _hovered = false;
  String get _status => widget.data['status'] as String? ?? 'available';

  (Color, Color, Color, String) get _cfg => switch (_status) {
        'occupied' => (
            AppColors.statusOccupied,
            AppColors.statusOccupBg,
            AppColors.statusOccupied,
            'OCCUPIED'
          ),
        'reserved' => (
            AppColors.statusReserved,
            AppColors.statusResBg,
            AppColors.statusReserved,
            'RESERVED'
          ),
        'preparing' => (
            AppColors.statusPreparing,
            AppColors.statusPrepBg,
            AppColors.statusPreparing,
            'PREPARING'
          ),
        _ => (
            AppColors.statusAvailable,
            AppColors.statusAvailBg,
            AppColors.statusAvailable,
            'AVAILABLE'
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (accent, badgeBg, badgeFg, badgeLabel) = _cfg;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _hovered ? accent.withOpacity(0.5) : AppColors.border,
              width: _hovered ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: _hovered ? accent.withOpacity(0.12) : AppColors.shadow,
                blurRadius: _hovered ? 14 : 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(13)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            (widget.data['section'] ?? 'Main Hall')
                                .toString()
                                .toUpperCase(),
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textLight,
                                letterSpacing: 0.6),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: accent, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text(badgeLabel,
                                style: TextStyle(
                                    color: badgeFg,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 5),
                      Text('Table ${widget.data['table_number']}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark)),
                      Row(children: [
                        const Icon(Icons.people_alt_outlined,
                            size: 11, color: AppColors.textLight),
                        const SizedBox(width: 3),
                        Text('${widget.data['seats'] ?? 4} Seats',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textLight)),
                      ]),
                      const SizedBox(height: 10),
                      const Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 10),
                      Expanded(child: _buildMiddle(accent)),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 32,
                        child: _status == 'occupied'
                            ? ElevatedButton.icon(
                                onPressed: widget.onAction,
                                icon: const Icon(Icons.receipt_long_outlined,
                                    size: 13),
                                label: const Text('View Order',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))),
                              )
                            : _status == 'reserved'
                                ? OutlinedButton.icon(
                                    onPressed: widget.onAction,
                                    icon: const Icon(Icons.event_seat_outlined,
                                        size: 13,
                                        color: AppColors.statusReserved),
                                    label: const Text('Reserved',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            AppColors.statusReserved,
                                        side: BorderSide(
                                            color: AppColors.statusReserved
                                                .withOpacity(0.4)),
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8))),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: widget.onAction,
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 13,
                                        color: AppColors.statusAvailable),
                                    label: const Text('Assign',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            AppColors.statusAvailable,
                                        side: BorderSide(
                                            color: AppColors.statusAvailable
                                                .withOpacity(0.4)),
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8))),
                                  ),
                      ),
                    ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildMiddle(Color accent) {
    switch (_status) {
      case 'occupied':
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.statusOccupBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE0B2))),
            child: Row(children: [
              const Icon(Icons.timer_outlined,
                  size: 13, color: AppColors.statusOccupied),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(widget.data['duration_text'] ?? 'Active',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.statusOccupied),
                      overflow: TextOverflow.ellipsis)),
              // ✅ Dynamic currency symbol for table current total
              if (widget.data['current_total'] != null)
                Text(
                  RestaurantService.instance.formatPrice(
                      (widget.data['current_total'] as num).toDouble(),
                      decimalDigits: 0),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark),
                ),
            ]),
          ),
          if (widget.data['guest_name'] != null) ...[
            const SizedBox(height: 7),
            Row(children: [
              const CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person, size: 11, color: Colors.white)),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(widget.data['guest_name'] ?? '',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark),
                      overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]);

      case 'reserved':
        final hex = widget.data['avatar_color_hex'] as String? ?? '26A69A';
        final avatarColor = Color(int.parse('FF$hex', radix: 16));
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            CircleAvatar(
                radius: 14,
                backgroundColor: avatarColor,
                child: Text(widget.data['avatar_initials'] ?? '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.data['guest_name'] ?? '—',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark),
                      overflow: TextOverflow.ellipsis),
                  if (widget.data['reservation_time'] != null)
                    Row(children: [
                      const Icon(Icons.access_time_outlined,
                          size: 11, color: AppColors.textLight),
                      const SizedBox(width: 3),
                      Text(widget.data['reservation_time'] ?? '',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textMid)),
                    ]),
                ])),
          ]),
        ]);

      case 'preparing':
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.statusPrepBg,
                borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              const Row(children: [
                Icon(Icons.cleaning_services_outlined,
                    size: 13, color: AppColors.statusPreparing),
                SizedBox(width: 6),
                Text('Cleaning in progress',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.statusPreparing)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                      value: 0.6,
                      backgroundColor: Colors.white,
                      color: AppColors.statusPreparing,
                      minHeight: 4)),
            ]),
          ),
        ]);

      default:
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.statusAvailBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.statusAvailable.withOpacity(0.2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_outline,
                  size: 14, color: AppColors.statusAvailable.withOpacity(0.8)),
              const SizedBox(width: 6),
              Text('Ready · ${widget.data['seats'] ?? 4} seats',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.statusAvailable.withOpacity(0.9))),
            ]),
          ),
        ]);
    }
  }
}