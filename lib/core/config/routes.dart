import 'package:admin_side/screens/analytics/analytics_screen.dart';
import 'package:admin_side/screens/billing/billing_screen.dart';
import 'package:admin_side/screens/employees/employee_management_screen.dart';
import 'package:admin_side/screens/kitchen/kitchen_display.dart';
import 'package:admin_side/screens/menu/menu_categories_screen.dart';
import 'package:admin_side/screens/orders/order_screen.dart' hide BillingScreen;
import 'package:admin_side/screens/parcel/parcel_screen.dart';
import 'package:admin_side/screens/qrcodes/qr_codes_screen.dart';
import 'package:admin_side/screens/restaurant/restaurant_setting_screen.dart';
import 'package:admin_side/screens/tables/table_management_screen.dart';
import 'package:flutter/material.dart';

import '../../screens/auth/login_screen.dart';
import '../../screens/auth/signup_screen.dart';
import '../../screens/restaurant/restaurant_setup_screen.dart';
import '../../layouts/admin_layout.dart';   // ← only this needed now

class AppRoutes {
  static const String login              = '/login';
  static const String signup             = '/signup';
  static const String setupRestaurant    = '/setuprestaurant';
  static const String dashboard          = '/dashboard';

  // ── These are kept as constants so admin_layout.dart can still
  //    use them in _navItems and _routeIndex — but they no longer
  //    need their own route builder entries.
  static const String restaurantSettings = '/restaurant-settings';
  static const String tableManagement    = '/tables';
  static const String menuManagement     = '/menu';
  static const String employees          = '/employees';
  static const String orders             = '/orders';
  static const String kitchen            = '/kitchen';
  static const String parcel             = '/parcel';
  static const String billing            = '/billing';
  static const String qrCodes           = '/qr-codes';
  static const String analytics          = '/analytics';

  static final Map<String, WidgetBuilder> routes = {
    login:           (_) => const LoginScreen(),
    signup:          (_) => const SignupScreen(),
    setupRestaurant: (_) => const SetupRestaurantScreen(),
    dashboard:       (_) => const AdminLayout(), 
        restaurantSettings: (_) => const RestaurantSettingsScreen(),
    tableManagement:    (_) => const TableManagementScreen(),
    menuManagement:     (_) => const MenuManagementScreen(),
    employees:          (_) => const EmployeesScreen(),
    orders:             (_) => const OrdersScreen(),
    kitchen:            (_) => const KitchenDisplayScreen(),
    billing:            (_) => const BillingScreen(),
    qrCodes:            (_) => const QrCodesScreen(),
    analytics:          (_) => const AnalyticsScreen(),
    parcel:             (_) => const ParcelScreen(), 

  };}