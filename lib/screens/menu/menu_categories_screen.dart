// lib/screens/menu/menu_management_screen.dart
import 'dart:typed_data';
import 'package:admin_side/layouts/admin_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/services/restaurant_service.dart';
import '../../core/config/app_theme.dart';


class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});
  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _items = [];
  String? _restaurantId;
  String? _selectedCategoryId;
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
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
    if (r == null) {
      setState(() => _loading = false);
      return;
    }
    _restaurantId = r['id'] as String;
    await _loadAll();
  }

  Future<void> _loadAll() async {
    final cats = await _sb
        .from('menu_categories')
        .select()
        .eq('restaurant_id', _restaurantId!)
        .order('sort_order');
    final items = await _sb
        .from('menu_items')
        .select()
        .eq('restaurant_id', _restaurantId!)
        .order('sort_order');
    if (!mounted) return;
    setState(() {
      _categories = List<Map<String, dynamic>>.from(cats);
      _items = List<Map<String, dynamic>>.from(items);
      if (_categories.isNotEmpty) {
        _selectedCategoryId ??= _categories.first['id'] as String;
      }
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredItems => _selectedCategoryId == null
      ? _items
      : _items.where((i) => i['category_id'] == _selectedCategoryId).toList();

  Future<String?> _uploadImageBytes(Uint8List bytes, String fileName) async {
    try {
      final ext = fileName.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      final path =
          'menu-images/$_restaurantId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _sb.storage.from('menu-images').uploadBinary(path, bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true));
      return _sb.storage.from('menu-images').getPublicUrl(path);
    } catch (e) {
      _snack('Image upload failed: $e', isError: true);
      return null;
    }
  }

  Future<void> _deleteImageByUrl(String url) async {
    try {
      final segs = Uri.parse(url).pathSegments;
      final idx = segs.indexOf('menu-images');
      if (idx != -1) {
        await _sb.storage
            .from('menu-images')
            .remove([segs.sublist(idx).join('/')]);
      }
    } catch (_) {}
  }

  void _showCategoryDialog([Map<String, dynamic>? cat]) {
    final nameCtrl = TextEditingController(text: cat?['name'] ?? '');
    final iconCtrl = TextEditingController(text: cat?['icon'] ?? '🍽️');
    final descCtrl = TextEditingController(text: cat?['description'] ?? '');
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(cat == null ? 'Add Category' : 'Edit Category',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.textDark)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                _dlgField(nameCtrl, 'Category Name', Icons.category_outlined),
                const SizedBox(height: 12),
                _dlgField(
                    iconCtrl, 'Emoji Icon', Icons.emoji_emotions_outlined),
                const SizedBox(height: 12),
                _dlgField(descCtrl, 'Description (optional)',
                    Icons.description_outlined),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textMid))),
                ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      final payload = {
                        'restaurant_id': _restaurantId,
                        'name': nameCtrl.text.trim(),
                        'icon': iconCtrl.text.trim().isEmpty
                            ? '🍽️'
                            : iconCtrl.text.trim(),
                        'description': descCtrl.text.trim()
                      };
                      if (cat == null) {
                        final row = await _sb
                            .from('menu_categories')
                            .insert(payload)
                            .select()
                            .single();
                        setState(() {
                          _categories.add(row);
                          _selectedCategoryId = row['id'];
                        });
                      } else {
                        await _sb
                            .from('menu_categories')
                            .update(payload)
                            .eq('id', cat['id']);
                        final idx =
                            _categories.indexWhere((c) => c['id'] == cat['id']);
                        if (idx != -1) {
                          setState(() => _categories[idx] = {
                                ..._categories[idx],
                                ...payload
                              });
                        }
                      }
                      if (mounted) Navigator.pop(context);
                      _snack(cat == null
                          ? 'Category added!'
                          : 'Category updated!');
                    },
                    child: const Text('Save')),
              ],
            ));
  }

  Future<void> _deleteCategory(String id) async {
    final ok = await _confirmDialog(
        'Delete category? All items in it will be unlinked.');
    if (!ok) return;
    await _sb.from('menu_categories').delete().eq('id', id);
    setState(() {
      _categories.removeWhere((c) => c['id'] == id);
      if (_selectedCategoryId == id) {
        _selectedCategoryId =
            _categories.isNotEmpty ? _categories.first['id'] : null;
      }
    });
    _snack('Category deleted');
  }

  void _showItemDialog([Map<String, dynamic>? item]) {
    final nameCtrl = TextEditingController(text: item?['name'] ?? '');
    final priceCtrl =
        TextEditingController(text: item?['price']?.toString() ?? '');
    final descCtrl = TextEditingController(text: item?['description'] ?? '');
    final prepCtrl = TextEditingController(
        text: item?['prep_time_mins']?.toString() ?? '15');
    bool available = item?['is_available'] ?? true;
    bool featured = item?['is_featured'] ?? false;
    String catId = item?['category_id'] ?? (_selectedCategoryId ?? '');
    String? existingImageUrl = item?['image_url'] as String?;
    Uint8List? pickedBytes;
    String? pickedFileName;
    bool removeImage = false;
    bool uploading = false;

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, setDlg) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Text(item == null ? 'Add Menu Item' : 'Edit Menu Item',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark)),
                  content: SizedBox(
                      width: 500,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        _PhotoPicker(
                          existingUrl: removeImage ? null : existingImageUrl,
                          previewBytes: pickedBytes,
                          onPick: () async {
                            final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1200,
                                maxHeight: 1200,
                                imageQuality: 85);
                            if (picked == null) return;
                            final bytes = await picked.readAsBytes();
                            setDlg(() {
                              pickedBytes = bytes;
                              pickedFileName = picked.name;
                              removeImage = false;
                            });
                          },
                          onRemove: () => setDlg(() {
                            pickedBytes = null;
                            pickedFileName = null;
                            removeImage = true;
                          }),
                        ),
                        const SizedBox(height: 16),
                        _dlgField(
                            nameCtrl, 'Item Name', Icons.fastfood_outlined,
                            validator: (v) =>
                                v!.trim().isEmpty ? 'Required' : null),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: _dlgField(priceCtrl, 'Price',
                                  Icons.attach_money_outlined,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _dlgField(prepCtrl, 'Prep Time (mins)',
                                  Icons.timer_outlined,
                                  keyboardType: TextInputType.number)),
                        ]),
                        const SizedBox(height: 12),
                        _dlgField(descCtrl, 'Description',
                            Icons.description_outlined),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: catId.isEmpty ? null : catId,
                          decoration:
                              _dlgDeco('Category', Icons.category_outlined),
                          items: _categories
                              .map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text('${c['icon']} ${c['name']}')))
                              .toList(),
                          onChanged: (v) => setDlg(() => catId = v ?? catId),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Available',
                                      style: TextStyle(fontSize: 13)),
                                  value: available,
                                  activeThumbColor: AppColors.primary,
                                  onChanged: (v) =>
                                      setDlg(() => available = v))),
                          Expanded(
                              child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Featured',
                                      style: TextStyle(fontSize: 13)),
                                  value: featured,
                                  activeThumbColor: AppColors.primary,
                                  onChanged: (v) =>
                                      setDlg(() => featured = v))),
                        ]),
                        if (uploading) ...[
                          const SizedBox(height: 10),
                          const LinearProgressIndicator(
                              color: AppColors.primary),
                          const SizedBox(height: 6),
                          const Text('Uploading image...',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMid))
                        ],
                      ]))),
                  actions: [
                    TextButton(
                        onPressed:
                            uploading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel',
                            style: TextStyle(color: AppColors.textMid))),
                    ElevatedButton(
                        onPressed: uploading
                            ? null
                            : () async {
                                if (nameCtrl.text.trim().isEmpty) return;
                                setDlg(() => uploading = true);
                                String? finalImageUrl = existingImageUrl;
                                if (removeImage && existingImageUrl != null) {
                                  await _deleteImageByUrl(existingImageUrl);
                                  finalImageUrl = null;
                                }
                                if (pickedBytes != null &&
                                    pickedFileName != null) {
                                  if (existingImageUrl != null && !removeImage) {
                                    await _deleteImageByUrl(existingImageUrl);
                                  }
                                  finalImageUrl = await _uploadImageBytes(
                                      pickedBytes!, pickedFileName!);
                                }
                                final payload = {
                                  'restaurant_id': _restaurantId,
                                  'name': nameCtrl.text.trim(),
                                  'price':
                                      double.tryParse(priceCtrl.text) ?? 0.0,
                                  'description': descCtrl.text.trim(),
                                  'prep_time_mins':
                                      int.tryParse(prepCtrl.text) ?? 15,
                                  'category_id': catId.isEmpty ? null : catId,
                                  'is_available': available,
                                  'is_featured': featured,
                                  'image_url': finalImageUrl
                                };
                                if (item == null) {
                                  final row = await _sb
                                      .from('menu_items')
                                      .insert(payload)
                                      .select()
                                      .single();
                                  setState(() => _items.add(row));
                                } else {
                                  await _sb
                                      .from('menu_items')
                                      .update(payload)
                                      .eq('id', item['id']);
                                  final idx = _items
                                      .indexWhere((i) => i['id'] == item['id']);
                                  if (idx != -1) {
                                    setState(() => _items[idx] = {
                                          ..._items[idx],
                                          ...payload
                                        });
                                  }
                                }
                                setDlg(() => uploading = false);
                                if (mounted) Navigator.pop(context);
                                _snack(item == null
                                    ? 'Item added!'
                                    : 'Item updated!');
                              },
                        child: const Text('Save')),
                  ],
                )));
  }

  Future<void> _deleteItem(String id) async {
    final ok = await _confirmDialog('Delete this menu item?');
    if (!ok) return;
    final item = _items.firstWhere((i) => i['id'] == id, orElse: () => {});
    if ((item['image_url'] as String?) != null) {
      await _deleteImageByUrl(item['image_url'] as String);
    }
    await _sb.from('menu_items').delete().eq('id', id);
    setState(() => _items.removeWhere((i) => i['id'] == id));
    _snack('Item deleted');
  }

  Future<void> _toggleAvailable(Map<String, dynamic> item) async {
    final newVal = !(item['is_available'] as bool? ?? true);
    await _sb
        .from('menu_items')
        .update({'is_available': newVal}).eq('id', item['id']);
    final idx = _items.indexWhere((i) => i['id'] == item['id']);
    if (idx != -1) setState(() => _items[idx]['is_available'] = newVal);
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
          _buildHeader(isMobile),
          Expanded(
              child: isMobile
                  ? Column(children: [
                      _buildCategoryRow(),
                      Expanded(child: _buildItemsPanel(isMobile))
                    ])
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildCategoryPanel(),
                      Expanded(child: _buildItemsPanel(isMobile))
                    ])),
        ]);
}

  Widget _buildHeader(bool isMobile) => Container(
        padding:
            EdgeInsets.fromLTRB(isMobile ? 14 : 24, 16, isMobile ? 14 : 24, 0),
        color: AppColors.contentBg,
        child: isMobile
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Menu', style: AppText.h1),
                            Text(
                                '${_categories.length} cats · ${_items.length} items',
                                style: AppText.bodySmall),
                          ]),
                      Row(children: [
                        OutlinedButton(
                            onPressed: _showCategoryDialog,
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side:
                                    const BorderSide(color: AppColors.primary),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 9)),
                            child: const Text('+ Cat',
                                style: TextStyle(fontSize: 12))),
                        const SizedBox(width: 8),
                        ElevatedButton(
                            onPressed: () => _showItemDialog(),
                            style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 9),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9))),
                            child: const Text('+ Item',
                                style: TextStyle(fontSize: 12))),
                      ]),
                    ]),
              ])
            : Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Menu Management', style: AppText.h1),
                  Text(
                      '${_categories.length} categories · ${_items.length} items',
                      style: AppText.body),
                ]),
                const Spacer(),
                OutlinedButton.icon(
                    onPressed: _showCategoryDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Category'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11))),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                    onPressed: () => _showItemDialog(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Item')),
              ]),
      );

  Widget _buildCategoryRow() => Container(
        height: 50,
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length,
          itemBuilder: (_, i) {
            final cat = _categories[i];
            final active = cat['id'] == _selectedCategoryId;
            final count =
                _items.where((it) => it['category_id'] == cat['id']).length;
            return GestureDetector(
              onTap: () =>
                  setState(() => _selectedCategoryId = cat['id'] as String),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: active ? AppColors.primary : AppColors.border)),
                child: Row(children: [
                  Text(cat['icon'] ?? '🍽️',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(cat['name'] ?? '',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : AppColors.textDark)),
                  const SizedBox(width: 4),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: active
                              ? Colors.white.withOpacity(0.25)
                              : AppColors.contentBg,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('$count',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color:
                                  active ? Colors.white : AppColors.textMid))),
                ]),
              ),
            );
          },
        ),
      );

  Widget _buildCategoryPanel() => Container(
        width: 210,
        margin: const EdgeInsets.all(14),
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
          const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Text('Categories', style: AppText.h4)),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
              child: _categories.isEmpty
                  ? const Center(
                      child: Text('No categories yet', style: AppText.body))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _categories.length,
                      itemBuilder: (_, i) {
                        final cat = _categories[i];
                        final active = cat['id'] == _selectedCategoryId;
                        final count = _items
                            .where((it) => it['category_id'] == cat['id'])
                            .length;
                        return GestureDetector(
                          onTap: () => setState(
                              () => _selectedCategoryId = cat['id'] as String),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary.withOpacity(0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: active
                                    ? Border.all(
                                        color:
                                            AppColors.primary.withOpacity(0.3))
                                    : null),
                            child: Row(children: [
                              Text(cat['icon'] ?? '🍽️',
                                  style: const TextStyle(fontSize: 17)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(cat['name'] ?? '',
                                      style: TextStyle(
                                          fontWeight: active
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          fontSize: 12.5,
                                          color: active
                                              ? AppColors.primary
                                              : AppColors.textDark),
                                      overflow: TextOverflow.ellipsis)),
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                      color: active
                                          ? AppColors.primary
                                          : AppColors.contentBg,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Text('$count',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: active
                                              ? Colors.white
                                              : AppColors.textMid))),
                            ]),
                          ),
                        );
                      },
                    )),
          if (_selectedCategoryId != null) ...[
            const Divider(color: AppColors.divider, height: 1),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(
                      child: TextButton.icon(
                          onPressed: () {
                            final cat = _categories.firstWhere(
                                (c) => c['id'] == _selectedCategoryId);
                            _showCategoryDialog(cat);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 13),
                          label: const Text('Edit',
                              style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.textMid))),
                  Expanded(
                      child: TextButton.icon(
                          onPressed: () =>
                              _deleteCategory(_selectedCategoryId!),
                          icon: const Icon(Icons.delete_outline, size: 13),
                          label: const Text('Delete',
                              style: TextStyle(fontSize: 11)),
                          style: TextButton.styleFrom(
                              foregroundColor: AppColors.red))),
                ])),
          ],
        ]),
      );

  Widget _buildItemsPanel(bool isMobile) {
    final items = _filteredItems;
    // ── Key fix: use maxCrossAxisExtent so cards never get too wide
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 14 : 0, 14, 14, 14),
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
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Text('${items.length} item${items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textDark)),
                const Spacer(),
                if (items.isNotEmpty)
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.touch_app_outlined,
                            size: 13, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text('Tap card to edit',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary.withOpacity(0.8),
                                fontWeight: FontWeight.w500))
                      ])),
              ])),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.07),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.fastfood_outlined,
                                size: 36, color: AppColors.primary)),
                        const SizedBox(height: 14),
                        const Text('No items in this category',
                            style: AppText.h4),
                        const SizedBox(height: 6),
                        const Text('Add your first dish to get started',
                            style: AppText.body),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                            onPressed: () => _showItemDialog(),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Item')),
                      ]))
                : GridView.builder(
                    padding: const EdgeInsets.all(14),
                    // ── SliverGridDelegateWithMaxCrossAxisExtent automatically
                    //    adapts columns — no dead space at any screen size
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220, // each card max 220px wide
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.72, // taller than wide → no empty gap
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _ItemCard(
                      item: items[i],
                      onEdit: () => _showItemDialog(items[i]),
                      onDelete: () => _deleteItem(items[i]['id'] as String),
                      onToggle: () => _toggleAvailable(items[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────
  Widget _dlgField(TextEditingController ctrl, String label, IconData icon,
          {TextInputType? keyboardType,
          List<TextInputFormatter>? inputFormatters,
          String? Function(String?)? validator}) =>
      TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textDark),
          decoration: _dlgDeco(label, icon));

  InputDecoration _dlgDeco(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMid),
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
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12));

  Future<bool> _confirmDialog(String msg) async =>
      await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  title: const Text('Confirm',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  content: Text(msg),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: AppColors.textMid))),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white),
                        child: const Text('Delete'))
                  ])) ??
      false;

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.red : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }
}

