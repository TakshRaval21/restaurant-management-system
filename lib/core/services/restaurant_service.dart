// lib/core/services/restaurant_service.dart
//
// A lightweight singleton that fetches your restaurant row from Supabase
// ONCE per app session and caches it in memory.
//
// ─── Setup (call in main.dart after Supabase.initialize) ───────────────────
//   await RestaurantService.instance.init();
//
// ─── Read anywhere ─────────────────────────────────────────────────────────
//   final currency = RestaurantService.instance.currency;   // 'INR'
//   final symbol   = RestaurantService.instance.symbol;     // '₹'
//   final name     = RestaurantService.instance.name;       // 'The Golden Grill'

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:admin_side/core/utils/currency_helper.dart';
class RestaurantService {
  RestaurantService._();
  static final RestaurantService instance = RestaurantService._();

  final _sb = Supabase.instance.client;

  // ── Cached data ────────────────────────────────────────────────────────────
  Map<String, dynamic>? _data;

  bool get isLoaded => _data != null;

  // ── Convenience getters ────────────────────────────────────────────────────
  String get restaurantId => _data?['id'] as String? ?? '';
  String get name => _data?['name'] as String? ?? '';
  String get currency => _data?['currency'] as String? ?? 'USD';
  String get symbol => CurrencyHelper.symbolFor(currency);
  String get timezone => _data?['timezone'] as String? ?? 'UTC';
  double get taxRate => (_data?['tax_rate'] as num?)?.toDouble() ?? 0.0;
  bool get isLive => _data?['is_live'] as bool? ?? false;
  String? get logoUrl => _data?['logo_url'] as String?;
  String get openingTime => _data?['opening_time'] as String? ?? '09:00';
  String get closingTime => _data?['closing_time'] as String? ?? '23:00';

  // ── Init: call once in main.dart ──────────────────────────────────────────
  /// Fetches the restaurant row for the currently logged-in owner.
  /// Safe to call multiple times — re-fetches only if [forceRefresh] is true.
  Future<void> init({bool forceRefresh = false}) async {
    if (isLoaded && !forceRefresh) return;

    final user = _sb.auth.currentUser;
    if (user == null) return;

    try {
      final row = await _sb
          .from('restaurants')
          .select()
          .eq('owner_id', user.id)
          .maybeSingle();

      _data = row;
    } catch (e) {
      // Silently fail — screens should handle null state gracefully
      debugPrint('[RestaurantService] init error: $e');
    }
  }

  /// Call this after the user updates restaurant settings so the cache refreshes.
  Future<void> refresh() => init(forceRefresh: true);

  /// Clear cache on sign-out.
  void clear() => _data = null;

  // ── Formatting helpers (pass-through to CurrencyHelper) ───────────────────

  /// Formats a price using the restaurant's saved currency.
  /// e.g.  formatPrice(1299)  → '₹1,299.00'
  String formatPrice(num amount, {int decimalDigits = 2}) =>
      CurrencyHelper.format(amount, currency, decimalDigits: decimalDigits);

  /// Compact format for dashboard summary cards.
  /// e.g.  formatCompact(125000)  → '₹1.2L'  or  '$125K'
  String formatCompact(num amount) =>
      CurrencyHelper.formatCompact(amount, currency);
}