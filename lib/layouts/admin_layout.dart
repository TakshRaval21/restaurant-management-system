// lib/layouts/admin_layout.dart
import 'dart:async';
import 'package:admin_side/screens/employees/employee_management_screen.dart';
import 'package:admin_side/screens/kitchen/kitchen_display.dart';
import 'package:admin_side/screens/menu/menu_categories_screen.dart';
import 'package:admin_side/screens/orders/order_screen.dart';
import 'package:admin_side/screens/qrcodes/qr_codes_screen.dart';
import 'package:admin_side/screens/restaurant/restaurant_setting_screen.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/routes.dart';
import '../core/config/app_theme.dart';

// ── Import your section screens ───────────────────────────────
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/tables/table_management_screen.dart';
import '../screens/parcel/parcel_screen.dart';
import '../screens/billing/billing_screen.dart';
import '../screens/analytics/analytics_screen.dart';

class _BP {
  static const desktop = 1100.0;
  static const tablet = 600.0;
}

class _Notif {
  final String id, title, body;
  final DateTime time;
  final IconData icon;
  final Color color;
  bool read;
  _Notif({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.icon,
    required this.color,
    this.read = false,
  });
}

class _SResult {
  final String label, subtitle;
  final int targetIndex; // ← index instead of route string
  final IconData icon;
  final Color color;
  const _SResult({
    required this.label,
    required this.subtitle,
    required this.targetIndex,
    required this.icon,
    required this.color,
  });
}

class _NavItem {
  final String label, route;
  final IconData icon;
  const _NavItem(this.label, this.icon, this.route);
}

const _navItems = [
  _NavItem('Dashboard', Icons.dashboard_outlined, AppRoutes.dashboard),
  _NavItem('Restaurant Settings', Icons.store_outlined,
      AppRoutes.restaurantSettings),
  _NavItem(
      'Tables', Icons.table_restaurant_outlined, AppRoutes.tableManagement),
  _NavItem('Menu', Icons.menu_book_outlined, AppRoutes.menuManagement),
  _NavItem('Employees', Icons.badge_outlined, AppRoutes.employees),
  _NavItem('Orders', Icons.receipt_long_outlined, AppRoutes.orders),
  _NavItem('Kitchen', Icons.soup_kitchen_outlined, AppRoutes.kitchen),
  _NavItem('Parcel Orders', Icons.inventory_2_outlined, AppRoutes.parcel),
  _NavItem('Billing', Icons.credit_card_outlined, AppRoutes.billing),
  _NavItem('QR Codes', Icons.qr_code_2_outlined, AppRoutes.qrCodes),
  _NavItem('Analytics', Icons.bar_chart_outlined, AppRoutes.analytics),
];

// ── Route → Index map (used by search & notification taps) ────
const _routeIndex = {
  AppRoutes.dashboard: 0,
  AppRoutes.restaurantSettings: 1,
  AppRoutes.tableManagement: 2,
  AppRoutes.menuManagement: 3,
  AppRoutes.employees: 4,
  AppRoutes.orders: 5,
  AppRoutes.kitchen: 6,
  AppRoutes.parcel: 7,
  AppRoutes.billing: 8,
  AppRoutes.qrCodes: 9,
  AppRoutes.analytics: 10,
};

// ── All section screens (order must match _navItems & _routeIndex) ──

