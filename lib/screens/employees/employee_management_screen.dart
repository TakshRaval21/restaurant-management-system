// lib/screens/employees/employees_screen.dart
//
// CHANGES FROM ORIGINAL:
// • "Add Employee" button replaced with "Invite Staff" button
// • _showInviteDialog() — sends magic link via Edge Function
//   Staff gets email → taps link → staff app opens → sets password
// • Edit dialog unchanged (kept _showDialog for editing)
// • Status column shows "Invited" badge for pending staff
// • _roleEmoji() helper added

import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/app_theme.dart';


class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _employees = [];
  String? _restaurantId;
  bool _loading = true;
  String _filterRole = 'all';

  static const _roles = ['all', 'manager', 'waiter', 'chef', 'cashier'];
  static const _roleColors = {
    'owner': Color(0xFF6A1B9A),
    'manager': Color(0xFF1565C0),
    'waiter': Color(0xFF2E7D32),
    'chef': Color(0xFFBF360C),
    'cashier': Color(0xFF00695C),
  };

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
    final data = await _sb
        .from('employees')
        .select()
        .eq('restaurant_id', _restaurantId!)
        .order('full_name');
    if (!mounted) return;
    setState(() {
      _employees = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filtered => _filterRole == 'all'
      ? _employees
      : _employees.where((e) => e['role'] == _filterRole).toList();

  // ── Invite Staff Dialog (NEW) ─────────────────────────────
  void _showInviteDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    String role = 'waiter';
    bool sending = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setDlg) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Container(
                    width: 440,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // ── Header ──
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
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.person_add_outlined,
                                  color: Colors.white, size: 20)),
                          const SizedBox(width: 12),
                          const Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Invite Staff Member',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textDark)),
                                Text(
                                    'They\'ll receive an email to set up their account',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textMid)),
                              ])),
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
                                    size: 15, color: AppColors.textMid)),
                          ),
                        ]),
                      ),

                      // ── Body ──
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                            key: formKey,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name + Role row
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              _ThemedLabel('Full Name'),
                                              const SizedBox(height: 6),
                                              TextFormField(
                                                  controller: nameCtrl,
                                                  validator: (v) =>
                                                      v!.trim().isEmpty
                                                          ? 'Required'
                                                          : null,
                                                  style: const TextStyle(
                                                      fontSize: 13.5,
                                                      color:
                                                          AppColors.textDark),
                                                  decoration: _themedDeco(
                                                      'John Doe',
                                                      Icons.person_outline)),
                                            ])),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              _ThemedLabel('Role'),
                                              const SizedBox(height: 6),
                                              DropdownButtonFormField<String>(
                                                initialValue: role,
                                                style: const TextStyle(
                                                    fontSize: 13.5,
                                                    color: AppColors.textDark),
                                                decoration: _themedDeco(
                                                    '', Icons.badge_outlined),
                                                items: _roles
                                                    .where((r) => r != 'all')
                                                    .map((r) =>
                                                        DropdownMenuItem(
                                                            value: r,
                                                            child:
                                                                Row(children: [
                                                              Text(
                                                                  _roleEmoji(r),
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          15)),
                                                              const SizedBox(
                                                                  width: 7),
                                                              Text(r[0]
                                                                      .toUpperCase() +
                                                                  r.substring(
                                                                      1)),
                                                            ])))
                                                    .toList(),
                                                onChanged: (v) => setDlg(
                                                    () => role = v ?? role),
                                              ),
                                            ])),
                                      ]),
                                  const SizedBox(height: 14),

                                  // Email
                                  _ThemedLabel('Email Address'),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                      controller: emailCtrl,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (v) {
                                        if (v!.trim().isEmpty) {
                                          return 'Required';
                                        }
                                        if (!v.contains('@')) {
                                          return 'Invalid email';
                                        }
                                        return null;
                                      },
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          color: AppColors.textDark),
                                      decoration: _themedDeco(
                                          'staff@restaurant.com',
                                          Icons.email_outlined)),
                                  const SizedBox(height: 14),

                                  // Phone + Salary row
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              _ThemedLabel('Phone (optional)'),
                                              const SizedBox(height: 6),
                                              TextFormField(
                                                  controller: phoneCtrl,
                                                  keyboardType:
                                                      TextInputType.phone,
                                                  style: const TextStyle(
                                                      fontSize: 13.5,
                                                      color:
                                                          AppColors.textDark),
                                                  decoration: _themedDeco(
                                                      '+1 555 0000',
                                                      Icons.phone_outlined)),
                                            ])),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              _ThemedLabel('Salary (optional)'),
                                              const SizedBox(height: 6),
                                              TextFormField(
                                                  controller: salaryCtrl,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  style: const TextStyle(
                                                      fontSize: 13.5,
                                                      color:
                                                          AppColors.textDark),
                                                  decoration: _themedDeco(
                                                      '0.00',
                                                      Icons.payments_outlined)),
                                            ])),
                                      ]),
                                  const SizedBox(height: 16),

                                  // Info box explaining magic link flow
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.primary.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: AppColors.primary
                                              .withOpacity(0.15)),
                                    ),
                                    child: const Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                              Icons.auto_awesome_outlined,
                                              size: 14,
                                              color: AppColors.primary),
                                          SizedBox(width: 8),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text('How it works',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            AppColors.primary)),
                                                SizedBox(height: 3),
                                                Text(
                                                    'Staff will receive an invite email → tap the link → open the RestoAdmin Staff app → set their own password → start working.',
                                                    style: TextStyle(
                                                        fontSize: 11.5,
                                                        color:
                                                            AppColors.textMid,
                                                        height: 1.45)),
                                              ])),
                                        ]),
                                  ),
                                ])),
                      ),

                      // ── Footer ──
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Row(children: [
                          Expanded(
                              child: OutlinedButton(
                            onPressed:
                                sending ? null : () => Navigator.pop(ctx),
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
                            onPressed: sending
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    setDlg(() => sending = true);
                                    try {
                                      // Call Edge Function — uses service role key server-side
                                      final response = await _sb.functions.invoke(
  'invite-staff',
  body: {
    'email':         emailCtrl.text.trim(),
    'full_name':     nameCtrl.text.trim(),
    'role':          role,
    'restaurant_id': _restaurantId,
    'redirect_to':   'staffapp://login-callback',
  },
  headers: {
    'Authorization': 'Bearer ${_sb.auth.currentSession?.accessToken ?? ''}',
  },
);

                                      if (response.status == 200) {
                                        // Insert employee record with 'invited' status
                                        final row = await _sb
                                            .from('employees')
                                            .insert({
                                              'restaurant_id': _restaurantId,
                                              'full_name': nameCtrl.text.trim(),
                                              'email': emailCtrl.text.trim(),
                                              'phone': phoneCtrl.text.trim(),
                                              'role': role,
                                              'status': 'invited',
                                              'salary': double.tryParse(
                                                  salaryCtrl.text),
                                            })
                                            .select()
                                            .single();
                                        setState(() => _employees.add(row));
                                        if (mounted) Navigator.pop(ctx);
                                        _snack(
                                            'Invite sent to ${emailCtrl.text.trim()} ✉️');
                                      } else {
                                        _snack(
                                            'Failed to send invite. Try again.',
                                            isError: true);
                                      }
                                    } catch (e) {
                                      _snack('Error: ${e.toString()}',
                                          isError: true);
                                    } finally {
                                      if (mounted) {
                                        setDlg(() => sending = false);
                                      }
                                    }
                                  },
                            child: sending
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                      child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                        Icon(Icons.send_outlined, size: 15),
                                        SizedBox(width: 6),
                                        Text('Send Invite',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700)),
                                      ]),
                          )),
                        ]),
                      ),
                    ]),
                  ),
                )));
  }

  // ── Edit Dialog (unchanged from original) ─────────────────
  void _showDialog([Map<String, dynamic>? emp]) {
    if (emp == null) {
      _showInviteDialog();
      return;
    } // new = invite
    final nameCtrl = TextEditingController(text: emp['full_name'] ?? '');
    final emailCtrl = TextEditingController(text: emp['email'] ?? '');
    final phoneCtrl = TextEditingController(text: emp['phone'] ?? '');
    final salaryCtrl =
        TextEditingController(text: emp['salary']?.toString() ?? '');
    String role = emp['role'] ?? 'waiter';
    String status = emp['status'] ?? 'active';

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Edit Employee',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark)),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        _f(nameCtrl, 'Full Name', Icons.person_outline),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _f(
                                  emailCtrl, 'Email', Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _f(
                                  phoneCtrl, 'Phone', Icons.phone_outlined,
                                  keyboardType: TextInputType.phone)),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _dd(
                                  'Role',
                                  role,
                                  _roles.where((r) => r != 'all').toList(),
                                  (v) => setDlg(() => role = v!))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _dd(
                                  'Status',
                                  status,
                                  ['active', 'inactive', 'invited'],
                                  (v) => setDlg(() => status = v!))),
                        ]),
                        const SizedBox(height: 12),
                        _f(salaryCtrl, 'Salary (optional)',
                            Icons.payments_outlined,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel',
                            style: TextStyle(color: AppColors.textMid))),
                    ElevatedButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty ||
                              emailCtrl.text.trim().isEmpty) {
                            return;
                          }
                          final payload = {
                            'restaurant_id': _restaurantId,
                            'full_name': nameCtrl.text.trim(),
                            'email': emailCtrl.text.trim(),
                            'phone': phoneCtrl.text.trim(),
                            'role': role,
                            'status': status,
                            'salary': double.tryParse(salaryCtrl.text),
                          };
                          await _sb
                              .from('employees')
                              .update(payload)
                              .eq('id', emp['id']);
                          final idx = _employees
                              .indexWhere((e) => e['id'] == emp['id']);
                          if (idx != -1) {
                            setState(() => _employees[idx] = {
                                  ..._employees[idx],
                                  ...payload
                                });
                          }
                          if (mounted) Navigator.pop(context);
                          _snack('Updated!');
                        },
                        child: const Text('Save')),
                  ],
                )));
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  title: const Text('Remove Employee?',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  content: const Text(
                      'This will remove the employee record. Their login account will remain in Supabase Auth.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white),
                        child: const Text('Remove')),
                  ],
                )) ??
        false;
    if (!ok) return;
    await _sb.from('employees').delete().eq('id', id);
    setState(() => _employees.removeWhere((e) => e['id'] == id));
    _snack('Employee removed');
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.red : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
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
      : Padding(
          padding: Responsive.padding(context),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ... everything inside child: stays exactly the same
                    // ── Header ──
                    if (isMobile)
                      Column(
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
                                        const Text('Employees',
                                            style: AppText.h1),
                                        Text(
                                            '${_employees.length} team members',
                                            style: AppText.body),
                                      ]),
                                  ElevatedButton.icon(
                                    onPressed: _showInviteDialog,
                                    icon: const Icon(Icons.person_add_outlined,
                                        size: 16),
                                    label: const Text('Invite'),
                                  ),
                                ]),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                    children: _roles
                                        .map((r) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: _chip(r)))
                                        .toList())),
                          ])
                    else
                      Row(children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Employees', style: AppText.h1),
                              Text('${_employees.length} team members',
                                  style: AppText.body),
                            ]),
                        const Spacer(),
                        ..._roles.map((r) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _chip(r))),
                        const SizedBox(width: 8),
                        // ── Invite Staff button (replaced "Add Employee") ──
                        ElevatedButton.icon(
                          onPressed: _showInviteDialog,
                          icon: const Icon(Icons.person_add_outlined, size: 16),
                          label: const Text('Invite Staff'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 11),
                          ),
                        ),
                      ]),

                    const SizedBox(height: 16),

                    // ── Table ──
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                  const Icon(Icons.people_outline,
                                      size: 48, color: AppColors.textLight),
                                  const SizedBox(height: 10),
                                  const Text('No employees found',
                                      style: AppText.h4),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                      onPressed: _showInviteDialog,
                                      icon: const Icon(
                                          Icons.person_add_outlined,
                                          size: 15),
                                      label: const Text(
                                          'Invite First Staff Member')),
                                ]))
                          : Column(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 11),
                                decoration: BoxDecoration(
                                    color: AppColors.contentBg,
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Row(children: [
                                  Expanded(
                                      flex: 5,
                                      child: Text('EMPLOYEE',
                                          style: AppText.label)),
                                  Expanded(
                                      flex: 3,
                                      child:
                                          Text('ROLE', style: AppText.label)),
                                  Expanded(
                                      flex: 4,
                                      child: Text('CONTACT',
                                          style: AppText.label)),
                                  Expanded(
                                      flex: 3,
                                      child:
                                          Text('STATUS', style: AppText.label)),
                                  Expanded(
                                      flex: 2,
                                      child:
                                          Text('SALARY', style: AppText.label)),
                                  SizedBox(
                                      width: 70,
                                      child: Text('ACTIONS',
                                          style: AppText.label)),
                                ]),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: AppColors.cardBg,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: AppColors.shadow,
                                            blurRadius: 10,
                                            offset: Offset(0, 2))
                                      ]),
                                  child: ListView.separated(
                                    itemCount: _filtered.length,
                                    separatorBuilder: (_, __) => const Divider(
                                        color: AppColors.divider, height: 1),
                                    itemBuilder: (_, i) => _EmployeeRow(
                                      emp: _filtered[i],
                                      roleColors: _roleColors,
                                      onEdit: () => _showDialog(_filtered[i]),
                                      onDelete: () =>
                                          _delete(_filtered[i]['id'] as String),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                    ),
                  ]),
    
    );
  }

  Widget _chip(String r) => ChoiceChip(
        label: Text(r == 'all' ? 'All' : r[0].toUpperCase() + r.substring(1),
            style: TextStyle(
                fontSize: 12,
                color: _filterRole == r ? Colors.white : AppColors.textMid,
                fontWeight: FontWeight.w600)),
        selected: _filterRole == r,
        selectedColor: AppColors.primary,
        onSelected: (_) => setState(() => _filterRole = r),
      );

  Widget _f(TextEditingController ctrl, String label, IconData icon,
          {TextInputType? keyboardType}) =>
      TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          decoration: InputDecoration(
              labelText: label,
              labelStyle:
                  const TextStyle(fontSize: 13, color: AppColors.textMid),
              prefixIcon: Icon(icon, size: 18, color: AppColors.textLight),
              filled: true,
              fillColor: const Color(0xFFF7FBFA),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12)));

  Widget _dd(String label, String value, List<String> items,
          ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
          initialValue: value,
          decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: const Color(0xFFF7FBFA),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
          style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          items: items
              .map((e) => DropdownMenuItem(
                  value: e, child: Text(e[0].toUpperCase() + e.substring(1))))
              .toList(),
          onChanged: onChanged);

  String _roleEmoji(String r) => switch (r) {
        'chef' => '👨‍🍳',
        'cashier' => '💳',
        'manager' => '🏢',
        _ => '🍽️',
      };

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

  static Widget _ThemedLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark));
}

