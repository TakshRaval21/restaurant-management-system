// lib/screens/tables/table_management_screen.dart
import 'package:admin_side/core/config/routes.dart';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_theme.dart';

class TableManagementScreen extends StatefulWidget {
  const TableManagementScreen({super.key});
  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _tables = [];
  String _restaurantId = '';
  bool _loading = true;
  late TabController _tabCtrl;
  int _tab = 0;

  int get _availableCount =>
      _tables.where((t) => t['status'] == 'available').length;
  int get _occupiedCount =>
      _tables.where((t) => t['status'] == 'occupied').length;
  int get _reservedCount =>
      _tables.where((t) => t['status'] == 'reserved').length;

  List<Map<String, dynamic>> get _filtered {
    switch (_tab) {
      case 1:
        return _tables.where((t) => t['status'] == 'available').toList();
      case 2:
        return _tables.where((t) => t['status'] == 'occupied').toList();
      case 3:
        return _tables.where((t) => t['status'] == 'reserved').toList();
      default:
        return _tables;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabCtrl.indexIsChanging) setState(() => _tab = _tabCtrl.index);
      });
    _init();
  }

  Future<void> _init() async {
    await _loadRestaurant();
    if (_restaurantId.isNotEmpty) {
      await _loadTables();
      _subscribeRealtime();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRestaurant() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final row = await _sb
        .from('restaurants')
        .select('id')
        .eq('owner_id', user.id)
        .maybeSingle();
    if (row != null) _restaurantId = row['id'] as String;
  }

  Future<void> _loadTables() async {
    if (_restaurantId.isEmpty) return;
    final data = await _sb
        .from('tables')
        .select()
        .eq('restaurant_id', _restaurantId)
        .order('table_number');
    if (mounted) {
      setState(() => _tables = List<Map<String, dynamic>>.from(data));
    }
  }

  void _subscribeRealtime() {
    _channel = _sb
        .channel('tables-live-$_restaurantId')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tables',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'restaurant_id',
                value: _restaurantId),
            callback: (_) {
              if (mounted) _loadTables();
            })
        .subscribe();
  }

  Future<void> _selectTime(BuildContext context, TextEditingController controller) async {
  final TimeOfDay? picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF006769), // Your Emerald Teal
            onPrimary: Colors.white,
            onSurface: AppColors.textDark,
          ),
        ),
        child: child!,
      );
    },
  );

  if (picked != null) {
    // Format the time to a 24-hour or 12-hour string for the controller
    if (mounted) {
      final formattedTime = picked.format(context); // e.g., "7:30 PM"
      controller.text = formattedTime;
    }
  }
}

  @override
  void dispose() {
    _channel?.unsubscribe();
      _channel = null;
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  final isMobile = Responsive.isMobile(context);
  final pad = Responsive.padding(context);
  // ← No AdminLayout wrapper, return content directly
  return _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Header ────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(pad.left, 20, pad.right, 0),
                child: isMobile
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
                                        const Text('Tables', style: AppText.h1),
                                        Text(
                                            '${_tables.length} tables on floor',
                                            style: AppText.body),
                                      ]),
                                  _AddTableButton(
                                      small: true, onTap: _showAddDialog),
                                ]),
                          ])
                    : Row(children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Table Management', style: AppText.h1),
                              Text(
                                  'Real-time floor layout · ${_tables.length} tables',
                                  style: AppText.body),
                            ]),
                        const Spacer(),
                        _AddTableButton(onTap: _showAddDialog),
                      ]),
              ),

              // ── Stats row ─────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(pad.left, 14, pad.right, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  _StatChip('${_tables.length}', 'Total', AppColors.primary,
                      AppColors.primary.withOpacity(0.09)),
                  _StatChip('$_availableCount', 'Available',
                      AppColors.statusAvailable, AppColors.statusAvailBg),
                  _StatChip('$_occupiedCount', 'Occupied',
                      AppColors.statusOccupied, AppColors.statusOccupBg),
                  _StatChip('$_reservedCount', 'Reserved',
                      AppColors.statusReserved, AppColors.statusResBg),
                ]),
              ),

              // ── Tab bar ───────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: 14),
                decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: AppColors.divider))),
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textMid,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                  indicator: const UnderlineTabIndicator(
                      borderSide:
                          BorderSide(width: 2.5, color: AppColors.primary)),
                  indicatorSize: TabBarIndicatorSize.tab,
                  padding: EdgeInsets.symmetric(horizontal: pad.left),
                  tabs: [
                    Tab(text: 'All (${_tables.length})'),
                    Tab(text: 'Available ($_availableCount)'),
                    Tab(text: 'Occupied ($_occupiedCount)'),
                    Tab(text: 'Reserved ($_reservedCount)'),
                  ],
                ),
              ),

              // ── Grid ──────────────────────────────────────
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(pad.left, 16, pad.right, 24),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isMobile ? 180 : 260,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: isMobile ? 0.75 : 0.78,
                  ),
                  itemCount: _filtered.length + 1,
                  itemBuilder: (_, i) {
                    if (i == _filtered.length) {
                      return _AddCard(onTap: _showAddDialog);
                    }
                    final t = _filtered[i];
                    return _TableCard(
                      data: t,
                      onEdit: () => _showEditDialog(t),
                      onDelete: () => _confirmDelete(t['id'] as String),
                      onViewOrder: () => _showOrderDialog(t),
                      onQrCode: () => _showQrDialog(t),
                      onStatusChange: (s) =>
                          _updateStatus(t['id'] as String, s),
                    );
                  },
                ),
              ),
          ]
    );
  }

  // ── Add Table Dialog ──────────────────────────────────────
  void _showAddDialog() {
    final numCtrl = TextEditingController();
    final seatsCtrl = TextEditingController(text: '4');
    String section = 'Main Hall';
    final formKey = GlobalKey<FormState>();
    const sections = ['Main Hall', 'Outdoor', 'VIP', 'Bar', 'Terrace'];

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setDlg) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Container(
                    width: 400,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                          border: const Border(
                              bottom: BorderSide(color: AppColors.divider)),
                        ),
                        child: Row(children: [
                          Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.table_restaurant_outlined,
                                  color: Colors.white, size: 20)),
                          const SizedBox(width: 12),
                          const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Add New Table',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textDark)),
                                Text('Configure table details',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMid)),
                              ]),
                          const Spacer(),
                          GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      color: AppColors.contentBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: AppColors.border)),
                                  child: const Icon(Icons.close,
                                      size: 15, color: AppColors.textMid))),
                        ]),
                      ),

                      // Body
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                            key: formKey,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Table Number
                                  const _ThemedLabel('Table Number'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: numCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textDark,
                                        fontWeight: FontWeight.w600),
                                    decoration: _themedDeco(
                                        'e.g. 12', Icons.tag_outlined),
                                  ),
                                  const SizedBox(height: 16),

                                  // Seats
                                  const _ThemedLabel('Number of Seats'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: seatsCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textDark,
                                        fontWeight: FontWeight.w600),
                                    decoration: _themedDeco(
                                        'e.g. 4', Icons.people_alt_outlined),
                                  ),
                                  const SizedBox(height: 16),

                                  // Section
                                  const _ThemedLabel('Section'),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: section,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textDark,
                                        fontWeight: FontWeight.w600),
                                    decoration: _themedDeco(
                                        '', Icons.grid_view_outlined),
                                    items: sections
                                        .map((s) => DropdownMenuItem(
                                            value: s, child: Text(s)))
                                        .toList(),
                                    onChanged: (v) =>
                                        setDlg(() => section = v ?? section),
                                  ),
                                ])),
                      ),

                      // Footer buttons
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                        child: Row(children: [
                          Expanded(
                              child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textMid,
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13)),
                            child: const Text('Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13)),
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              final number = int.parse(numCtrl.text);
                              final existing = await _sb
                                  .from('tables')
                                  .select('id')
                                  .eq('restaurant_id', _restaurantId)
                                  .eq('table_number', number);
                              if (existing.isNotEmpty) {
                                _snack('Table $number already exists',
                                    isError: true);
                                return;
                              }
                              final row = await _sb
                                  .from('tables')
                                  .insert({
                                    'restaurant_id': _restaurantId,
                                    'table_number': number,
                                    'seats': int.parse(seatsCtrl.text),
                                    'section': section,
                                    'status': 'available',
                                  })
                                  .select()
                                  .single();
                              setState(() => _tables.add(row));
                              if (mounted) Navigator.pop(ctx);
                              _snack('Table $number added!');
                            },
                            child: const Text('Add Table',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          )),
                        ]),
                      ),
                    ]),
                  ),
                )));
  }

  // ── Edit Dialog ───────────────────────────────────────────
  void _showEditDialog(Map<String, dynamic> t) {
    final seatsCtrl = TextEditingController(text: t['seats'].toString());
    final durationCtrl = TextEditingController(text: t['duration_text'] ?? '');
    final totalCtrl =
        TextEditingController(text: t['current_total']?.toString() ?? '');
    final guestCtrl = TextEditingController(text: t['guest_name'] ?? '');
    final timeCtrl = TextEditingController(text: t['reservation_time'] ?? '');
    final phoneCtrl = TextEditingController(text: t['guest_phone'] ?? '');
    String status = t['status'] as String;

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setDlg) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Container(
                    width: 420,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                          border: const Border(
                              bottom: BorderSide(color: AppColors.divider)),
                        ),
                        child: Row(children: [
                          Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.edit_outlined,
                                  color: AppColors.primary, size: 19)),
                          const SizedBox(width: 12),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Edit Table ${t['table_number']}',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textDark)),
                                Text(
                                    '${t['section'] ?? 'Main Hall'} · ${t['seats']} seats',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMid)),
                              ]),
                          const Spacer(),
                          GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      color: AppColors.contentBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: AppColors.border)),
                                  child: const Icon(Icons.close,
                                      size: 15, color: AppColors.textMid))),
                        ]),
                      ),

                      // Body
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              // Seats
                              const _ThemedLabel('Seats'),
                              const SizedBox(height: 6),
                              TextFormField(
                                  controller: seatsCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textDark,
                                      fontWeight: FontWeight.w600),
                                  decoration: _themedDeco('Number of seats',
                                      Icons.people_alt_outlined)),
                              const SizedBox(height: 18),

                              // Status selector
                              const _ThemedLabel('Table Status'),
                              const SizedBox(height: 10),
                              Row(
                                  children: [
                                'available',
                                'occupied',
                                'reserved'
                              ].map((s) {
                                final (color, bg) = switch (s) {
                                  'occupied' => (
                                      AppColors.statusOccupied,
                                      AppColors.statusOccupBg
                                    ),
                                  'reserved' => (
                                      AppColors.statusReserved,
                                      AppColors.statusResBg
                                    ),
                                  _ => (
                                      AppColors.statusAvailable,
                                      AppColors.statusAvailBg
                                    ),
                                };
                                final isSelected = status == s;
                                return Expanded(
                                    child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () => setDlg(() => status = s),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? color : bg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: isSelected
                                                ? color
                                                : color.withOpacity(0.3),
                                            width: isSelected ? 2 : 1),
                                      ),
                                      child: Column(children: [
                                        Icon(_statusIcon(s),
                                            size: 18,
                                            color: isSelected
                                                ? Colors.white
                                                : color),
                                        const SizedBox(height: 4),
                                        Text(
                                            s[0].toUpperCase() + s.substring(1),
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected
                                                    ? Colors.white
                                                    : color)),
                                      ]),
                                    ),
                                  ),
                                ));
                              }).toList()),

                              // Occupied extras
                              if (status == 'occupied') ...[
                                const SizedBox(height: 18),
                                const _ThemedLabel('Duration'),
                                const SizedBox(height: 6),
                                TextFormField(
                                    controller: durationCtrl,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textDark),
                                    decoration: _themedDeco(
                                        'e.g. 45 mins', Icons.timer_outlined)),
                                const SizedBox(height: 12),
                                const _ThemedLabel('Current Total (\$)'),
                                const SizedBox(height: 6),
                                TextFormField(
                                    controller: totalCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textDark),
                                    decoration: _themedDeco(
                                        '0.00', Icons.attach_money_outlined)),
                              ],

                              // Reserved extras
                              if (status == 'reserved') ...[
  const SizedBox(height: 18),
  const _ThemedLabel('Guest Name'),
  const SizedBox(height: 6),
  TextFormField(
    controller: guestCtrl,
    style: const TextStyle(fontSize: 14, color: AppColors.textDark),
    decoration: _themedDeco('Full name', Icons.person_outline),
  ),
  const SizedBox(height: 12),
  Row(children: [
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ThemedLabel('Reservation Time'),
          const SizedBox(height: 6),
          TextFormField(
            controller: timeCtrl,
            readOnly: true, // Prevents keyboard from opening
            onTap: () => _selectTime(context, timeCtrl), // Opens the dialog
            style: const TextStyle(fontSize: 14, color: AppColors.textDark),
            decoration: _themedDeco(
              'Select Time', 
              Icons.calendar_today_outlined // Changed icon to suggest a picker
            ))])),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        const _ThemedLabel('Phone'),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                            controller: phoneCtrl,
                                            keyboardType: TextInputType.phone,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: AppColors.textDark),
                                            decoration: _themedDeco(
                                                '+1 555 0000',
                                                Icons.phone_outlined)),
                                      ])),
                                ]),
                              ],
                            ])),
                      ),

                      // Footer
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Row(children: [
                          Expanded(
                              child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textMid,
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13)),
                            child: const Text('Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13)),
                            onPressed: () async {
                              final initials = _initials(guestCtrl.text);
                              final colorHex = _randomColorHex(guestCtrl.text);
                              final payload = {
                                'seats': int.tryParse(seatsCtrl.text) ?? 4,
                                'status': status,
                                'duration_text': status == 'occupied'
                                    ? durationCtrl.text
                                    : null,
                                'current_total': status == 'occupied'
                                    ? double.tryParse(totalCtrl.text)
                                    : null,
                                'guest_name': status == 'reserved'
                                    ? guestCtrl.text
                                    : null,
                                'reservation_time':
                                    status == 'reserved' ? timeCtrl.text : null,
                                'guest_phone': status == 'reserved'
                                    ? phoneCtrl.text
                                    : null,
                                'avatar_initials':
                                    status == 'reserved' ? initials : null,
                                'avatar_color_hex':
                                    status == 'reserved' ? colorHex : null,
                              };
                              await _sb
                                  .from('tables')
                                  .update(payload)
                                  .eq('id', t['id']);
                              final idx =
                                  _tables.indexWhere((e) => e['id'] == t['id']);
                              if (idx != -1) {
                                setState(() => _tables[idx] = {
                                      ..._tables[idx],
                                      ...payload
                                    });
                              }
                              if (mounted) Navigator.pop(ctx);
                              _snack('Table updated!');
                            },
                            child: const Text('Save Changes',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          )),
                        ]),
                      ),
                    ]),
                  ),
                )));
  }

  IconData _statusIcon(String s) => switch (s) {
        'occupied' => Icons.people_alt_outlined,
        'reserved' => Icons.event_seat_outlined,
        _ => Icons.check_circle_outline
      };

  void _confirmDelete(String id) {
    final t = _tables.firstWhere((e) => e['id'] == id);
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Container(
                width: 360,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(18)),
                        border: Border(
                            bottom: BorderSide(color: Color(0xFFFFE0E0)))),
                    child: Row(children: [
                      Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.red.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.delete_outline,
                              color: AppColors.red, size: 20)),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Delete Table',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark)),
                            Text(
                                'Table ${t['table_number']} · ${t['section'] ?? 'Main Hall'}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMid)),
                          ]),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      const Text(
                          'Are you sure you want to delete this table? This action cannot be undone and will also remove all associated QR codes.',
                          style: TextStyle(
                              fontSize: 13.5,
                              color: AppColors.textMid,
                              height: 1.5)),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textMid,
                                    side: const BorderSide(
                                        color: AppColors.border),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13)),
                                child: const Text('Cancel',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600)))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: ElevatedButton(
                          onPressed: () async {
                            await _sb.from('tables').delete().eq('id', id);
                            setState(() =>
                                _tables.removeWhere((e) => e['id'] == id));
                            if (mounted) Navigator.pop(context);
                            _snack('Table deleted');
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13)),
                          child: const Text('Delete',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        )),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ));
  }

  void _showOrderDialog(Map<String, dynamic> t) {
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Container(
                width: 360,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18)),
                        border: const Border(
                            bottom: BorderSide(color: AppColors.divider))),
                    child: Row(children: [
                      Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.receipt_long_outlined,
                              color: Colors.white, size: 20)),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Table ${t['table_number']} Order',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark)),
                            Text(t['section'] ?? 'Main Hall',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMid)),
                          ]),
                      const Spacer(),
                      GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                  color: AppColors.contentBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border)),
                              child: const Icon(Icons.close,
                                  size: 15, color: AppColors.textMid))),
                    ]),
                  ),
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        _OrderInfoRow(
                            Icons.timer_outlined,
                            'Duration',
                            t['duration_text'] ?? '—',
                            AppColors.statusOccupied),
                        const SizedBox(height: 12),
                        _OrderInfoRow(
                            Icons.currency_rupee_sharp,
                            'Current Total',
                            t['current_total'] != null
                                ? '\$${t['current_total']}'
                                : '—',
                            AppColors.primary),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textMid,
                                      side: const BorderSide(
                                          color: AppColors.border),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12)),
                                  child: const Text('Close'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushReplacementNamed(
                                  context, AppRoutes.orders);
                            },
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 15),
                            label: const Text('View Orders'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12)),
                          )),
                        ]),
                      ])),
                ]),
              ),
            ));
  }

  void _showQrDialog(Map<String, dynamic> t) {
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Container(
                width: 360,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18)),
                        border: const Border(
                            bottom: BorderSide(color: AppColors.divider))),
                    child: Row(children: [
                      Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.qr_code_2_outlined,
                              color: Colors.white, size: 20)),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('QR Code — Table ${t['table_number']}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textDark)),
                            Text(t['section'] ?? 'Main Hall',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textMid)),
                          ]),
                      const Spacer(),
                      GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                  color: AppColors.contentBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border)),
                              child: const Icon(Icons.close,
                                  size: 15, color: AppColors.textMid))),
                    ]),
                  ),
                  Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: AppColors.primary, width: 3),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.primary.withOpacity(0.1),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4))
                              ]),
                          child: const Center(
                              child: Icon(Icons.qr_code_2,
                                  size: 130, color: AppColors.textDark)),
                        ),
                        const SizedBox(height: 14),
                        Text(
                            'Table ${t['table_number']} · ${t['section'] ?? 'Main Hall'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textDark)),
                        const SizedBox(height: 4),
                        const Text('Scan to view menu & place order',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textMid)),
                        const SizedBox(height: 6),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: AppColors.contentBg,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text(
                                'Add qr_flutter package for real QR',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.textLight))),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.textMid,
                                      side: const BorderSide(
                                          color: AppColors.border),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12)),
                                  child: const Text('Close'))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushReplacementNamed(
                                  context, AppRoutes.qrCodes);
                            },
                            icon: const Icon(Icons.qr_code_outlined, size: 15),
                            label: const Text('Manage QRs'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12)),
                          )),
                        ]),
                      ])),
                ]),
              ),
            ));
  }

  Future<void> _updateStatus(String id, String status) async {
    await _sb.from('tables').update({'status': status}).eq('id', id);
    final idx = _tables.indexWhere((e) => e['id'] == id);
    if (idx != -1) {
      setState(() => _tables[idx] = {..._tables[idx], 'status': status});
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  String _initials(String name) {
    final p = name.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : name.isEmpty
            ? '?'
            : name[0].toUpperCase();
  }

  String _randomColorHex(String seed) {
    const c = [
      '5C6BC0',
      '26A69A',
      'EF5350',
      'AB47BC',
      '42A5F5',
      'FF7043',
      '66BB6A',
      'EC407A'
    ];
    return c[seed.hashCode.abs() % c.length];
  }

  // Themed input decoration matching app theme
  static InputDecoration _themedDeco(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: AppColors.textLight),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textLight),
        filled: true,
        fillColor: AppColors.contentBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.8)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.red)),
      );
}