// ─────────────────────────────────────────────────────────────
class AdminLayout extends StatefulWidget {
  const AdminLayout({super.key}); // ← no more currentRoute / child params
  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout> {
  final _sb = Supabase.instance.client;

  int _selectedIndex = 0; // ← drives IndexedStack

  String _restaurantName = 'My Restaurant';
  String _userName = '';
  String _userRole = 'Manager';
  String _userEmail = '';
  String? _restaurantId;
  String? _billingTableKey;
  List<Map<String, dynamic>> _billingTableOrders = [];
  Map<String, List<Map<String, dynamic>>> _billingItemsCache = {};
  String? _billingRestaurantId;

  final List<_Notif> _notifs = [];
  RealtimeChannel? _notifChannel;
  bool _showNotifs = false;
  bool _showSearch = false;
  bool _searching = false;
  List<_SResult> _results = [];

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  final _drawerKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _notifChannel = null;
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Navigate by index (no Navigator needed) ───────────────
  void _go(String route) {
    final idx = _routeIndex[route];
    if (idx == null) return;
    if (mounted) setState(() => _selectedIndex = idx);
  }

  void _goIndex(int idx) {
    if (mounted) setState(() => _selectedIndex = idx);
  }

  void _receiveBillingData({
    required String tableKey,
    required List<Map<String, dynamic>> tableOrders,
    required Map<String, List<Map<String, dynamic>>> orderItemsCache,
    required String? restaurantId,
  }) {
    setState(() {
      _billingTableKey = tableKey;
      _billingTableOrders = tableOrders;
      _billingItemsCache = orderItemsCache;
      _billingRestaurantId = restaurantId;
    });
  }

  // ✅ Clears billing data after dialog is shown — prevents re-popping on re-navigate
  void _clearBillingData() {
    if (!mounted) return;
    setState(() {
      _billingTableKey = null;
      _billingTableOrders = [];
      _billingItemsCache = {};
      _billingRestaurantId = null;
    });
  }

  // ── Load user & restaurant ────────────────────────────────
  Future<void> _loadUser() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    _userEmail = user.email ?? '';

    final r = await _sb
        .from('restaurants')
        .select('id, name')
        .eq('owner_id', user.id)
        .limit(1)
        .maybeSingle();
    final e = await _sb
        .from('employees')
        .select('full_name, role')
        .eq('user_id', user.id)
        .maybeSingle();

    if (!mounted) return;
    setState(() {
      if (r != null) {
        _restaurantName = r['name'] ?? _restaurantName;
        _restaurantId = r['id'];
      }
      if (e != null) {
        _userName = e['full_name'] ?? user.email?.split('@').first ?? 'Admin';
        _userRole = _fmtRole(e['role'] ?? 'manager');
      } else {
        _userName = user.email?.split('@').first ?? 'Admin';
      }
    });
    if (_restaurantId != null) _subscribeNotifs();
  }

  String _fmtRole(String r) =>
      const {
        'owner': 'Owner',
        'manager': 'General Manager',
        'waiter': 'Waiter',
        'chef': 'Head Chef',
        'cashier': 'Cashier',
      }[r] ??
      r;

  // ── Realtime notifications ────────────────────────────────
  void _subscribeNotifs() {
    _notifChannel = _sb.channel('notif-$_restaurantId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: _restaurantId!),
        callback: (p) async {
          if (!mounted) return;
          final o = p.newRecord;
          final tableId = o['table_id'] as String?;
          String tLabel = 'Takeaway';
          if (tableId != null) {
            final t = await _sb
                .from('tables')
                .select('table_number')
                .eq('id', tableId)
                .maybeSingle();
            if (!mounted) return;
            if (t != null) tLabel = 'Table ${t['table_number']}';
          } else if (o['order_type'] == 'parcel') {
            final customer = o['customer_name'] as String?;
            tLabel = (customer != null && customer.isNotEmpty)
                ? '📦 $customer'
                : '📦 Parcel';
          }
          if (!mounted) return;
          _addNotif(_Notif(
            id: '${DateTime.now().millisecondsSinceEpoch}',
            title: 'New Order — $tLabel',
            body:
                'Order #${o['order_number']} · ${_typeLabel(o['order_type'] ?? 'dine_in')}',
            time: DateTime.now(),
            icon: Icons.receipt_long_outlined,
            color: AppColors.primary,
          ));
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: _restaurantId!),
        callback: (p) {
          if (!mounted) return;
          final o = p.newRecord;
          final status = o['status'] as String? ?? '';
          final num = o['order_number']?.toString() ?? '—';
          if (status == 'ready') {
            _addNotif(_Notif(
                id: '${DateTime.now().millisecondsSinceEpoch}',
                title: '🍽️ Order #$num is Ready!',
                body: 'Ready to serve',
                time: DateTime.now(),
                icon: Icons.check_circle_outline,
                color: AppColors.green));
          } else if (status == 'cancelled') {
            _addNotif(_Notif(
                id: '${DateTime.now().millisecondsSinceEpoch}',
                title: '❌ Order #$num Cancelled',
                body: 'Cancelled by staff',
                time: DateTime.now(),
                icon: Icons.cancel_outlined,
                color: AppColors.red));
          }
        },
      )
      ..subscribe();
  }