// ─────────────────────────────────────────────────────────────
//  Employee Row — updated to show "Invited" status badge
// ─────────────────────────────────────────────────────────────
class _EmployeeRow extends StatelessWidget {
  final Map<String, dynamic> emp;
  final Map<String, Color> roleColors;
  final VoidCallback onEdit, onDelete;
  const _EmployeeRow(
      {required this.emp,
      required this.roleColors,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final role = emp['role'] as String? ?? 'waiter';
    final status = emp['status'] as String? ?? 'active';
    final phone = emp['phone'] as String? ?? '';
    final salary = emp['salary'];
    final roleClr = roleColors[role] ?? AppColors.primary;
    final initials = (emp['full_name'] as String? ?? 'U')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    // Status config — now includes 'invited'
    final (statusBg, statusFg, statusLabel) = switch (status) {
      'invited' => (
          const Color(0xFFFFF8E1),
          const Color(0xFFBF7900),
          'Invited ✉️'
        ),
      'inactive' => (AppColors.redBg, AppColors.red, 'Inactive'),
      _ => (AppColors.statusAvailBg, AppColors.statusAvailable, 'Active'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        // Employee name + avatar
        Expanded(
            flex: 5,
            child: Row(children: [
              CircleAvatar(
                  radius: 17,
                  backgroundColor: roleClr.withOpacity(0.15),
                  child: Text(initials,
                      style: TextStyle(
                          color: roleClr,
                          fontSize: 11,
                          fontWeight: FontWeight.w700))),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(emp['full_name'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textDark),
                        overflow: TextOverflow.ellipsis),
                    Text(emp['email'] ?? '',
                        style: AppText.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ])),
            ])),

        // Role badge
        Expanded(
            flex: 3,
            child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: roleClr.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(role[0].toUpperCase() + role.substring(1),
                        style: TextStyle(
                            color: roleClr,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis)))),

        // Phone
        Expanded(
            flex: 4,
            child: Text(phone.isNotEmpty ? phone : '—',
                style: AppText.body, overflow: TextOverflow.ellipsis)),

        // Status badge — shows "Invited" for pending staff
        Expanded(
            flex: 3,
            child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusFg,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))))),

        // Salary
        Expanded(
            flex: 2,
            child: Text(salary != null ? '\$$salary' : '—',
                style: AppText.body, overflow: TextOverflow.ellipsis)),

        // Actions
        SizedBox(
            width: 70,
            child: Row(children: [
              IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 17, color: AppColors.textMid),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30)),
              IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 17, color: AppColors.red),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30)),
            ])),
      ]),
    );
  }
}
