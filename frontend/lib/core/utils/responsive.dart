import 'package:flutter/widgets.dart';

import '../../app/theme/dimensions.dart';

enum ScreenSize { mobile, tablet, desktop }

ScreenSize screenSizeOf(double width) {
  if (width < Breakpoints.tablet) return ScreenSize.mobile;
  if (width <= Breakpoints.desktop) return ScreenSize.tablet;
  return ScreenSize.desktop;
}

extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize => screenSizeOf(MediaQuery.sizeOf(this).width);
  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// Vrai dès qu'il y a assez de place pour un tableau ou deux colonnes.
  bool get isWide => !isMobile;
}
