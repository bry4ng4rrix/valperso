import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Ouvre les photos en plein écran : glisser pour passer d'une photo à l'autre, pincer (ou molette)
/// pour zoomer. [urls] : adresses complètes.
Future<void> showPhotoViewer(BuildContext context, List<String> urls, {int initialIndex = 0, String? title}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      barrierDismissible: true,
      pageBuilder: (_, _, _) => PhotoViewer(urls: urls, initialIndex: initialIndex, title: title),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.urls, this.initialIndex = 0, this.title});

  final List<String> urls;
  final int initialIndex;
  final String? title;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) =>
      _pages.animateToPage(_index + delta, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final count = widget.urls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          [?widget.title, if (count > 1) '${_index + 1} / $count'].join(' · '),
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: count,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.network(
                  widget.urls[index],
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorBuilder: (_, _, _) => const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                      SizedBox(height: Gaps.sm),
                      Text('Photo indisponible', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Flèches sur ordinateur (au téléphone, on glisse).
          if (count > 1) ...[
            if (_index > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Photo précédente',
                  color: Colors.white,
                  icon: const Icon(Icons.chevron_left, size: 40),
                  onPressed: () => _go(-1),
                ),
              ),
            if (_index < count - 1)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Photo suivante',
                  color: Colors.white,
                  icon: const Icon(Icons.chevron_right, size: 40),
                  onPressed: () => _go(1),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
