import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Image principale d'un produit.
///
/// L'API actuelle ne gère pas encore d'images de produit : une vignette avec l'initiale est
/// affichée. Dès que l'API fournira une adresse d'image, il suffira de passer [imageUrl].
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, required this.name, this.imageUrl, this.size = 56});

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.sm)),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w700, color: scheme.primary),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
