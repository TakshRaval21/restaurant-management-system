// lib/core/utils/currency_helper.dart
//
// Usage:
//   CurrencyHelper.symbolFor('INR')        → '₹'
//   CurrencyHelper.format(1299, 'INR')     → '₹1,299.00'
//   CurrencyHelper.formatCompact(12000, 'USD') → '$12K'

class CurrencyHelper {
  CurrencyHelper._();

  /// Maps ISO 4217 currency codes to their symbols.
  static const Map<String, String> _symbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'INR': '₹',
    'AED': 'د.إ',
    'SGD': 'S\$',
    'AUD': 'A\$',
    'CAD': 'C\$',
  };

  /// Returns the symbol for a given currency code.
  /// Falls back to the code itself if not found (e.g. 'XYZ').
  static String symbolFor(String? code) =>
      _symbols[code?.toUpperCase()] ?? (code ?? '\$');

  /// Formats [amount] with the currency symbol derived from [currencyCode].
  ///
  /// Example:
  ///   format(1299.5, 'INR')  → '₹1,299.50'
  ///   format(0,      'USD')  → '$0.00'
  static String format(num amount, String? currencyCode,
      {int decimalDigits = 2}) {
    final symbol = symbolFor(currencyCode);
    final formatted = _formatNumber(amount.toDouble(), decimalDigits);
    return '$symbol$formatted';
  }

  /// Compact format for large numbers shown in summary cards.
  ///
  /// Example:
  ///   formatCompact(1200000, 'INR') → '₹12L'   (Indian style)
  ///   formatCompact(1200000, 'USD') → '$1.2M'
  static String formatCompact(num amount, String? currencyCode) {
    final symbol = symbolFor(currencyCode);
    final isIndian = currencyCode?.toUpperCase() == 'INR';

    if (isIndian) {
      if (amount >= 10000000) {
        return '$symbol${(amount / 10000000).toStringAsFixed(1)}Cr';
      } else if (amount >= 100000) {
        return '$symbol${(amount / 100000).toStringAsFixed(1)}L';
      } else if (amount >= 1000) {
        return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
      }
    } else {
      if (amount >= 1000000000) {
        return '$symbol${(amount / 1000000000).toStringAsFixed(1)}B';
      } else if (amount >= 1000000) {
        return '$symbol${(amount / 1000000).toStringAsFixed(1)}M';
      } else if (amount >= 1000) {
        return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
      }
    }
    return format(amount, currencyCode);
  }

  /// Formats a number with thousands separators and decimal places.
  static String _formatNumber(double amount, int decimalDigits) {
    final fixed = amount.toStringAsFixed(decimalDigits);
    final parts = fixed.split('.');
    final intPart = _addThousandsSeparator(parts[0]);
    return decimalDigits > 0 ? '$intPart.${parts[1]}' : intPart;
  }

  static String _addThousandsSeparator(String intStr) {
    final buffer = StringBuffer();
    final digits = intStr.replaceAll('-', '');
    final isNegative = intStr.startsWith('-');
    int count = 0;
    for (int i = digits.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
      count++;
    }
    final result = buffer.toString().split('').reversed.join();
    return isNegative ? '-$result' : result;
  }
}