  void _addNotif(_Notif n) {
    if (!mounted) return;
    setState(() => _notifs.insert(0, n));
  }

  String _typeLabel(String t) => switch (t) {
        'takeaway' => '🥡 Takeaway',
        'delivery' => '🛵 Delivery',
        'parcel' => '📦 Parcel',
        _ => '🍽️ Dine-in',
      };

  int get _unread => _notifs.where((n) => !n.read).length;

  // ── Search ────────────────────────────────────────────────
  void _onSearch() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      if (mounted)
        setState(() {
          _showSearch = false;
          _results = [];
        });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (_restaurantId == null) return;
    if (!mounted) return;
    setState(() {
      _showSearch = true;
      _searching = true;
    });
    final res = <_SResult>[];
    try {
      final num = int.tryParse(q);
      final ts = await _sb
          .from('tables')
          .select('table_number, section, status')
          .eq('restaurant_id', _restaurantId!)
          .ilike('section', '%$q%')
          .limit(3);
      for (final t in ts as List) {
        res.add(_SResult(
            label: 'Table ${t['table_number']}',
            subtitle:
                '${t['section'] ?? 'Main Hall'} · ${(t['status'] as String).toUpperCase()}',
            icon: Icons.table_restaurant_outlined,
            color: AppColors.orange,
            targetIndex: _routeIndex[AppRoutes.tableManagement]!));
      }
      if (num != null) {
        final tn = await _sb
            .from('tables')
            .select('table_number, section, status')
            .eq('restaurant_id', _restaurantId!)
            .eq('table_number', num)
            .limit(3);
        for (final t in tn as List) {
          if (!res.any((r) => r.label == 'Table ${t['table_number']}')) {
            res.add(_SResult(
                label: 'Table ${t['table_number']}',
                subtitle:
                    '${t['section'] ?? 'Main Hall'} · ${(t['status'] as String).toUpperCase()}',
                icon: Icons.table_restaurant_outlined,
                color: AppColors.orange,
                targetIndex: _routeIndex[AppRoutes.tableManagement]!));
          }
        }
        final os = await _sb
            .from('orders')
            .select('order_number, status, total_amount')
            .eq('restaurant_id', _restaurantId!)
            .eq('order_number', num)
            .limit(3);
        for (final o in os as List) {
          res.add(_SResult(
              label: 'Order #${o['order_number']}',
              subtitle:
                  '${(o['status'] as String).toUpperCase()} · \$${o['total_amount'] ?? 0}',
              icon: Icons.receipt_long_outlined,
              color: AppColors.primary,
              targetIndex: _routeIndex[AppRoutes.orders]!));
        }
      }
      final mi = await _sb
          .from('menu_items')
          .select('name, price, is_available')
          .eq('restaurant_id', _restaurantId!)
          .ilike('name', '%$q%')
          .limit(4);
      for (final m in mi as List) {
        res.add(_SResult(
            label: m['name'] as String? ?? '',
            subtitle:
                '\$${m['price']} · ${m['is_available'] == true ? 'Available' : 'Unavailable'}',
            icon: Icons.fastfood_outlined,
            color: AppColors.green,
            targetIndex: _routeIndex[AppRoutes.menuManagement]!));
      }
      final em = await _sb
          .from('employees')
          .select('full_name, role, status')
          .eq('restaurant_id', _restaurantId!)
          .ilike('full_name', '%$q%')
          .limit(3);
      for (final e in em as List) {
        res.add(_SResult(
            label: e['full_name'] as String? ?? '',
            subtitle: '${e['role']} · ${e['status']}',
            icon: Icons.badge_outlined,
            color: AppColors.purple,
            targetIndex: _routeIndex[AppRoutes.employees]!));
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
    if (!mounted) return;
    setState(() {
      _results = res;
      _searching = false;
    });
  }

  Future<void> _logout() async {
    await _sb.auth.signOut();
    if (mounted) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }
  }