// ── Theme label ───────────────────────────────────────────────
class _ThemedLabel extends StatelessWidget {
  final String text;
  const _ThemedLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark));
}

// ── Order info row ─────────────────────────────────────────────
class _OrderInfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _OrderInfoRow(this.icon, this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.15))),
        child: Row(children: [
          Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMid)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

// ── Add Table Button ──────────────────────────────────────────
class _AddTableButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool small;
  const _AddTableButton({required this.onTap, this.small = false});
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.add, size: small ? 15 : 17),
        label: Text(small ? 'Add Table' : 'Add New Table',
            style: TextStyle(
                fontSize: small ? 13 : 14, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.symmetric(
                horizontal: small ? 14 : 18, vertical: small ? 10 : 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
      );
}

// ── Stat Chip ─────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String value, label;
  final Color color, bg;
  const _StatChip(this.value, this.label, this.color, this.bg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$value $label',
              style: TextStyle(
                  color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
//  Table Card — redesigned
// ─────────────────────────────────────────────────────────────
class _TableCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit, onDelete, onViewOrder, onQrCode;
  final void Function(String) onStatusChange;
  const _TableCard(
      {required this.data,
      required this.onEdit,
      required this.onDelete,
      required this.onViewOrder,
      required this.onQrCode,
      required this.onStatusChange});
  @override
  State<_TableCard> createState() => _TableCardState();
}

class _TableCardState extends State<_TableCard> {
  bool _hovered = false;
  String get _status => widget.data['status'] as String? ?? 'available';

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeFg, badgeLabel, accentColor) = switch (_status) {
      'occupied' => (
          AppColors.statusOccupBg,
          AppColors.statusOccupied,
          'OCCUPIED',
          AppColors.statusOccupied
        ),
      'reserved' => (
          AppColors.statusResBg,
          AppColors.statusReserved,
          'RESERVED',
          AppColors.statusReserved
        ),
      _ => (
          AppColors.statusAvailBg,
          AppColors.statusAvailable,
          'AVAILABLE',
          AppColors.statusAvailable
        ),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: _hovered ? accentColor.withOpacity(0.4) : AppColors.border,
              width: _hovered ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color:
                    _hovered ? accentColor.withOpacity(0.12) : AppColors.shadow,
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Top row: number + badge ──
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        'Table ${widget.data['table_number']?.toString().padLeft(2, '0') ?? '01'}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textDark)),
                    const SizedBox(height: 2),
                    Text((widget.data['section'] ?? 'Main Hall').toString(),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMid)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.people_alt_outlined,
                          size: 11, color: AppColors.textLight),
                      const SizedBox(width: 3),
                      Text('${widget.data['seats'] ?? 4} Seats',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textLight)),
                    ]),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: badgeBg, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: badgeFg, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(badgeLabel,
                      style: TextStyle(
                          color: badgeFg,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3)),
                ]),
              ),
            ]),

            const SizedBox(height: 10),

            // ── Middle content ──
            Expanded(child: _buildMiddle(accentColor)),

            const SizedBox(height: 10),

            // ── Action row ──
            _buildActions(),
          ]),
        ),
      ),
    );
  }

  Widget _buildMiddle(Color accentColor) {
    if (_status == 'occupied') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.statusOccupBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFE0B2)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _InfoPair('Duration', widget.data['duration_text'] ?? '—',
              AppColors.statusOccupied),
          const SizedBox(height: 7),
          _InfoPair(
              'Total',
              widget.data['current_total'] != null
                  ? '\$${widget.data['current_total']}'
                  : '—',
              AppColors.textDark),
        ]),
      );
    }

    if (_status == 'reserved') {
      final hex = widget.data['avatar_color_hex'] as String? ?? '26A69A';
      final avatarColor = Color(int.parse('FF$hex', radix: 16));
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.statusResBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD1C4E9)),
        ),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                    radius: 14,
                    backgroundColor: avatarColor,
                    child: Text(widget.data['avatar_initials'] ?? '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(
                        '${widget.data['guest_name'] ?? ''} · ${widget.data['reservation_time'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark),
                        overflow: TextOverflow.ellipsis)),
              ]),
              if (widget.data['guest_phone'] != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.phone_outlined,
                      size: 11, color: AppColors.textLight),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(widget.data['guest_phone'] ?? '—',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textMid),
                          overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ]),
      );
    }

    // Available
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.statusAvailBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.statusAvailable.withOpacity(0.25)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_outline,
            size: 28, color: AppColors.statusAvailable.withOpacity(0.6)),
        const SizedBox(height: 5),
        Text('Ready to serve',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.statusAvailable.withOpacity(0.8))),
      ]),
    );
  }

  Widget _buildActions() {
    if (_status == 'occupied') {
      return Row(children: [
        Expanded(
            child: _PrimaryBtn(
                icon: Icons.receipt_long_outlined,
                label: 'View Order',
                onTap: widget.onViewOrder,
                color: AppColors.primary)),
        const SizedBox(width: 6),
        _CircleBtn(icon: Icons.edit_outlined, onTap: widget.onEdit),
        const SizedBox(width: 4),
        _CircleBtn(
            icon: Icons.delete_outline, onTap: widget.onDelete, isDelete: true),
      ]);
    }
    return Row(children: [
      Expanded(
          child: _PrimaryBtn(
              icon: Icons.qr_code_2_outlined,
              label: 'QR Code',
              onTap: widget.onQrCode,
              color: AppColors.textMid,
              outlined: true)),
      const SizedBox(width: 6),
      _CircleBtn(icon: Icons.edit_outlined, onTap: widget.onEdit),
      const SizedBox(width: 4),
      _CircleBtn(
          icon: Icons.delete_outline, onTap: widget.onDelete, isDelete: true),
    ]);
  }
}

