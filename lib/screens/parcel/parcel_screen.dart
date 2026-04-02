// lib/screens/parcel/parcel_screen.dart
import 'dart:async';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart'; // ✅
import '../../core/config/app_theme.dart';

class ParcelScreen extends StatefulWidget {
  const ParcelScreen({super.key});
  @override
  State<ParcelScreen> createState() => _ParcelScreenState();
}

class _ParcelScreenState extends State<ParcelScreen> {
  final _sb = Supabase.instance.client;
  // ✅ Dynamic currency symbol getter
  NumberFormat get _fmt => NumberFormat.currency(
      symbol: RestaurantService.instance.symbol, decimalDigits: 2);

  static double get _gstRate => RestaurantService.instance.taxRate / 100; // ✅ uses restaurant tax

  String? _restaurantId;
  bool _loading = true;
  bool _placing = false;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _menuItems = [];
  String? _selectedCategoryId;
  String _menuSearch = '';
  final _menuSearchCtrl = TextEditingController();

  final Map<String, _CartItem> _cart = {};

  final _customerCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _init();
    _menuSearchCtrl.addListener(() {
      setState(() => _menuSearch = _menuSearchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _menuSearchCtrl.dispose();
    _customerCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final r = await _sb
        .from('restaurants')
        .select('id')
        .eq('owner_id', user.id)
        .maybeSingle();
    if (!mounted) return;
    if (r == null) { setState(() => _loading = false); return; }
    _restaurantId = r['id'] as String;
    await Future.wait([_loadCategories(), _loadMenuItems()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCategories() async {
    final data = await _sb
        .from('menu_categories')
        .select('id, name, sort_order')
        .eq('restaurant_id', _restaurantId!)
        .order('sort_order');
    if (!mounted) return;
    setState(() => _categories = List<Map<String, dynamic>>.from(data));
  }

  Future<void> _loadMenuItems() async {
    final data = await _sb
        .from('menu_items')
        .select('id, name, price, description, category_id, image_url, is_available, tags')
        .eq('restaurant_id', _restaurantId!)
        .eq('is_available', true)
        .order('sort_order');
    if (!mounted) return;
    setState(() => _menuItems = List<Map<String, dynamic>>.from(data));
  }

  List<Map<String, dynamic>> get _filteredItems {
    return _menuItems.where((item) {
      final matchCat = _selectedCategoryId == null ||
          item['category_id'] == _selectedCategoryId;
      final matchSearch = _menuSearch.isEmpty ||
          (item['name'] as String).toLowerCase().contains(_menuSearch);
      return matchCat && matchSearch;
    }).toList();
  }

  void _addToCart(Map<String, dynamic> item) {
    final id = item['id'] as String;
    setState(() {
      if (_cart.containsKey(id)) {
        _cart[id]!.qty++;
      } else {
        _cart[id] = _CartItem(
          id: id,
          name: item['name'] as String,
          price: (item['price'] as num).toDouble(),
        );
      }
    });
  }

  void _removeFromCart(String id) {
    setState(() {
      if (_cart.containsKey(id)) {
        if (_cart[id]!.qty > 1) {
          _cart[id]!.qty--;
        } else {
          _cart.remove(id);
        }
      }
    });
  }

  void _deleteFromCart(String id) => setState(() => _cart.remove(id));

  double get _subtotal => _cart.values.fold(0.0, (s, i) => s + i.price * i.qty);
  double get _gst => double.parse((_subtotal * _gstRate).toStringAsFixed(2));
  double get _grandTotal => double.parse((_subtotal + _gst).toStringAsFixed(2));
  int get _totalItems => _cart.values.fold(0, (s, i) => s + i.qty);

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cart.isEmpty) {
      _snack('Add at least one item to the cart', isError: true);
      return;
    }
    setState(() => _placing = true);

    try {
      final lastOrder = await _sb
          .from('orders')
          .select('order_number')
          .eq('restaurant_id', _restaurantId!)
          .order('order_number', ascending: false)
          .limit(1)
          .maybeSingle();
      final nextNum = ((lastOrder?['order_number'] as int?) ?? 0) + 1;

      final order = await _sb.from('orders').insert({
        'restaurant_id': _restaurantId,
        'table_id': null,
        'order_number': nextNum,
        'status': 'pending',
        'order_type': 'parcel',
        'customer_name': _customerCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'subtotal': _subtotal,
        'tax_amount': _gst,
        'total_amount': _grandTotal,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single();

      final orderId = order['id'] as String;

      final items = _cart.values.map((i) => {
        'order_id': orderId,
        'item_name': i.name,
        'item_price': i.price,
        'quantity': i.qty,
        'status': 'pending',
      }).toList();

      await _sb.from('order_items').insert(items);

      if (!mounted) return;
      _snack('✓ Parcel order #$nextNum placed for ${_customerCtrl.text.trim()}!');

      setState(() {
        _cart.clear();
        _customerCtrl.clear();
        _notesCtrl.clear();
      });
    } catch (e) {
      if (mounted) _snack('Failed to place order: $e', isError: true);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.red : const Color(0xFF004D40),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
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
      : isMobile
          ? _buildMobileLayout()
          : _buildDesktopLayout();
}

  Widget _buildDesktopLayout() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(flex: 3, child: _buildMenuPanel()),
      const VerticalDivider(color: AppColors.divider, width: 1),
      SizedBox(width: 380, child: _buildCartPanel()),
    ],
  );

  Widget _buildMobileLayout() => Column(
    children: [
      Expanded(child: _buildMenuPanel()),
      if (_cart.isNotEmpty)
        _buildCartSummaryBar(),
    ],
  );

  Widget _buildMenuPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        color: AppColors.cardBg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1E6B60).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  color: Color(0xFF1E6B60), size: 19),
            ),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New Parcel Order', style: AppText.h1),
              Text('Select items from menu', style: AppText.body),
            ]),
          ]),
          const SizedBox(height: 14),
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _menuSearchCtrl,
              style: const TextStyle(fontSize: 13, color: AppColors.textDark),
              decoration: InputDecoration(
                hintText: 'Search menu items...',
                hintStyle: const TextStyle(fontSize: 13, color: AppColors.textLight),
                prefixIcon: const Icon(Icons.search, size: 17, color: AppColors.textLight),
                suffixIcon: _menuSearch.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14, color: AppColors.textLight),
                        onPressed: () { _menuSearchCtrl.clear(); setState(() => _menuSearch = ''); })
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ]),
      ),
      if (_categories.isNotEmpty)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _CategoryChip('All', null),
              ..._categories.map((c) => _CategoryChip(c['name'] as String, c['id'] as String)),
            ]),
          ),
        ),
      const Divider(color: AppColors.divider, height: 1),
      Expanded(
        child: _filteredItems.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.search_off, size: 36, color: AppColors.textLight),
                  const SizedBox(height: 10),
                  Text('No items found', style: AppText.body),
                ]),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: _filteredItems.length,
                itemBuilder: (_, i) => _MenuItemCard(
                  item: _filteredItems[i],
                  qty: _cart[_filteredItems[i]['id']]?.qty ?? 0,
                  fmt: _fmt, // ✅ passes dynamic fmt
                  onAdd: () => _addToCart(_filteredItems[i]),
                  onRemove: () => _removeFromCart(_filteredItems[i]['id'] as String),
                ),
              ),
      ),
    ],
  );

  Widget _CategoryChip(String label, String? id) {
    final active = _selectedCategoryId == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryId = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E6B60) : const Color(0xFFF5F4F0),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : const Color(0xFF6B7B7A),
        )),
      ),
    );
  }

  Widget _buildCartPanel() => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          color: AppColors.cardBg,
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF1E6B60).withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.shopping_cart_outlined,
                  color: Color(0xFF1E6B60), size: 17),
            ),
            const SizedBox(width: 10),
            const Text('Order Cart', style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const Spacer(),
            if (_cart.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E6B60),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_totalItems items',
                  style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        const Divider(color: AppColors.divider, height: 1),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Customer Name *', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _customerCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 14, color: AppColors.textDark),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter customer name' : null,
                decoration: InputDecoration(
                  hintText: 'e.g. Rahul Sharma',
                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textLight),
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      size: 18, color: AppColors.textMid),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1E6B60), width: 1.8)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.red)),
                ),
              ),
              const SizedBox(height: 16),

              const Text('Order Notes (optional)', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'e.g. Extra spicy, no onion...',
                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textLight),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF1E6B60), width: 1.8)),
                ),
              ),
              const SizedBox(height: 20),

              if (_cart.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Column(children: [
                    Icon(Icons.add_shopping_cart_outlined,
                        size: 36, color: AppColors.textLight.withOpacity(0.5)),
                    const SizedBox(height: 10),
                    const Text('No items added yet',
                        style: TextStyle(fontSize: 13, color: AppColors.textLight)),
                    const SizedBox(height: 4),
                    const Text('Tap + on any menu item',
                        style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                  ])),
                )
              else ...[
                const Text('Items', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(height: 10),
                ..._cart.values.map((item) => _CartItemRow(
                  item: item,
                  fmt: _fmt, // ✅ dynamic
                  onAdd: () => setState(() => item.qty++),
                  onRemove: () => _removeFromCart(item.id),
                  onDelete: () => _deleteFromCart(item.id),
                )),
                const SizedBox(height: 16),

                // ✅ Totals use dynamic symbol + dynamic tax rate label
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E6B60).withOpacity(0.15)),
                  ),
                  child: Column(children: [
                    _TotalRow('Subtotal', _fmt.format(_subtotal)),
                    const SizedBox(height: 6),
                    // ✅ Dynamic tax rate label
                    _TotalRow(
                      'Tax (${RestaurantService.instance.taxRate.toStringAsFixed(0)}%)',
                      _fmt.format(_gst),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: Color(0xFFE0D5FF)),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('GRAND TOTAL', style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppColors.textDark)),
                      Text(_fmt.format(_grandTotal), style: const TextStyle( // ✅
                        fontSize: 20, fontWeight: FontWeight.w900,
                        color: Color(0xFF1E6B60))),
                    ]),
                  ]),
                ),
              ],
            ]),
          ),
        ),

        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider))),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_placing || _cart.isEmpty) ? null : _placeOrder,
              icon: _placing
                  ? SizedBox(width: 16, height: 16,
                        child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_placing
                  ? 'Placing Order...'
                  : _cart.isEmpty
                      ? 'Add items to order'
                      // ✅ dynamic symbol in button text
                      : 'Place Parcel Order · ${_fmt.format(_grandTotal)}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E6B60),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF1E6B60).withOpacity(0.4),
                disabledForegroundColor: Colors.white60,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildCartSummaryBar() => GestureDetector(
    onTap: () => _showMobileCartSheet(),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E6B60),
        boxShadow: [BoxShadow(
          color: const Color(0xFF1E6B60).withOpacity(0.3),
          blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$_totalItems', style: const TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        const Text('View Cart & Place Order', style: TextStyle(
          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(_fmt.format(_grandTotal), style: const TextStyle( // ✅
          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
      ]),
    ),
  );

  void _showMobileCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _buildCartPanel(),
        ),
      ),
    );
  }
}

