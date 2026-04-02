import 'dart:math' as math;
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart'; // ✅
import '../../core/config/app_theme.dart';


class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _sb = Supabase.instance.client;

  // ✅ Dynamic currency symbol — getter so it always reads latest value
  NumberFormat get _fmt => NumberFormat.currency(
      symbol: RestaurantService.instance.symbol, decimalDigits: 2);

  String? _restaurantId;
  bool _loading = true;
  String _period = '7d';
  double _totalRevenue = 0;
  int _totalOrders = 0;
  double _avgOrderValue = 0;
  List<double> _revenueData = List.filled(7, 0);
  List<int> _ordersData = List.filled(7, 0);
  List<String> _chartLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  List<Map<String, dynamic>> _topItems = [];
  Map<String, double> _paymentBreakdown = {};
  static const _periods = {'7d': '7 Days', '30d': '30 Days', '90d': '90 Days'};

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
    setState(() => _loading = true);
    final days = _period == '7d'
        ? 7
        : _period == '30d'
            ? 30
            : 90;
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));
    final fromStr = DateTime(from.year, from.month, from.day).toIso8601String();
    final results = await Future.wait([
      _sb
          .from('orders')
          .select('created_at, total_amount, status')
          .eq('restaurant_id', _restaurantId!)
          .gte('created_at', fromStr)
          .neq('status', 'cancelled'),
      _sb
          .from('order_items')
          .select('item_name, quantity, item_price, orders(created_at, status)')
          .eq('orders.restaurant_id', _restaurantId!)
          .gte('orders.created_at', fromStr),
      _sb
          .from('payments')
          .select('amount_paid, payment_method')
          .eq('restaurant_id', _restaurantId!)
          .eq('status', 'completed')
          .gte('paid_at', fromStr),
    ]);
    final orders = results[0] as List;
    final oItems = results[1] as List;
    final payments = results[2] as List;
    double totalRev = 0;
    final revenueByDay = <String, double>{};
    final ordersByDay = <String, int>{};
    final labels = <String>[];
    for (int i = days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      labels.add(days <= 7
          ? DateFormat('EEE').format(d)
          : DateFormat('MM/dd').format(d));
      revenueByDay[key] = 0;
      ordersByDay[key] = 0;
    }
    for (final o in orders) {
      final dt = DateTime.tryParse(o['created_at'] as String)?.toLocal();
      if (dt == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(dt);
      totalRev += (o['total_amount'] as num?)?.toDouble() ?? 0;
      revenueByDay[key] = (revenueByDay[key] ?? 0) +
          ((o['total_amount'] as num?)?.toDouble() ?? 0);
      ordersByDay[key] = (ordersByDay[key] ?? 0) + 1;
    }
    final revValues = revenueByDay.values.toList();
    final ordValues = ordersByDay.values.toList();
    final displayRev = revValues.length > 7
        ? revValues.sublist(revValues.length - 7)
        : revValues;
    final displayOrd = ordValues.length > 7
        ? ordValues.sublist(ordValues.length - 7)
        : ordValues;
    final displayLab =
        labels.length > 7 ? labels.sublist(labels.length - 7) : labels;
    final itemMap = <String, _ItemStat>{};
    for (final item in oItems) {
      final name = item['item_name'] as String? ?? 'Unknown';
      final qty = item['quantity'] as int? ?? 0;
      final rev = ((item['item_price'] as num?)?.toDouble() ?? 0) * qty;
      itemMap[name] = itemMap[name] == null
          ? _ItemStat(name, qty, rev)
          : _ItemStat(
              name, itemMap[name]!.qty + qty, itemMap[name]!.revenue + rev);
    }
    final topItems = itemMap.values.toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));
    final breakdown = <String, double>{};
    for (final p in payments) {
      final m = p['payment_method'] as String? ?? 'cash';
      breakdown[m] =
          (breakdown[m] ?? 0) + ((p['amount_paid'] as num?)?.toDouble() ?? 0);
    }
    if (!mounted) return;
    setState(() {
      _totalRevenue = totalRev;
      _totalOrders = orders.length;
      _avgOrderValue = orders.isEmpty ? 0 : totalRev / orders.length;
      _revenueData = displayRev.map((v) => v).toList();
      _ordersData = displayOrd.map((v) => v).toList();
      _chartLabels = displayLab;
      _topItems = topItems
          .take(5)
          .map((e) => {'name': e.name, 'qty': e.qty, 'revenue': e.revenue})
          .toList();
      _paymentBreakdown = breakdown;
      _loading = false;
    });
  }

 @override
