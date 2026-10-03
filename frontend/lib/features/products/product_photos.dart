import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/utils/media.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/photo_viewer.dart';
import '../../shared/widgets/product_avatar.dart';
import 'product_models.dart';
import 'products_repository.dart';

/// Choix d'une photo : appareil photo ou galerie (Android), fichier (ordinateur).
/// Réduite à 1600 px : l'envoi reste léger. Remplacée dans les tests (pas de galerie).
@visibleForTesting
Future<XFile?> Function(ImageSource source) pickProductPhoto = (source) =>
    ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);

/// Photos d'un produit : un clic ouvre la photo en grand ; ajout et suppression si autorisé.
class ProductPhotosCard extends StatefulWidget {
  const ProductPhotosCard({super.key, required this.product, required this.canEdit, required this.onChanged});

  final Product product;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<ProductPhotosCard> createState() => _ProductPhotosCardState();
}

class _ProductPhotosCardState extends State<ProductPhotosCard> {
  bool _busy = false;

  Future<ImageSource?> _chooseSource() async {
    // Sur ordinateur, pas d'appareil photo : on choisit directement un fichier.
    if (defaultTargetPlatform != TargetPlatform.android) return ImageSource.gallery;
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    final source = await _chooseSource();
    if (source == null || !mounted) return;
    final file = await pickProductPhoto(source);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final repository = context.read<ProductsRepository>();
    final done = await runApiAction(
      context,
      // Le serveur reconnaît le format au contenu ; le nom sert seulement à l'envoi.
      () => repository.addImage(widget.product.id, bytes, file.name.isEmpty ? 'photo' : file.name),
      success: 'Photo ajoutée.',
    );
    if (mounted) setState(() => _busy = false);
    if (done) widget.onChanged();
  }

  Future<void> _delete(ProductImage image) async {
    final confirmed = await showConfirmation(
      context,
      title: 'Supprimer cette photo ?',
      message: 'La photo est retirée du produit ${widget.product.label}.',
      confirmLabel: 'Supprimer',
      type: ConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;
    final done = await runApiAction(
      context,
      () => context.read<ProductsRepository>().deleteImage(widget.product.id, image.id),
      success: 'Photo supprimée.',
    );
    if (done) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.images;
    final baseUrl = context.read<ApiClient>().baseUrl;
    final urls = [for (final image in images) ?resolveMediaUrl(image.url, baseUrl)];
    return SectionCard(
      title: 'Photos (${images.length})',
      icon: Icons.photo_library_outlined,
      trailing: widget.canEdit
          ? Tooltip(
              message: 'Ajouter une photo',
              child: TextButton.icon(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Ajouter'),
              ),
            )
          : null,
      child: images.isEmpty
          ? Text(
              widget.canEdit
                  ? 'Aucune photo. Ajoutez-en depuis l\'appareil photo ou la galerie.'
                  : 'Aucune photo pour ce produit.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : Wrap(
              spacing: Gaps.sm,
              runSpacing: Gaps.sm,
              children: [
                for (final (index, image) in images.indexed)
                  Stack(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        onTap: () => showPhotoViewer(context, urls, initialIndex: index, title: widget.product.label),
                        child: ProductAvatar(
                          name: widget.product.label,
                          imageUrl: image.url,
                          size: 96,
                          openOnTap: false,
                        ),
                      ),
                      if (widget.canEdit)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: IconButton.filled(
                            tooltip: 'Supprimer la photo',
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            style: IconButton.styleFrom(backgroundColor: Colors.black54),
                            onPressed: () => _delete(image),
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}
