import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/utils/media.dart';
import 'photo_viewer.dart';

/// Photo principale d'un produit (vignette avec l'initiale s'il n'en a pas).
///
/// Avec une photo, un clic l'ouvre en plein écran ; [gallery] (toutes les photos du produit) permet
/// ensuite de passer de l'une à l'autre. Les chemins de l'API (/media/...) sont complétés ici.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.gallery = const [],
    this.size = 56,
    this.openOnTap = true,
  });

  final String name;
  final String? imageUrl;
  final List<String> gallery;
  final double size;
  final bool openOnTap;

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
    final baseUrl = context.read<ApiClient>().baseUrl;
    final url = resolveMediaUrl(imageUrl, baseUrl);
    if (url == null) return placeholder;
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
    if (!openOnTap) return photo;
    final urls = [
      for (final path in gallery.isEmpty ? [imageUrl] : gallery) ?resolveMediaUrl(path, baseUrl),
    ];
    return Tooltip(
      message: 'Voir la photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => showPhotoViewer(context, urls, title: name),
        child: photo,
      ),
    );
  }
}