// ─── Cart Item Model ──────────────────────────────────────────
class _CartItem {
  final String id, name;
  final double price;
  int qty;
  _CartItem({required this.id, required this.name, required this.price, this.qty = 1});
}

// ─── Menu Item Card ───────────────────────────────────────────
class _MenuItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int qty;
  final NumberFormat fmt;
  final VoidCallback onAdd, onRemove;

  const _MenuItemCard({
    required this.item, required this.qty, required this.fmt,
    required this.onAdd, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final inCart = qty > 0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inCart ? const Color(0xFF1E6B60).withOpacity(0.4) : AppColors.border,
          width: inCart ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(
          color: inCart ? const Color(0xFF1E6B60).withOpacity(0.08) : AppColors.shadow,
          blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 80,
          decoration: BoxDecoration(
            color: inCart ? const Color(0xFF1E6B60).withOpacity(0.06) : const Color(0xFFF5F4F0),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: item['image_url'] != null
              ? ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  child: Image.network(item['image_url'] as String,
                      fit: BoxFit.cover, width: double.infinity,
                      errorBuilder: (_, __, ___) => _placeholder(inCart)),
                )
              : _placeholder(inCart),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['name'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700,
                    color: AppColors.textDark)),
            const SizedBox(height: 4),
            // ✅ Dynamic currency symbol
            Text(fmt.format((item['price'] as num).toDouble()),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: Color(0xFF1E6B60))),
            const SizedBox(height: 8),
            if (qty == 0)
              SizedBox(
                width: double.infinity,
                height: 30,
                child: ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B60),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              Row(children: [
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E6B60).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.remove, size: 14, color: Color(0xFF1E6B60)),
                  ),
                ),
                Expanded(child: Center(child: Text('$qty',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                        color: Color(0xFF1E6B60))))),
                GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E6B60),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.add, size: 14, color: Colors.white),
                  ),
                ),
              ]),
          ]),
        ),
      ]),
    );
  }

  Widget _placeholder(bool inCart) => Center(
    child: Icon(Icons.fastfood_outlined, size: 28,
        color: inCart ? const Color(0xFF1E6B60).withOpacity(0.3) : AppColors.textLight.withOpacity(0.3)),
  );
}