class _InfoPair extends StatelessWidget {
  final String label, value;
  final Color valueColor;
  const _InfoPair(this.label, this.value, this.valueColor);
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMid)),
        Text(value,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: valueColor)),
      ]);
}

class _PrimaryBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool outlined;
  const _PrimaryBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      required this.color,
      this.outlined = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: outlined
            ? OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 13),
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: color,
                    side: BorderSide(color: color.withOpacity(0.4)),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9))))
            : ElevatedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 13),
                label: Text(label, style: const TextStyle(fontSize: 11.5)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9)))),
      );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDelete;
  const _CircleBtn(
      {required this.icon, required this.onTap, this.isDelete = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: isDelete
                ? AppColors.red.withOpacity(0.06)
                : AppColors.contentBg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: isDelete
                    ? AppColors.red.withOpacity(0.3)
                    : AppColors.border)),
        child: Icon(icon,
            size: 16, color: isDelete ? AppColors.red : AppColors.textMid),
      ));
}

// ─────────────────────────────────────────────────────────────
//  Add Card — properly centered content
// ─────────────────────────────────────────────────────────────
class _AddCard extends StatefulWidget {
  final VoidCallback onTap;
  const _AddCard({required this.onTap});
  @override
  State<_AddCard> createState() => _AddCardState();
}

