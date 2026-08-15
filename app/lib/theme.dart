import 'package:flutter/cupertino.dart';

/// The visual vocabulary: iOS grouped-table semantics, resolved for light and dark.
///
/// Flutter's Cupertino library gives us the controls but not the surface colours a
/// Settings-style app needs, so the handful that matter are defined once here rather
/// than being guessed at in each screen.
class AppColors {
  const AppColors({
    required this.background,
    required this.card,
    required this.cardPressed,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.tint,
    required this.success,
    required this.warning,
    required this.danger,
    required this.fill,
  });

  final Color background;
  final Color card;
  final Color cardPressed;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color separator;
  final Color tint;
  final Color success;
  final Color warning;
  final Color danger;
  final Color fill;

  static const AppColors light = AppColors(
    background: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    cardPressed: Color(0xFFE5E5EA),
    label: Color(0xFF1C1C1E),
    secondaryLabel: Color(0xFF8E8E93),
    tertiaryLabel: Color(0xFFC7C7CC),
    separator: Color(0x333C3C43),
    tint: Color(0xFF007AFF),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9500),
    danger: Color(0xFFFF3B30),
    fill: Color(0x1F767680),
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    cardPressed: Color(0xFF2C2C2E),
    label: Color(0xFFF2F2F7),
    secondaryLabel: Color(0xFF8E8E93),
    tertiaryLabel: Color(0xFF48484A),
    separator: Color(0x99545458),
    tint: Color(0xFF0A84FF),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    fill: Color(0x3D767680),
  );

  static AppColors of(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark ? dark : light;
}

class AppText {
  static const TextStyle largeTitle =
      TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.1);
  static const TextStyle title =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3);
  static const TextStyle headline =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const TextStyle body = TextStyle(fontSize: 17, letterSpacing: -0.2, height: 1.35);
  static const TextStyle callout = TextStyle(fontSize: 16, letterSpacing: -0.2);
  static const TextStyle subhead = TextStyle(fontSize: 15, letterSpacing: -0.1);
  static const TextStyle footnote = TextStyle(fontSize: 13, height: 1.35);
  static const TextStyle caption = TextStyle(fontSize: 12);
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
  );
}

/// The one place that decides which brightness the app runs at.
CupertinoThemeData appTheme(String preference, Brightness platformBrightness) {
  final brightness = switch (preference) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => platformBrightness,
  };
  final colors = brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: colors.tint,
    scaffoldBackgroundColor: colors.background,
    barBackgroundColor: brightness == Brightness.dark
        ? const Color(0xF01C1C1E)
        : const Color(0xF0F9F9F9),
    textTheme: CupertinoTextThemeData(
      primaryColor: colors.tint,
      textStyle: AppText.body.copyWith(color: colors.label),
      navTitleTextStyle: AppText.headline.copyWith(color: colors.label),
      navLargeTitleTextStyle: AppText.largeTitle.copyWith(color: colors.label),
    ),
  );
}

/// Clock helpers used across the screens. Formatting a handful of dates does not justify
/// pulling in `intl` and its locale data.
class When {
  static String time(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String minuteOfDay(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String dayLabel(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfThat = DateTime(d.year, d.month, d.day);
    final diff = startOfToday.difference(startOfThat).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[d.weekday - 1];
    }
    if (d.year == today.year) return '${_months[d.month - 1]} ${d.day}';
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String stamp(int epochMs) => '${dayLabel(epochMs)} at ${time(epochMs)}';

  static String relative(int epochMs) {
    final delta = DateTime.now().millisecondsSinceEpoch - epochMs;
    if (delta < 60_000) return 'just now';
    if (delta < 3_600_000) return '${delta ~/ 60_000} min ago';
    if (delta < 86_400_000) return '${delta ~/ 3_600_000} h ago';
    return dayLabel(epochMs);
  }

  static String duration(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    if (seconds % 60 == 0) {
      final m = seconds ~/ 60;
      return m == 1 ? '1 minute' : '$m minutes';
    }
    return '${seconds ~/ 60} min ${seconds % 60} s';
  }
}
