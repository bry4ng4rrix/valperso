import 'package:flutter/material.dart';

/// Palette de l'application : base noire, bleu foncé pour les actions,
/// et quelques couleurs sémantiques réservées aux états (succès, attention, erreur).
///
/// Pour changer l'apparence de toute l'application, modifier uniquement ce fichier.
abstract final class AppColors {
  // --- Thème sombre (par défaut) ---------------------------------------------------------
  static const background = Color(0xFF07090D);
  static const surface = Color(0xFF0F131A);
  static const surfaceHigh = Color(0xFF161B24);
  static const surfaceHighest = Color(0xFF1E2531);
  static const border = Color(0xFF263041);

  static const primary = Color(0xFF2F5BD3); // bleu foncé : actions principales, éléments actifs
  static const primaryDark = Color(0xFF1E3A8A);
  static const primarySoft = Color(0xFF14254D); // fond des éléments sélectionnés

  static const textPrimary = Color(0xFFE6EAF2);
  static const textSecondary = Color(0xFF94A0B4);
  static const textMuted = Color(0xFF66718A);

  // --- Couleurs sémantiques (états uniquement) -------------------------------------------
  static const success = Color(0xFF22A06B); // payé, stock disponible
  static const warning = Color(0xFFE09B2D); // stock faible, paiement partiel
  static const danger = Color(0xFFE5484D); // erreur, suppression, rupture, dette
  static const info = Color(0xFF4C8DF6);

  // --- Thème clair (prévu, non utilisé par défaut) ---------------------------------------
  static const lightBackground = Color(0xFFF5F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFEDF1F7);
  static const lightBorder = Color(0xFFD7DEEA);
  static const lightTextPrimary = Color(0xFF111827);
  static const lightTextSecondary = Color(0xFF4B5563);
}