class _AddCardState extends State<_AddCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.primary.withOpacity(0.03)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: DottedBorder(
              borderType: BorderType.RRect,
              radius: const Radius.circular(16),
              dashPattern: const [7, 5],
              color: _hovered ? AppColors.primary : const Color(0xFFB0C4C0),
              strokeWidth: 1.8,
              // ── KEY FIX: SizedBox.expand so the dotted border fills the
              //    grid cell, and Center perfectly places content inside ──
              child: SizedBox.expand(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _hovered
                              ? AppColors.primary.withOpacity(0.1)
                              : const Color(0xFFEAF1F0),
                          border: Border.all(
                              color: _hovered
                                  ? AppColors.primary
                                  : const Color(0xFFB0C4C0),
                              width: 1.5),
                        ),
                        child: Icon(Icons.add,
                            color: _hovered
                                ? AppColors.primary
                                : const Color(0xFFB0C4C0),
                            size: 24),
                      ),
                      const SizedBox(height: 12),
                      Text('Add New Table',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _hovered
                                  ? AppColors.primary
                                  : AppColors.textMid)),
                      const SizedBox(height: 4),
                      Text('Define seats & section',
                          style: TextStyle(
                              fontSize: 11,
                              color: _hovered
                                  ? AppColors.primary.withOpacity(0.6)
                                  : AppColors.textLight)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
