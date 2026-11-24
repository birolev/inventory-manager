import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/controllers/inventory_search_controller.dart';
import 'package:yoaron_app/screens/inventory_list_screen.dart';
import 'package:yoaron_app/screens/sales_screen.dart';
import 'package:yoaron_app/screens/search_screen.dart';
import 'package:yoaron_app/services/image_inventory_search.dart';
import 'package:yoaron_app/services/inventory_search.dart';
import 'package:yoaron_app/theme/app_theme.dart';
import 'package:yoaron_app/widgets/inventory_search_view.dart';

// 1x1 transparent PNG so Image.memory decodes cleanly in widget tests.
final Uint8List _validPngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

SearchImageInput _testPhoto(String id) => SearchImageInput(
  id: id,
  mimeType: 'image/png',
  initialBytes: _validPngBytes,
);

Widget _themed(Widget home) => MaterialApp(theme: AppTheme.light(), home: home);

class _ImageCallRecord {
  _ImageCallRecord(this.mode, this.criteria);
  final ImageSearchMode mode;
  final InventorySearchCriteria criteria;
}

class _TestGateway implements InventorySearchGateway {
  final List<_ImageCallRecord> imageCalls = [];
  int criteriaCallCount = 0;

  Future<ImageInventorySearchResult> Function(
    ImageSearchMode mode,
    InventorySearchCriteria criteria,
    InventorySortOption sortOption,
    int callIndex,
  )?
  onSearchByImage;

  Future<ImageInventorySearchResult> Function(
    InventorySearchCriteria criteria,
    InventorySortOption sortOption,
  )?
  onSearchByCriteria;

  @override
  Future<ImageInventorySearchResult> searchByImage({
    required Uint8List imageBytes,
    required String mimeType,
    required InventorySearchCriteria criteria,
    required ImageSearchMode mode,
    required InventorySortOption sortOption,
  }) {
    final idx = imageCalls.length;
    imageCalls.add(_ImageCallRecord(mode, criteria));
    if (onSearchByImage != null) {
      return onSearchByImage!(mode, criteria, sortOption, idx);
    }
    return Future.value(
      ImageInventorySearchResult(
        aiCriteria: null,
        criteria: criteria,
        matches: const [],
        usedFallback: false,
        embedding: const [0.1, 0.2],
        resolvedMode: mode,
      ),
    );
  }

  @override
  Future<ImageInventorySearchResult> searchByExistingEmbedding({
    required List<num> embedding,
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
  }) async {
    return ImageInventorySearchResult(
      aiCriteria: null,
      criteria: criteria,
      matches: const [],
      usedFallback: false,
      embedding: embedding,
      resolvedMode: ImageSearchMode.embedded,
    );
  }