  void _closeAll() {
    if (!mounted) return;
    setState(() {
      _showNotifs = false;
      _showSearch = false;
    });
    _searchFocus.unfocus();
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= _BP.desktop;
    final isTablet = width >= _BP.tablet && width < _BP.desktop;
    final isMobile = width < _BP.tablet;

    return Scaffold(
      key: _drawerKey,
      backgroundColor: AppColors.contentBg,
      drawer: isMobile
          ? Drawer(
              width: 240,
              backgroundColor: AppColors.sidebarBg,
              child: _SidebarContent(
                selectedIndex: _selectedIndex,
                expanded: true,
                restaurantName: _restaurantName,
                onNavigate: (i) {
                  Navigator.pop(context);
                  _goIndex(i);
                },
                onLogout: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
            )
          : null,
      body: GestureDetector(
        onTap: _closeAll,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // ── Main layout row ──────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isMobile)
                  _SidebarContent(
                    selectedIndex: _selectedIndex,
                    expanded: isDesktop,
                    restaurantName: _restaurantName,
                    onNavigate: _goIndex,
                    onLogout: _logout,
                  ),
                Expanded(
                  child: Column(
                    children: [
                      // ── Top bar ────────────────────────────
                      _buildTopBar(isMobile, isTablet, isDesktop),
                      // ── Screen content ─────────────────────
                      Expanded(
                        child: switch (_selectedIndex) {
                          0 => DashboardScreen(onNavigate: _goIndex),
                          1 => const RestaurantSettingsScreen(),
                          2 => TableManagementScreen(onNavigate: _goIndex),
                          3 => const MenuManagementScreen(),
                          4 => const EmployeesScreen(),
                          5 => OrdersScreen(
                              onNavigate: _goIndex,
                              onBill: _receiveBillingData),
                          6 => const KitchenDisplayScreen(),
                          7 => const ParcelScreen(),
                          8 => BillingScreen(
                              tableKey: _billingTableKey,
                              tableOrders: _billingTableOrders.isEmpty
                                  ? null
                                  : _billingTableOrders,
                              orderItemsCache: _billingItemsCache,
                              restaurantId: _billingRestaurantId,
                              onBillHandled: _clearBillingData, // ✅ clears key after dialog shown
                            ),
                          9 => const QrCodesScreen(),
                          10 => const AnalyticsScreen(),
                          _ => const SizedBox(),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Search dropdown ──────────────────────────────
            if (_showSearch)
              Positioned(
                top: 64,
                left: isMobile ? 8 : (isDesktop ? 220 + 24 : 64 + 16),
                right: isMobile ? 8 : null,
                width: isMobile ? null : 400,
                child: _SearchDropdown(
                  results: _results,
                  loading: _searching,
                  query: _searchCtrl.text,
                  onSelect: (idx) {
                    _closeAll();
                    _searchCtrl.clear();
                    _goIndex(idx);
                  },
                ),
              ),

            // ── Notification panel ───────────────────────────
            if (_showNotifs)
              Positioned(
                top: 64,
                right: 0,
                width: isMobile ? MediaQuery.of(context).size.width : 360,
                child: _NotifPanel(
                  notifs: _notifs,
                  onMarkAll: () => setState(() {
                    for (final n in _notifs) n.read = true;
                  }),
                  onDismiss: (id) =>
                      setState(() => _notifs.removeWhere((n) => n.id == id)),
                  onTap: (n) {
                    setState(() {
                      n.read = true;
                      _showNotifs = false;
                    });
                    _goIndex(_routeIndex[AppRoutes.orders]!);
                  },
                  onViewAll: () {
                    setState(() => _showNotifs = false);
                    _goIndex(_routeIndex[AppRoutes.orders]!);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────
  Widget _buildTopBar(bool isMobile, bool isTablet, bool isDesktop) {
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A';
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.topBarBg,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20),
      child: Row(children: [
  // ── Hamburger (mobile only) ──────────────────────────
  if (isMobile) ...[
    IconButton(
      icon: const Icon(Icons.menu, color: AppColors.textDark),
      onPressed: () => _drawerKey.currentState?.openDrawer(),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    ),
    const SizedBox(width: 10),
  ],

  // ── Search bar ───────────────────────────────────────
  ConstrainedBox(
    constraints: BoxConstraints(
        maxWidth: isMobile ? 220 : 360, minWidth: isMobile ? 120 : 200),
    child: Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.contentBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: _showSearch ? AppColors.primary : AppColors.border,
            width: _showSearch ? 1.5 : 1),
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        style: const TextStyle(fontSize: 13, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText:
              isMobile ? 'Search...' : 'Search orders, tables, menu...',
          hintStyle:
              const TextStyle(fontSize: 13, color: AppColors.textLight),
          prefixIcon: _searching
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                      width: 14,
                      height: 14,
                        child: Lottie.asset(
      'assets/animations/loader.json',
      width: 200,
      height: 200,
      fit: BoxFit.contain,
    ),))
              : const Icon(Icons.search,
                  size: 18, color: AppColors.textLight),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close,
                      size: 15, color: AppColors.textLight),
                  onPressed: () {
                    _searchCtrl.clear();
                    if (mounted)
                      setState(() {
                        _showSearch = false;
                        _results = [];
                      });
                    _searchFocus.unfocus();
                  })
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: false,
        ),
      ),
    ),
  ),

  // ── Spacer pushes bell + profile to far right ────────
  const Spacer(),

  // ── Notification bell ────────────────────────────────
  GestureDetector(
    onTap: () {
      if (!mounted) return;
      setState(() {
        _showNotifs = !_showNotifs;
        _showSearch = false;
        _searchFocus.unfocus();
      });
    },
    child: Stack(clipBehavior: Clip.none, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _showNotifs
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.contentBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _showNotifs ? AppColors.primary : AppColors.border),
        ),
        child: Icon(
            _showNotifs
                ? Icons.notifications
                : Icons.notifications_outlined,
            size: 18,
            color: _showNotifs ? AppColors.primary : AppColors.textMid),
      ),
      if (_unread > 0)
        Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              constraints:
                  const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: const BoxDecoration(
                  color: AppColors.red, shape: BoxShape.circle),
              child: Text(_unread > 9 ? '9+' : '$_unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
            )),
    ]),
  ),
  const SizedBox(width: 10),

  // ── Profile ──────────────────────────────────────────
  GestureDetector(
    onTap: _showProfileDialog,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isDesktop) ...[
          Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_userName.isEmpty ? 'Admin' : _userName,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis),
                Text(_userRole,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMid),
                    overflow: TextOverflow.ellipsis),
              ]),
          const SizedBox(width: 8),
        ],
        CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700))),
        if (isDesktop) ...[
          const SizedBox(width: 3),
          const Icon(Icons.expand_more,
              size: 14, color: AppColors.textMid),
        ],
      ]),
    ),
  ),
]),
    );
  }

  void _showProfileDialog() {
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A';
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(color: Colors.transparent))),
        Positioned(
          top: 68,
          right: 12,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 270,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16))),
                  child: Row(children: [
                    CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary,
                        child: Text(initial,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(_userName.isEmpty ? 'Admin' : _userName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(_userRole,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ])),
                  ]),
                ),
                const Divider(color: AppColors.divider, height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    _PRow(Icons.email_outlined, 'Email',
                        _userEmail.isEmpty ? '—' : _userEmail),
                    const SizedBox(height: 8),
                    _PRow(Icons.store_outlined, 'Restaurant', _restaurantName),
                  ]),
                ),
                const Divider(color: AppColors.divider, height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    _PAction(Icons.settings_outlined, 'Restaurant Settings',
                        () {
                      Navigator.pop(context);
                      _goIndex(_routeIndex[AppRoutes.restaurantSettings]!);
                    }),
                    const SizedBox(height: 4),
                    _PAction(Icons.logout_outlined, 'Sign out', () {
                      Navigator.pop(context);
                      _logout();
                    }, color: AppColors.red),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────
class _SidebarContent extends StatelessWidget {
  final int selectedIndex; // ← was currentRoute string
  final bool expanded;
  final String restaurantName;
  final void Function(int) onNavigate; // ← passes index now
  final VoidCallback onLogout;

  const _SidebarContent({
    required this.selectedIndex,
    required this.expanded,
    required this.restaurantName,
    required this.onNavigate,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final w = expanded ? 220.0 : 64.0;
    return Container(
      width: w,
      decoration: const BoxDecoration(color: AppColors.sidebarBg),
      child: Column(children: [
        Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: expanded
              ? Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.restaurant,
                        color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Admin Panel',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        Text('V1.0',
                            style: TextStyle(
                                color: AppColors.textSidebar.withOpacity(0.5),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5)),
                      ])),
                ])
              : Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.restaurant,
                      color: Colors.white, size: 17)),
        ),
        Container(height: 1, color: AppColors.sidebarBorder),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding:
                EdgeInsets.symmetric(horizontal: expanded ? 8 : 4, vertical: 4),
            itemCount: _navItems.length,
            itemBuilder: (_, i) => _NavTile(
              item: _navItems[i],
              isActive: selectedIndex == i, // ← compare by index
              expanded: expanded,
              onTap: () => onNavigate(i), // ← pass index
            ),
          ),
        ),
        InkWell(
          onTap: onLogout,
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
            alignment: expanded ? Alignment.centerLeft : Alignment.center,
            child: expanded
                ? Row(children: [
                    Icon(Icons.logout_outlined,
                        size: 17,
                        color: AppColors.textSidebar.withOpacity(0.6)),
                    const SizedBox(width: 9),
                    Text('Sign out',
                        style: TextStyle(
                            color: AppColors.textSidebar.withOpacity(0.6),
                            fontSize: 13)),
                  ])
                : Tooltip(
                    message: 'Sign out',
                    child: Icon(Icons.logout_outlined,
                        size: 20,
                        color: AppColors.textSidebar.withOpacity(0.6))),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Nav Tile ──────────────────────────────────────────────────
class _NavTile extends StatefulWidget {
  final _NavItem item;
  final bool isActive, expanded;
  final VoidCallback onTap;
  const _NavTile(
      {required this.item,
      required this.isActive,
      required this.expanded,
      required this.onTap});
  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(
              horizontal: widget.expanded ? 10 : 0, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.sidebarActive
                : _hovered
                    ? AppColors.sidebarHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.expanded
              ? Row(children: [
                  Icon(widget.item.icon,
                      size: 18,
                      color: active ? Colors.white : AppColors.textSidebar),
                  const SizedBox(width: 9),
                  Text(widget.item.label,
                      style: active
                          ? AppText.sidebarItemActive
                          : AppText.sidebarItem),
                ])
              : Center(
                  child: Icon(widget.item.icon,
                      size: 20,
                      color: active ? Colors.white : AppColors.textSidebar)),
        ),
      ),
    );
    if (!widget.expanded) {
      return Tooltip(
          message: widget.item.label, preferBelow: false, child: tile);
    }
    return tile;
  }
}