// ─────────────────────────────────────────────────────────────
//  Photo Picker
// ─────────────────────────────────────────────────────────────
  class _PhotoPicker extends StatelessWidget {
    final String? existingUrl;
  final Uint8List? previewBytes;
  final VoidCallback onPick, onRemove;
  const _PhotoPicker(
      {required this.existingUrl,
      required this.previewBytes,
      required this.onPick,
      required this.onRemove});
  bool get _has => previewBytes != null || existingUrl != null;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.photo_camera_outlined,
              size: 15, color: AppColors.textMid),
          const SizedBox(width: 6),
          const Text('Food Photo',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMid)),
          const Spacer(),
          if (_has)
            GestureDetector(
                onTap: onRemove,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(6)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.delete_outline,
                          size: 12, color: AppColors.red),
                      SizedBox(width: 4),
                      Text('Remove',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.red,
                              fontWeight: FontWeight.w600))
                    ]))),
        ]),
        const SizedBox(height: 8),
        GestureDetector(
            onTap: onPick,
            child: Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                    color: const Color(0xFFF4F8F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _has
                            ? AppColors.primary.withOpacity(0.5)
                            : AppColors.border,
                        width: _has ? 1.5 : 1)),
                clipBehavior: Clip.antiAlias,
                child: _has ? _preview() : _placeholder())),
        const SizedBox(height: 5),
        Text(_has ? 'Tap to change · Max 5MB' : 'JPG, PNG or WEBP · Max 5MB',
            style: AppText.bodySmall),
      ]);

  Widget _preview() => Stack(fit: StackFit.expand, children: [
        previewBytes != null
            ? Image.memory(previewBytes!, fit: BoxFit.cover)
            : Image.network(existingUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder()),
        Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent
                    ])),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_outlined, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Tap to change',
                          style: TextStyle(color: Colors.white, fontSize: 11))
                    ]))),
      ]);

  Widget _placeholder() =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.add_photo_alternate_outlined,
                size: 28, color: AppColors.primary)),
        const SizedBox(height: 8),
        const Text('Tap to add food photo',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMid)),
      ]);
}