  @override
  Future<ImageInventorySearchResult> searchByCriteria({
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
    bool allowFallback = true,
  }) async {
    criteriaCallCount++;
    if (onSearchByCriteria != null) {
      return onSearchByCriteria!(criteria, sortOption);
    }
    return ImageInventorySearchResult(
      aiCriteria: null,
      criteria: criteria,
      matches: [
        {
          'id': 'manual-1',
          'name': 'Manual Tee',
          'brand': 'Nike',
          'category': 'Póló',
          'gender': 'férfi',
          'price_est': 3500,
          'location': 'Csengery',
          'is_sold': false,
        },
      ],
      usedFallback: false,
    );
  }
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _switchModeInUi(WidgetTester tester, String targetLabel) async {
  final dropdown = find.byType(DropdownButtonFormField<ImageSearchMode>);
  expect(dropdown, findsOneWidget);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(targetLabel).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Multi-image sales logging scenarios', () {
    testWidgets('1. Multiple pictures using vector search', (tester) async {
      await _setPhoneViewport(tester);
      final gateway = _TestGateway();
      gateway.onSearchByImage = (mode, criteria, sort, idx) async {
        expect(mode, ImageSearchMode.embedded);
        return ImageInventorySearchResult(
          aiCriteria: null,
          criteria: criteria,
          matches: [
            {
              'id': 'item-${idx + 1}',
              'name': 'Vector Item ${idx + 1}',
              'brand': 'Brand',
              'category': 'Póló',
              'gender': 'férfi',
              'price_est': 3000 * (idx + 1),
              'location': 'Csengery',
            },
          ],
          usedFallback: false,
          embedding: const [0.1, 0.2],
          resolvedMode: ImageSearchMode.embedded,
        );
      };

      await tester.pumpWidget(
        _themed(
          SalesScreen(
            searchGateway: gateway,
            initialPhotos: [_testPhoto('p1'), _testPhoto('p2')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fotó 1 / 2'), findsOneWidget);
      await _tapVisible(tester, find.text('Vector Item 1'));
      await tester.tap(find.text('Hozzáadás és következő'));
      await tester.pumpAndSettle();

      expect(find.text('Fotó 2 / 2'), findsOneWidget);
      await _tapVisible(tester, find.text('Vector Item 2'));
      await tester.tap(find.text('Párosítás kész'));
      await tester.pumpAndSettle();

      expect(find.text('2 tétel a kosárban'), findsOneWidget);
      expect(gateway.imageCalls.length, 2);
    });

    testWidgets(
      '2. Multiple pictures using Gemini keep independent criteria per photo',
      (tester) async {
        await _setPhoneViewport(tester);
        final gateway = _TestGateway();
        gateway.onSearchByImage = (mode, criteria, sort, idx) async {
          if (mode == ImageSearchMode.embedded) {
            return ImageInventorySearchResult(
              aiCriteria: null,
              criteria: criteria,
              matches: [
                {'id': 'vec-0', 'name': 'Initial Vector', 'price_est': 1000},
              ],
              usedFallback: false,
              embedding: const [0.1],
              resolvedMode: ImageSearchMode.embedded,
            );
          }
          final geminiCount = gateway.imageCalls
              .where((c) => c.mode == ImageSearchMode.gemini)
              .length;
          if (geminiCount == 1) {
            return const ImageInventorySearchResult(
              aiCriteria: {
                'category': 'hoodie',
                'gender': 'férfi',
                'color': 'kék',
              },
              criteria: InventorySearchCriteria(
                category: 'hoodie',
                gender: 'férfi',
                color: 'kék',
              ),
              matches: [
                {
                  'id': 'gem-1',
                  'name': 'Blue Hoodie',
                  'category': 'hoodie',
                  'gender': 'férfi',
                  'price_est': 8000,
                },
              ],
              usedFallback: false,
              resolvedMode: ImageSearchMode.gemini,
            );
          }
          return const ImageInventorySearchResult(
            aiCriteria: {'category': 'Póló', 'gender': 'női', 'color': 'fehér'},
            criteria: InventorySearchCriteria(
              category: 'Póló',
              gender: 'női',
              color: 'fehér',
            ),
            matches: [
              {
                'id': 'gem-2',
                'name': 'White Tee',
                'category': 'Póló',
                'gender': 'női',
                'price_est': 3500,
              },
            ],
            usedFallback: false,
            resolvedMode: ImageSearchMode.gemini,
          );
        };

        await tester.pumpWidget(
          _themed(
            SalesScreen(
              searchGateway: gateway,
              initialPhotos: [_testPhoto('p1'), _testPhoto('p2')],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _switchModeInUi(tester, 'AI elemzés (Gemini)');
        expect(find.text('Blue Hoodie'), findsOneWidget);

        await _tapVisible(tester, find.text('Blue Hoodie'));
        await tester.tap(find.text('Hozzáadás és következő'));
        await tester.pumpAndSettle();

        final photo2Call = gateway.imageCalls.last;
        expect(photo2Call.mode, ImageSearchMode.gemini);
        expect(photo2Call.criteria.category, 'Minden');
        expect(photo2Call.criteria.color, '');
        expect(find.text('White Tee'), findsOneWidget);

        await _tapVisible(tester, find.text('White Tee'));
        await tester.tap(find.text('Párosítás kész'));
        await tester.pumpAndSettle();

        expect(find.text('2 tétel a kosárban'), findsOneWidget);
      },
    );

    testWidgets(
      '3 & 4 & 5. Switching Vector -> Gemini -> Vector across pictures keeps clean state',
      (tester) async {
        await _setPhoneViewport(tester);
        final gateway = _TestGateway();
        gateway.onSearchByImage = (mode, criteria, sort, idx) async {
          if (mode == ImageSearchMode.gemini) {
            return ImageInventorySearchResult(
              aiCriteria: const {
                'category': 'dzseki',
                'gender': 'férfi',
                'color': 'fekete',
              },
              criteria: const InventorySearchCriteria(
                category: 'dzseki',
                gender: 'férfi',
                color: 'fekete',
              ),
              matches: [
                {
                  'id': 'g-$idx',
                  'name': 'Gemini Jacket $idx',
                  'category': 'dzseki',
                  'price_est': 15000,
                },
              ],
              usedFallback: false,
              resolvedMode: ImageSearchMode.gemini,
            );
          }
          return ImageInventorySearchResult(
            aiCriteria: null,
            criteria: criteria,
            matches: [
              {
                'id': 'v-$idx',
                'name': 'Vector Shirt $idx',
                'category': 'ing',
                'price_est': 4000,
              },
            ],
            usedFallback: false,
            embedding: const [0.5, 0.5],
            resolvedMode: ImageSearchMode.embedded,
          );
        };

        await tester.pumpWidget(
          _themed(
            SalesScreen(
              searchGateway: gateway,
              initialPhotos: [
                _testPhoto('p1'),
                _testPhoto('p2'),
                _testPhoto('p3'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tapVisible(tester, find.text('Vector Shirt 0'));
        await tester.tap(find.text('Hozzáadás és következő'));
        await tester.pumpAndSettle();

        await _switchModeInUi(tester, 'AI elemzés (Gemini)');
        await _tapVisible(tester, find.text('Gemini Jacket 2'));
        await tester.tap(find.text('Hozzáadás és következő'));
        await tester.pumpAndSettle();

        await _switchModeInUi(tester, 'Vizuális keresés (Gyors)');
        expect(gateway.imageCalls.last.criteria.category, 'Minden');
        expect(gateway.imageCalls.last.criteria.color, '');

        await _switchModeInUi(tester, 'AI elemzés (Gemini)');
        await _switchModeInUi(tester, 'Vizuális keresés (Gyors)');
        expect(gateway.imageCalls.last.criteria.category, 'Minden');
        expect(gateway.imageCalls.last.criteria.color, '');

        final lastIdx = gateway.imageCalls.length - 1;
        await _tapVisible(tester, find.text('Vector Shirt $lastIdx'));
        await tester.tap(find.text('Párosítás kész'));
        await tester.pumpAndSettle();

        expect(find.text('3 tétel a kosárban'), findsOneWidget);
      },
    );

    testWidgets(
      '6. Failure mid-batch allows retry or continue without losing previous matches',
      (tester) async {
        await _setPhoneViewport(tester);
        final gateway = _TestGateway();
        var photo2Attempts = 0;
        gateway.onSearchByImage = (mode, criteria, sort, idx) async {
          if (idx == 0) {
            return ImageInventorySearchResult(
              aiCriteria: null,
              criteria: criteria,
              matches: [
                {'id': 'keep-me', 'name': 'Saved First Item', 'price_est': 5000},
              ],
              usedFallback: false,
              embedding: const [0.1],
              resolvedMode: mode,
            );
          }
          photo2Attempts++;
          if (photo2Attempts == 1) {
            throw Exception('Temporary AI outage');
          }
          return ImageInventorySearchResult(
            aiCriteria: null,
            criteria: criteria,
            matches: [
              {
                'id': 'recovered-2',
                'name': 'Recovered Second Item',
                'price_est': 6000,
              },
            ],
            usedFallback: false,
            embedding: const [0.2],
            resolvedMode: mode,
          );
        };

        await tester.pumpWidget(
          _themed(
            SalesScreen(
              searchGateway: gateway,
              initialPhotos: [_testPhoto('p1'), _testPhoto('p2')],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _tapVisible(tester, find.text('Saved First Item'));
        await tester.tap(find.text('Hozzáadás és következő'));
        await tester.pumpAndSettle();

        expect(find.text('Fotó 2 / 2'), findsOneWidget);
        expect(find.text('Elemzés újrapróbálása'), findsOneWidget);

        await tester.tap(find.text('Elemzés újrapróbálása'));
        await tester.pumpAndSettle();
        expect(find.text('Recovered Second Item'), findsOneWidget);

        await _tapVisible(tester, find.text('Recovered Second Item'));
        await tester.tap(find.text('Párosítás kész'));
        await tester.pumpAndSettle();

        expect(find.text('2 tétel a kosárban'), findsOneWidget);
      },
    );
  });

  group('Sale submission & dark-screen prevention', () {
    testWidgets(
      'root SalesScreen resets to start screen after recording sale (never pops to dark screen)',
      (tester) async {
        var submitCount = 0;
        final submitCompleter = Completer<void>();

        await tester.pumpWidget(
          _themed(
            SalesScreen(
              initialItems: const [
                {
                  'id': 'item-1',
                  'name': 'Vintage Hoodie',
                  'category': 'hoodie',
                  'gender': 'férfi',
                  'price_est': 9000,
                  'location': 'Csengery',
                },
              ],
              onRecordSale: (params) {
                submitCount++;
                return submitCompleter.future;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tovább a véglegesítéshez'));
        await tester.pumpAndSettle();

        final recordButton = find.widgetWithText(
          FilledButton,
          'Eladás rögzítése',
        );
        await tester.ensureVisible(recordButton);
        await tester.tap(recordButton);
        await tester.pump();

        final savingButton = find.widgetWithText(
          FilledButton,
          'Eladás rögzítése…',
        );
        await tester.tap(savingButton, warnIfMissed: false);
        await tester.pump();
        expect(submitCount, 1);

        submitCompleter.complete();
        await tester.pumpAndSettle();

        expect(find.text('Fotók kiválasztása'), findsOneWidget);
        expect(find.text('Eladás sikeresen rögzítve!'), findsOneWidget);
      },
    );

    testWidgets('pushed SalesScreen pops with true after recording sale', (
      tester,
    ) async {
      bool? popResult;

      await tester.pumpWidget(
        _themed(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    popResult = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SalesScreen(
                          initialItems: const [
                            {
                              'id': 'item-1',
                              'name': 'Jacket',
                              'price_est': 12000,
                              'location': 'Astoria',
                            },
                          ],
                          onRecordSale: (_) async {},
                        ),
                      ),
                    );
                  },
                  child: const Text('Eladás megnyitása'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Eladás megnyitása'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tovább a véglegesítéshez'));
      await tester.pumpAndSettle();

      final recordButton = find.widgetWithText(
        FilledButton,
        'Eladás rögzítése',
      );
      await tester.ensureVisible(recordButton);
      await tester.tap(recordButton);
      await tester.pumpAndSettle();

      expect(popResult, isTrue);
      expect(find.text('Eladás megnyitása'), findsOneWidget);
    });
  });

  group('Back navigation in SalesScreen', () {
    testWidgets(
      'back arrow escapes 0-match photo search cleanly without getting trapped',
      (tester) async {
        final gateway = _TestGateway();

        await tester.pumpWidget(
          _themed(
            SalesScreen(
              searchGateway: gateway,
              initialPhotos: [_testPhoto('empty-photo')],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nem található eladatlan termék.'), findsOneWidget);
        final backButton = find.byIcon(Icons.arrow_back);
        expect(backButton, findsOneWidget);

        await tester.tap(backButton);
        await tester.pumpAndSettle();

        expect(find.text('Fotók kiválasztása'), findsOneWidget);
      },
    );

    testWidgets(
      'back arrow works while photo analysis is loading and cancels stale response',
      (tester) async {
        final gateway = _TestGateway();
        final pending = Completer<ImageInventorySearchResult>();
        gateway.onSearchByImage = (mode, criteria, sort, idx) => pending.future;

        await tester.pumpWidget(
          _themed(
            SalesScreen(
              searchGateway: gateway,
              initialPhotos: [_testPhoto('loading-photo')],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('Fotók kiválasztása'), findsOneWidget);

        pending.complete(
          const ImageInventorySearchResult(
            aiCriteria: null,
            criteria: InventorySearchCriteria(),
            matches: [],
            usedFallback: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Fotók kiválasztása'), findsOneWidget);
      },
    );

    testWidgets(
      'back arrow asks confirmation before discarding already matched items',
      (tester) async {
        await tester.pumpWidget(
          _themed(
            const SalesScreen(
              initialItems: [
                {'id': 'm-1', 'name': 'Matched Coat', 'price_est': 14000},
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1 tétel a kosárban'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        expect(find.text('Elveted ezt az eladást?'), findsOneWidget);

        await tester.tap(find.text('Maradok'));
        await tester.pumpAndSettle();
        expect(find.text('1 tétel a kosárban'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Elvetés'));
        await tester.pumpAndSettle();
        expect(find.text('Fotók kiválasztása'), findsOneWidget);
      },
    );
  });

  group('Standardized category-based search UI across screens', () {
    testWidgets(
      'manual search in SalesScreen, InventoryListScreen, and SearchScreen reuse InventorySearchView without image section',
      (tester) async {
        final gateway = _TestGateway();

        // 1. SalesScreen manual search
        await tester.pumpWidget(_themed(SalesScreen(searchGateway: gateway)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Keresés készletben'));
        await tester.pumpAndSettle();

        expect(find.byType(InventorySearchView), findsOneWidget);
        expect(find.text('Szűrők'), findsOneWidget);
        expect(find.text('Rendezés'), findsOneWidget);
        expect(find.text('Keresési mód'), findsNothing);
        expect(find.text('Manual Tee'), findsOneWidget);

        // 2. InventoryListScreen
        await tester.pumpWidget(
          _themed(
            InventoryListScreen(
              searchGateway: gateway,
              checkMissingEmbeddings: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(InventorySearchView), findsOneWidget);
        expect(find.text('Szűrők'), findsOneWidget);
        expect(find.text('Keresési mód'), findsNothing);
        expect(find.text('Manual Tee'), findsOneWidget);

        // 3. SearchScreen (manual, no image)
        await tester.pumpWidget(
          _themed(
            SearchScreen(
              key: const ValueKey('search-manual'),
              searchGateway: gateway,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(InventorySearchView), findsOneWidget);
        expect(find.text('Szűrők'), findsOneWidget);
        expect(find.text('Rendezés'), findsOneWidget);
        expect(find.text('Keresési mód'), findsNothing);
        expect(find.text('Manual Tee'), findsOneWidget);

        // 4. SearchScreen with image -> displays image & Keresési mód
        await tester.pumpWidget(
          _themed(
            SearchScreen(
              key: const ValueKey('search-with-image'),
              searchGateway: gateway,
              initialImage: _testPhoto('search-img'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(InventorySearchView), findsOneWidget);
        expect(find.text('Keresési mód'), findsOneWidget);

        // Tapping thumbnail opens full-screen InteractiveViewer dialog.
        await tester.tap(find.byIcon(Icons.zoom_in));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.tap(find.byTooltip('Bezárás'));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsNothing);

        // Folding photo section hides thumbnail & method dropdown.
        await tester.tap(find.byKey(const ValueKey('toggle-image-section')));
        await tester.pumpAndSettle();
        expect(find.text('Keresési mód'), findsNothing);
        expect(find.text('Mutat'), findsOneWidget);

        // Expanding it restores photo section.
        await tester.tap(find.byKey(const ValueKey('toggle-image-section')));
        await tester.pumpAndSettle();
        expect(find.text('Keresési mód'), findsOneWidget);
      },
    );

    testWidgets(
      'results grid fills remaining viewport height and folds top bars on scroll when not extended',
      (tester) async {
        await _setPhoneViewport(tester);
        final gateway = _TestGateway();
        gateway.onSearchByCriteria = (criteria, sortOption) async {
          return ImageInventorySearchResult(
            aiCriteria: null,
            criteria: criteria,
            matches: List.generate(
              16,
              (index) => {
                'id': 'scroll-$index',
                'name': 'Scrollable Item $index',
                'brand': 'Brand',
                'category': 'Póló',
                'gender': 'férfi',
                'price_est': 3000 + index * 100,
                'location': 'Csengery',
                'is_sold': false,
              },
            ),
            usedFallback: false,
          );
        };

        await tester.pumpWidget(
          _themed(
            InventoryListScreen(
              searchGateway: gateway,
              checkMissingEmbeddings: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scrollRect = tester.getRect(find.byType(CustomScrollView));
        expect(scrollRect.bottom, closeTo(932.0, 1.0));
        expect(scrollRect.height, greaterThan(800.0));
        expect(find.text('Szűrők'), findsOneWidget);

        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(find.text('Szűrők'), findsNothing);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(find.text('Szűrők'), findsOneWidget);

        await tester.tap(find.text('Szűrés'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(GridView), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(find.text('Szűrők'), findsOneWidget);
      },
    );
  });
}
