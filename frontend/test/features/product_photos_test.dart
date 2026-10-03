import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:valmag/core/widgets/app_dialog.dart';
import 'package:valmag/features/products/product_photos.dart';
import 'package:valmag/shared/widgets/photo_viewer.dart';
import 'package:valmag/shared/widgets/product_avatar.dart';

import '../support/demo_data.dart';
import '../support/fake_api.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(32, 0)]);

Map<String, Object?> _withPhotos(int count) {
  final product = demoProducts.first;
  final images = [
    for (var i = 1; i <= count; i++) {'id': i, 'url': '/media/products/photo$i.jpg'},
  ];
  return {...product, 'images': images, 'image_url': images.isEmpty ? null : images.first['url']};
}

Future<FakeApi> _openProduct(WidgetTester tester, {int photos = 0}) async {
  setScreenSize(tester, mobileSize);
  final api = FakeApi();
  stubDemoApi(api);
  api.on('GET', '/products/10', (_) => _withPhotos(photos));
  await pumpApp(tester, api, loggedIn: demoMe());
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/products/10');
  await settle(tester);
  return api;
}

void main() {
  setUpAll(initFrenchDates);

  testWidgets('fiche produit : ajouter une photo depuis la galerie', (tester) async {
    final api = await _openProduct(tester);
    api.on('POST', '/products/10/images', (_) => _withPhotos(1), status: 201);
    final original = pickProductPhoto;
    addTearDown(() => pickProductPhoto = original);
    ImageSource? asked;
    pickProductPhoto = (source) async {
      asked = source;
      return XFile.fromData(_png, name: 'abaya.png', mimeType: 'image/png');
    };

    expect(find.text('Photos (0)'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Ajouter une photo'));
    await tester.tap(find.byTooltip('Ajouter une photo'));
    await tester.pumpAndSettle();
    expect(find.text('Prendre une photo'), findsOneWidget, reason: 'Android : appareil photo ou galerie');
    await tester.tap(find.text('Choisir dans la galerie'));
    await settle(tester);

    expect(asked, ImageSource.gallery);
    final form = api.calls('POST', '/products/10/images').single.data as FormData;
    expect(form.files.single.key, 'file');
    expect(form.files.single.value.length, _png.length, reason: 'la photo choisie est envoyée telle quelle');
    expect(find.text('Photo ajoutée.'), findsOneWidget);
  });

  testWidgets('fiche produit : un clic sur une photo l\'ouvre en grand, on passe à la suivante', (tester) async {
    await _openProduct(tester, photos: 2);
    expect(find.text('Photos (2)'), findsOneWidget);

    await tester.tap(find.byTooltip('Voir la photo'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.text('Abaya brodée · 1 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Photo suivante'));
    await tester.pumpAndSettle();
    expect(find.text('Abaya brodée · 2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('fiche produit : supprimer une photo après confirmation', (tester) async {
    final api = await _openProduct(tester, photos: 1);
    api.on('DELETE', '/products/10/images/1', (_) => _withPhotos(0));

    await tester.ensureVisible(find.byTooltip('Supprimer la photo'));
    await tester.tap(find.byTooltip('Supprimer la photo'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer cette photo ?'), findsOneWidget);
    expect(api.calls('DELETE', '/products/10/images/1'), isEmpty);
    await tester.tap(find.descendant(of: find.byType(AppDialog), matching: find.text('Supprimer')));
    await settle(tester);

    expect(api.calls('DELETE', '/products/10/images/1'), hasLength(1));
  });

  testWidgets('vente : la photo du produit s\'affiche dans le catalogue et s\'ouvre au clic', (tester) async {
    setScreenSize(tester, desktopSize);
    final api = FakeApi();
    stubDemoApi(api);
    final line = {...demoStockLines.first, 'product': _withPhotos(1)};
    api.on('GET', '/stock', (_) => page([line]));
    await pumpApp(tester, api, loggedIn: demoMe());
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/sales/new');
    await settle(tester);

    final avatar = tester.widget<ProductAvatar>(find.byType(ProductAvatar).first);
    expect(avatar.imageUrl, '/media/products/photo1.jpg');
    await tester.tap(find.byTooltip('Voir la photo').first);
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(api.calls('POST', '/sales'), isEmpty, reason: 'ouvrir la photo n\'ajoute rien au panier');
  });
}