// ── Search Dropdown ───────────────────────────────────────────
class _SearchDropdown extends StatelessWidget {
  final List<_SResult> results;
  final bool loading;
  final String query;
  final void Function(int) onSelect; // ← index now
  const _SearchDropdown(
      {required this.results,
      required this.loading,
      required this.query,
      required this.onSelect});

  @override
  Widget build(BuildContext context) => Material(
        elevation: 14,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border)),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                       child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,  
      ),))
              : results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.search_off,
                                size: 17, color: AppColors.textLight),
                            const SizedBox(width: 8),
                            Text('No results for "$query"',
                                style: const TextStyle(
                                    color: AppColors.textLight, fontSize: 13)),
                          ]))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.divider, height: 1),
                      itemBuilder: (_, i) {
                        final r = results[i];
                        return InkWell(
                          onTap: () => onSelect(r.targetIndex),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(children: [
                              Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      color: r.color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(7)),
                                  child:
                                      Icon(r.icon, size: 15, color: r.color)),
                              const SizedBox(width: 9),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(r.label,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textDark),
                                        overflow: TextOverflow.ellipsis),
                                    Text(r.subtitle,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMid)),
                                  ])),
                              const Icon(Icons.arrow_forward_ios,
                                  size: 10, color: AppColors.textLight),
                            ]),
                          ),
                        );
                      }),
        ),
      );
}

