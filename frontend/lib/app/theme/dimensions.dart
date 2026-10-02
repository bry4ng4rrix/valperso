/// Espacements, rayons et tailles communs. Utiliser ces constantes plutôt que des valeurs en dur.
abstract final class Gaps {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}

/// Points de rupture du responsive : mobile < 600 <= tablette <= 1024 < bureau.
abstract final class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 1024.0;
}

abstract final class Sizes {
  static const minTouchTarget = 48.0;
  static const sidebarWidth = 248.0;
  static const sidebarCompactWidth = 76.0;
  static const formMaxWidth = 640.0;
  static const contentMaxWidth = 1400.0;
}
