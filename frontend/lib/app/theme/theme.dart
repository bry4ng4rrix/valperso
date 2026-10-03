import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'colors.dart';
import 'dimensions.dart';
import 'typography.dart';

/// Thèmes Material 3 centralisés. L'application démarre en [AppTheme.dark].
abstract final class AppTheme {
  /// Polices de secours ajoutées par les tests visuels : la Roboto du SDK de test n'a pas tous les
  /// symboles (« → »), que les appareils réels trouvent dans leurs polices système.
  @visibleForTesting
  static List<String> testFontFallback = const [];

  /// Thème sombre : noir et gris neutres, actions en blanc.
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceHigh: AppColors.surfaceHigh,
    border: AppColors.border,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    accent: AppColors.accent,
    onAccent: AppColors.onAccent,
    accentSoft: AppColors.accentSoft,
    onAccentSoft: AppColors.textPrimary,
    secondary: AppColors.accentMuted,
  );

  /// Thème clair : fond clair, actions en bleu.
  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceHigh: AppColors.lightSurfaceHigh,
    border: AppColors.lightBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    accent: AppColors.primary,
    onAccent: Colors.white,
    accentSoft: AppColors.primarySoft,
    onAccentSoft: AppColors.primaryDark,
    secondary: AppColors.primaryDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color onAccent,
    required Color accentSoft,
    required Color onAccentSoft,
    required Color secondary,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentSoft,
      onPrimaryContainer: onAccentSoft,
      secondary: secondary,
      onSecondary: brightness == Brightness.dark ? textPrimary : Colors.white,
      secondaryContainer: accentSoft,
      onSecondaryContainer: onAccentSoft,
      error: AppColors.danger,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: border,
      outlineVariant: border,
    );
    // Tailles et couleurs de l'application sur la typographie de la plateforme (police, polices de secours) :
    // les styles utilisés tels quels (titre de la barre, puces) gardent ainsi la même police que le reste.
    final platformTextTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme.merge(buildTextTheme(textPrimary, textSecondary));
    final textTheme = testFontFallback.isEmpty
        ? platformTextTheme
        : platformTextTheme.apply(fontFamilyFallback: testFontFallback);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md));
    const buttonPadding = EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      tabBarTheme: TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicatorColor: accent,
        dividerColor: border,
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, Sizes.minTouchTarget),
          padding: buttonPadding,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, Sizes.minTouchTarget),
          padding: buttonPadding,
          shape: shape,
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 44), shape: shape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        labelStyle: textTheme.bodyMedium,
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(backgroundColor: surface, indicatorColor: scheme.primaryContainer),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelMedium,
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 0.6,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(color: surfaceHigh, borderRadius: BorderRadius.circular(Radii.sm)),
        textStyle: textTheme.bodySmall?.copyWith(color: textPrimary),
      ),
    );
  }
}