// ─────────────────────────────────────────────────────────────
//  Item Card — redesigned
// ─────────────────────────────────────────────────────────────
class _ItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit, onDelete, onToggle;
  const _ItemCard(
      {required this.item,
      required this.onEdit,
      required this.onDelete,
      required this.onToggle});
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final available = widget.item['is_available'] as bool? ?? true;
    final featured = widget.item['is_featured'] as bool? ?? false;
    final imageUrl = widget.item['image_url'] as String?;
    final priceNum = (widget.item['price'] as num?)?.toDouble() ?? 0.0;
    final prep = widget.item['prep_time_mins'] ?? 15;
    final name = widget.item['name'] as String? ?? '';
    final desc = widget.item['description'] as String? ?? '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _hovered
                    ? AppColors.primary.withOpacity(0.4)
                    : AppColors.border,
                width: _hovered ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                  color: _hovered
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.shadow,
                  blurRadius: _hovered ? 14 : 6,
                  offset: const Offset(0, 3))
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Food photo (fixed height, covers top of card) ──
            Stack(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                child: SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : _shimmer(),
                          errorBuilder: (_, __, ___) => _noPhoto(),
                        )
                      : _noPhoto(),
                ),
              ),
              // Featured badge — top left
              if (featured)
                Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.orange.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text('Featured',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2))
                      ]),
                    )),
              // Unavailable overlay
              if (!available)
                Positioned.fill(
                    child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(13)),
                  child: Container(
                      color: Colors.black.withOpacity(0.45),
                      child: const Center(
                          child: Text('UNAVAILABLE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5)))),
                )),
            ]),

            // ── Content ──────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.textDark,
                              height: 1.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),

                      // Description
                      Text(desc.isEmpty ? 'No description' : desc,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMid,
                              height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),

                      const Spacer(),

                      // Price row
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                   Text(
     RestaurantService.instance.formatPrice(priceNum),
     style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800,
        color: AppColors.primary, letterSpacing: -0.3)),
                                  Row(children: [
                                    const Icon(Icons.timer_outlined,
                                        size: 10, color: AppColors.textLight),
                                    const SizedBox(width: 2),
                                    Text('${prep}m',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textLight)),
                                  ]),
                                ])),
                            // Action buttons
                            Row(children: [
                              _ActionBtn(
                                  icon: Icons.edit_outlined,
                                  color: AppColors.textMid,
                                  onTap: widget.onEdit),
                              const SizedBox(width: 4),
                              _ActionBtn(
                                  icon: Icons.delete_outline,
                                  color: AppColors.red,
                                  onTap: widget.onDelete),
                            ]),
                          ]),

                      const SizedBox(height: 8),

                      // Availability toggle — full width pill
                      GestureDetector(
                        onTap: widget.onToggle,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: available
                                ? AppColors.statusAvailBg
                                : AppColors.redBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: available
                                    ? AppColors.statusAvailable.withOpacity(0.3)
                                    : AppColors.red.withOpacity(0.3)),
                          ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                        color: available
                                            ? AppColors.statusAvailable
                                            : AppColors.red,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 5),
                                Text(available ? 'Available' : 'Unavailable',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: available
                                            ? AppColors.statusAvailable
                                            : AppColors.red)),
                              ]),
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

  Widget _noPhoto() => Container(
        color: const Color(0xFFF0F5F4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.restaurant_menu,
              size: 32, color: AppColors.primary.withOpacity(0.3)),
          const SizedBox(height: 4),
          Text('No photo',
              style: TextStyle(
                  fontSize: 10, color: AppColors.textLight.withOpacity(0.7))),
        ]),
      );

  Widget _shimmer() => Container(
        color: const Color(0xFFEEF2F1),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                  child: Lottie.asset(
        'assets/animations/loader.json',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
      ),)),
      );
}

// ── Small circular action button ─────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.2))),
          child: Icon(icon, size: 14, color: color),
        ),
      );
}
