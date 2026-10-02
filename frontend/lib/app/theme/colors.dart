import 'package:flutter/material.dart';

/// Palette de l'application.
///
/// - Thème sombre (par défaut) : entièrement noir et gris neutres, sans teinte bleue ;
///   les actions principales sont blanches (texte noir).
/// - Thème clair : fond clair, actions en bleu.
/// - Quelques couleurs sémantiques réservées aux états (succès, attention, erreur), communes aux deux.
///
/// Pour changer l'apparence de toute l'application, modifier uniquement ce fichier.
abstract final class AppColors {
  // --- Thème sombre (par défaut) : noir ------------------------------------------------------
  static const background = Color(0xFF000000); // noir pur
  static const surface = Color(0xFF0E0E0E); // cartes, menu latéral, barres
  static const surfaceHigh = Color(0xFF181818); // champs de saisie, éléments survolés
  static const surfaceHighest = Color(0xFF222222);
  static const border = Color(0xFF2A2A2A);

  static const accent = Color(0xFFF2F2F2); // blanc cassé : actions principales, éléments actifs
  static const onAccent = Color(0xFF000000);
  static const accentSoft = Color(0xFF262626); // fond des éléments sélectionnés (menu, puces)
  static const accentMuted = Color(0xFF3A3A3A);

  static const textPrimary = Color(0xFFEDEDED);
  static const textSecondary = Color(0xFFA3A3A3);
  static const textMuted = Color(0xFF6B6B6B);

  // --- Thème clair ----------------------------------------------------------------------------
  static const lightBackground = Color(0xFFF5F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFEDF1F7);
  static const lightBorder = Color(0xFFD7DEEA);
  static const lightTextPrimary = Color(0xFF111827);
  static const lightTextSecondary = Color(0xFF4B5563);

  static const primary = Color(0xFF2F5BD3); // bleu : actions principales du thème clair
  static const primaryDark = Color(0xFF1E3A8A);
  static const primarySoft = Color(0xFFDCE6FF);

  // --- Couleurs sémantiques (états uniquement) ------------------------------------------------
  static const success = Color(0xFF22A06B); // payé, stock disponible
  static const warning = Color(0xFFE09B2D); // stock faible, paiement partiel
  static const danger = Color(0xFFE5484D); // erreur, suppression, rupture, dette
}