// ── Notification Panel ────────────────────────────────────────
class _NotifPanel extends StatelessWidget {
  final List<_Notif> notifs;
  final VoidCallback onMarkAll, onViewAll;
  final void Function(String) onDismiss;
  final void Function(_Notif) onTap;
  const _NotifPanel(
      {required this.notifs,
      required this.onMarkAll,
      required this.onDismiss,
      required this.onTap,
      required this.onViewAll});
  int get _unread => notifs.where((n) => !n.read).length;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(children: [
                const Text('Notifications',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark)),
                const SizedBox(width: 7),
                if (_unread > 0)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('$_unread new',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700))),
                const Spacer(),
                if (notifs.isNotEmpty)
                  TextButton(
                    onPressed: onMarkAll,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 6)),
                    child: const Text('Mark all read',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            const Divider(color: AppColors.divider, height: 1),
            Flexible(
              child: notifs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.notifications_none_outlined,
                            size: 36, color: AppColors.textLight),
                        SizedBox(height: 8),
                        Text('No notifications yet',
                            style: TextStyle(
                                color: AppColors.textMid, fontSize: 12)),
                      ]))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: notifs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: AppColors.divider, height: 1),
                      itemBuilder: (_, i) => _NotifTile(
                          n: notifs[i],
                          onTap: () => onTap(notifs[i]),
                          onDismiss: () => onDismiss(notifs[i].id))),
            ),
            if (notifs.isNotEmpty)
              InkWell(
                onTap: onViewAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: const BoxDecoration(
                      border:
                          Border(top: BorderSide(color: AppColors.divider))),
                  child: const Center(
                      child: Text('View All Orders →',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
                ),
              ),
          ]),
        ),
      );
}