// ─── Cart Item Row ────────────────────────────────────────────
class _CartItemRow extends StatelessWidget {
  final _CartItem item;
  final NumberFormat fmt;
  final VoidCallback onAdd, onRemove, onDelete;

  const _CartItemRow({
    required this.item, required this.fmt,
    required this.onAdd, required this.onRemove, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(children: [
      Container(
        width: 26, height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E6B60).withOpacity(0.1),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text('${item.qty}', style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E6B60))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark),
            overflow: TextOverflow.ellipsis),
        Text(fmt.format(item.price), style: const TextStyle( // ✅
            fontSize: 11, color: AppColors.textMid)),
      ])),
      Text(fmt.format(item.price * item.qty), style: const TextStyle( // ✅
          fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      const SizedBox(width: 6),
      Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: onRemove,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: AppColors.contentBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.remove, size: 12, color: AppColors.textMid),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF1E6B60).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.add, size: 12, color: Color(0xFF1E6B60)),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onDelete,
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: AppColors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.delete_outline, size: 13, color: AppColors.red.withOpacity(0.7)),
          ),
        ),
      ]),
    ]),
  );
}

// ─── Total Row ────────────────────────────────────────────────
class _TotalRow extends StatelessWidget {
  final String label, value;
  const _TotalRow(this.label, this.value);
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(
            fontSize: 13, color: AppColors.textMid, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(
            fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w600)),
      ]);
}