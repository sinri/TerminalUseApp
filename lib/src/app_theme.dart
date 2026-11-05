import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'card_text.dart';

/// Shared desktop tokens: neutral chrome, blue focus, compact controls.
ThemeData desktopTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff3979db),
        brightness: brightness,
        surface: dark ? const Color(0xff202124) : const Color(0xfff5f5f7),
      ).copyWith(
        primary: dark ? const Color(0xff7aafff) : const Color(0xff0065d1),
        surfaceContainerLowest: dark ? const Color(0xff191a1c) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff252628)
            : const Color(0xfff0f0f2),
        surfaceContainer: dark
            ? const Color(0xff2c2d30)
            : const Color(0xffe9e9ec),
        secondaryContainer: dark
            ? const Color(0xff31445e)
            : const Color(0xffd9e8fa),
        outlineVariant: dark
            ? const Color(0xff3e4044)
            : const Color(0xffd0d1d5),
      );
  final border = BorderSide(color: scheme.outlineVariant);
  // Button text animates from Material's fully resolved, non-inheriting style.
  // Preserve its fields and inherit flag during hot reload and theme changes.
  final typographyBase = ThemeData(
    brightness: brightness,
    fontFamilyFallback: cardFontFallback,
  );
  final buttonText = typographyBase.typography.englishLike
      .merge(typographyBase.textTheme)
      .labelLarge!
      .copyWith(fontSize: 12);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: defaultTargetPlatform == TargetPlatform.macOS
        ? '.AppleSystemUIFont'
        : null,
    fontFamilyFallback: cardFontFallback,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.macOS: CupertinoPageTransitionsBuilder()},
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: border,
      ),
      textStyle: buttonText,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        side: WidgetStatePropertyAll(border),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(buttonText),
        minimumSize: const WidgetStatePropertyAll(Size(120, 28)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border,
      ),
      titleTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    ),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    iconTheme: IconThemeData(size: 16, color: scheme.onSurfaceVariant),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 28),
        maximumSize: const Size(32, 32),
        padding: const EdgeInsets.all(5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        textStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        textStyle: buttonText,
        side: border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 4,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: scheme.outlineVariant,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, height: 1.3),
      bodySmall: TextStyle(fontSize: 12, height: 1.4),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 38,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: border,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: border,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: border,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        minimumSize: const Size(48, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        textStyle: buttonText,
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