class _NotifTile extends StatelessWidget {
  final _Notif n;
  final VoidCallback onTap, onDismiss;
  const _NotifTile(
      {required this.n, required this.onTap, required this.onDismiss});
  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: n.read ? Colors.transparent : n.color.withOpacity(0.04),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: n.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(n.icon, size: 17, color: n.color)),
            const SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Expanded(
                        child: Text(n.title,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textDark,
                                fontWeight:
                                    n.read ? FontWeight.w500 : FontWeight.w700),
                            overflow: TextOverflow.ellipsis)),
                    if (!n.read)
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: n.color, shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 2),
                  Text(n.body,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMid)),
                  const SizedBox(height: 2),
                  Text(_ago(n.time),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textLight)),
                ])),
            const SizedBox(width: 6),
            GestureDetector(
                onTap: onDismiss,
                child: const Icon(Icons.close,
                    size: 13, color: AppColors.textLight)),
          ]),
        ),
      );
}

// ── Responsive helper ─────────────────────────────────────────
class Responsive {
  static bool isMobile(BuildContext ctx) => MediaQuery.of(ctx).size.width < 600;
  static bool isTablet(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 600 &&
      MediaQuery.of(ctx).size.width < 1100;
  static bool isDesktop(BuildContext ctx) =>
      MediaQuery.of(ctx).size.width >= 1100;
  static T value<T>(BuildContext ctx,
      {required T mobile, required T tablet, required T desktop}) {
    if (isDesktop(ctx)) return desktop;
    if (isTablet(ctx)) return tablet;
    return mobile;
  }

  static int gridCount(BuildContext ctx,
          {int mobile = 1, int tablet = 2, int desktop = 3}) =>
      value(ctx, mobile: mobile, tablet: tablet, desktop: desktop);
  static EdgeInsets padding(BuildContext ctx) => value(ctx,
      mobile: const EdgeInsets.all(12),
      tablet: const EdgeInsets.all(18),
      desktop: const EdgeInsets.all(24));
}

// ── Profile dialog helpers ────────────────────────────────────
class _PRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _PRow(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 14, color: AppColors.textLight),
        const SizedBox(width: 7),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMid,
                fontWeight: FontWeight.w500)),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis)),
      ]);
}

class _PAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _PAction(this.icon, this.label, this.onTap,
      {this.color = AppColors.textDark});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: color == AppColors.red
                  ? AppColors.red.withOpacity(0.05)
                  : AppColors.contentBg),
          child: Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 9),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios,
                size: 10, color: color.withOpacity(0.4)),
          ]),
        ),
      );
}