Widget build(BuildContext context) {
  final isMobile = Responsive.isMobile(context);
  // ← No AdminLayout wrapper, return content directly
  return _loading
      ? Center(  child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
      : SingleChildScrollView(
          padding: Responsive.padding(context),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Analytics', style: AppText.h1),
                          const Text('Revenue and performance insights', style: AppText.body),
                          const SizedBox(height: 12),
                          _periodSelector(),
                        ])
                    : Row(children: [
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Analytics', style: AppText.h1),
                              Text('Revenue and performance insights', style: AppText.body)
                            ]),
                        const Spacer(),
                        _periodSelector(),
                      ]),
                const SizedBox(height: 20),
                LayoutBuilder(builder: (ctx, constraints) {
                  final cols = isMobile ? 2 : 4;
                  const spacing = 12.0;
                  final cardW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
                  return Wrap(spacing: spacing, runSpacing: spacing, children: [
                    SizedBox(width: cardW.clamp(120.0, 300.0),
                        child: _KpiCard(icon: Icons.currency_rupee_sharp, color: AppColors.primary, label: 'Total Revenue', value: _fmt.format(_totalRevenue))),
                    SizedBox(width: cardW.clamp(120.0, 300.0),
                        child: _KpiCard(icon: Icons.receipt_long_outlined, color: AppColors.orange, label: 'Total Orders', value: '$_totalOrders')),
                    SizedBox(width: cardW.clamp(120.0, 300.0),
                        child: _KpiCard(icon: Icons.trending_up_outlined, color: AppColors.green, label: 'Avg. Order Value', value: _fmt.format(_avgOrderValue))),
                    SizedBox(width: cardW.clamp(120.0, 300.0),
                        child: _KpiCard(icon: Icons.star_outline, color: AppColors.purple, label: 'Top Day Revenue',
                            value: _revenueData.isEmpty ? '${RestaurantService.instance.symbol}0' : _fmt.format(_revenueData.reduce(math.max)))),
                  ]);
                }),
                const SizedBox(height: 20),
                isMobile
                    ? Column(children: [_buildRevenueChart(), const SizedBox(height: 14), _buildOrdersChart()])
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 3, child: _buildRevenueChart()),
                        const SizedBox(width: 14),
                        Expanded(flex: 2, child: _buildOrdersChart())
                      ]),
                const SizedBox(height: 18),
                isMobile
                    ? Column(children: [_buildTopItems(), const SizedBox(height: 14), _buildPaymentBreakdown()])
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: _buildTopItems()),
                        const SizedBox(width: 14),
                        Expanded(child: _buildPaymentBreakdown())
                      ]),
              ]),
        );
}

  Widget _periodSelector() => Container(
        decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _periods.entries.map((e) {
              final selected = _period == e.key;
              return GestureDetector(
                  onTap: () {
                    setState(() => _period = e.key);
                    _load();
                  },
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color:
                              selected ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(9)),
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppColors.textMid))));
            }).toList()),
      );

  Widget _buildRevenueChart() => _ChartPanel(
      title: 'Revenue Trend',
      child: SizedBox(
          height: 180,
          child: Column(children: [
            Expanded(
                child: CustomPaint(
                    painter: _LineP(_revenueData),
                    child: const SizedBox.expand())),
            const SizedBox(height: 8),
            _DayLabels(labels: _chartLabels)
          ])));

  Widget _buildOrdersChart() => _ChartPanel(
      title: 'Orders per Day',
      child: SizedBox(
          height: 180,
          child: Column(children: [
            Expanded(
                child: CustomPaint(
                    painter:
                        _BarP(_ordersData.map((e) => e.toDouble()).toList()),
                    child: const SizedBox.expand())),
            const SizedBox(height: 8),
            _DayLabels(labels: _chartLabels)
          ])));

  Widget _buildTopItems() => _ChartPanel(
      title: 'Top Selling Items',
      child: _topItems.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No data yet', style: AppText.body)))
          : Column(
              children: _topItems.asMap().entries.map((e) {
              final rank = e.key + 1;
              final item = e.value;
              final total =
                  _topItems.fold<int>(0, (s, i) => s + (i['qty'] as int));
              final pct = total > 0 ? (item['qty'] as int) / total : 0.0;
              return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle),
                        child: Center(
                            child: Text('$rank',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    color: AppColors.primary)))),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(item['name'] as String,
                              style: AppText.h4,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          LinearProgressIndicator(
                              value: pct,
                              color: AppColors.primary,
                              backgroundColor: AppColors.contentBg,
                              borderRadius: BorderRadius.circular(4),
                              minHeight: 5)
                        ])),
                    const SizedBox(width: 10),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${item['qty']}x',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: AppColors.textDark)),
                          Text(_fmt.format(item['revenue']), // ✅
                              style: AppText.bodySmall)
                        ]),
                  ]));
            }).toList()));

  Widget _buildPaymentBreakdown() => _ChartPanel(
      title: 'Payment Methods',
      child: _paymentBreakdown.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No data yet', style: AppText.body)))
          : Column(
              children: _paymentBreakdown.entries.map((e) {
              const methodColors = {
                'cash': AppColors.green,
                'card': Color(0xFF1565C0),
                'upi': AppColors.purple,
                'online': AppColors.primary,
                'split': AppColors.orange
              };
              final total =
                  _paymentBreakdown.values.fold<double>(0, (s, v) => s + v);
              final pct = total > 0 ? e.value / total : 0.0;
              final clr = methodColors[e.key] ?? AppColors.primary;
              return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Container(
                        width: 9,
                        height: 9,
                        decoration:
                            BoxDecoration(color: clr, shape: BoxShape.circle)),
                    const SizedBox(width: 9),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${e.key[0].toUpperCase()}${e.key.substring(1)}',
                              style: AppText.h4),
                          const SizedBox(height: 3),
                          LinearProgressIndicator(
                              value: pct,
                              color: clr,
                              backgroundColor: AppColors.contentBg,
                              borderRadius: BorderRadius.circular(4),
                              minHeight: 5)
                        ])),
                    const SizedBox(width: 10),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_fmt.format(e.value), // ✅
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: AppColors.textDark)),
                          Text('${(pct * 100).toStringAsFixed(1)}%',
                              style: AppText.bodySmall)
                        ]),
                  ]));
            }).toList()));
}

class _ItemStat {
  final String name;
  final int qty;
  final double revenue;
  _ItemStat(this.name, this.qty, this.revenue);
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _KpiCard(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 19)),
          const SizedBox(height: 10),
          Text(label,
              style: AppText.bodySmall, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.textDark,
                      letterSpacing: -0.5))),
        ]),
      );
}

class _ChartPanel extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartPanel({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppText.h3),
          const SizedBox(height: 14),
          child
        ]),
      );
}

class _DayLabels extends StatelessWidget {
  final List<String> labels;
  const _DayLabels({required this.labels});
  @override
  Widget build(BuildContext context) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((l) => Text(l, style: AppText.label)).toList());
}

class _LineP extends CustomPainter {
  final List<double> v;
  _LineP(this.v);
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
                AppColors.primary.withOpacity(0.22),
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
  bool shouldRepaint(_LineP o) => o.v != v;
}

class _BarP extends CustomPainter {
  final List<double> v;
  _BarP(this.v);
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
  bool shouldRepaint(_BarP o) => o.v != v;
}