/// Small display formatters (the example avoids extra dependencies such as
/// `intl`; a real app would use localized formatters).
abstract final class Formatters {
  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `$1,234.50` for 123450 cents.
  static String money(int amountInCents, String currency) {
    final symbol = switch (currency) {
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };
    final negative = amountInCents < 0;
    final cents = amountInCents.abs();
    final whole = (cents ~/ 100).toString();
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$symbol$grouped.$fraction';
  }

  /// `Oct 30, 2026`.
  static String date(DateTime value) {
    final local = value.toLocal();
    return '${_months[local.month - 1]} ${local.day}, ${local.year}';
  }

  /// `Oct 30, 2026 · 16:05`.
  static String dateTime(DateTime value) {
    final local = value.toLocal();
    return '${date(local)} · ${time(local)}';
  }

  /// `16:05`.
  static String time(DateTime value) {
    final local = value.toLocal();
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  /// `1.5 MB`.
  static String bytes(int value) {
    if (value < 1024) return '$value B';
    const units = <String>['KB', 'MB', 'GB'];
    var size = value / 1024;
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final whole = size >= 100 || size == size.roundToDouble();
    return '${size.toStringAsFixed(whole ? 0 : 1)} ${units[unit]}';
  }

  /// `45%`.
  static String percent(double fraction) =>
      '${(fraction * 100).clamp(0, 100).round()}%';

  /// `in 25 s`, `expired 3 min ago`...
  static String countdown(Duration remaining) {
    if (remaining.isNegative) {
      return 'expired ${_duration(-remaining)} ago';
    }
    return 'in ${_duration(remaining)}';
  }

  static String _duration(Duration value) {
    if (value.inSeconds < 60) return '${value.inSeconds} s';
    if (value.inMinutes < 60) return '${value.inMinutes} min';
    if (value.inHours < 48) return '${value.inHours} h';
    return '${value.inDays} days';
  }

  /// Initials of [name] (at most two letters).
  static String initials(String? name) {
    final parts =
        (name ?? '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
    if (parts.isEmpty) return '?';
    final letters =
        parts.length == 1
            ? parts.first.substring(0, 1)
            : '${parts.first[0]}${parts.last[0]}';
    return letters.toUpperCase();
  }
}
