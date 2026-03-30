import 'package:flutter/material.dart';
import 'package:admin_side/core/services/restaurant_service.dart'; 

class CurrencyText extends StatelessWidget {
  final num amount;
  final bool compact;
  final TextStyle? style;
  final int decimalDigits;

  const CurrencyText(
    this.amount, {
    super.key,
    this.compact = false,
    this.style,
    this.decimalDigits = 2,
  });

  @override
  Widget build(BuildContext context) {
    final svc = RestaurantService.instance;
    final text = compact
        ? svc.formatCompact(amount)
        : svc.formatPrice(amount, decimalDigits: decimalDigits);
    return Text(text, style: style);
  }
}


