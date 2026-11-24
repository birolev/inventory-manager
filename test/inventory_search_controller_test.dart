import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoaron_app/controllers/inventory_search_controller.dart';
import 'package:yoaron_app/services/image_inventory_search.dart';
import 'package:yoaron_app/services/inventory_search.dart';

class _RecordedImageCall {
  _RecordedImageCall({
    required this.mode,
    required this.criteria,
    required this.sortOption,
  });

  final ImageSearchMode mode;
  final InventorySearchCriteria criteria;
  final InventorySortOption sortOption;
}

class _FakeGateway implements InventorySearchGateway {
  final List<_RecordedImageCall> imageCalls = [];
  final List<InventorySearchCriteria> embeddingFilterCalls = [];
  final List<InventorySearchCriteria> criteriaCalls = [];

  Future<ImageInventorySearchResult> Function(
    ImageSearchMode mode,
    InventorySearchCriteria criteria,
    InventorySortOption sortOption,
  )?
  onSearchByImage;

  Future<ImageInventorySearchResult> Function(
    List<num> embedding,
    InventorySearchCriteria criteria,
    InventorySortOption sortOption,
  )?
  onSearchByExistingEmbedding;

  Future<ImageInventorySearchResult> Function(
    InventorySearchCriteria criteria,
    InventorySortOption sortOption,
    bool allowFallback,
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
    imageCalls.add(
      _RecordedImageCall(
        mode: mode,
        criteria: criteria,
        sortOption: sortOption,
      ),
    );
    return onSearchByImage!(mode, criteria, sortOption);
  }

  @override
  Future<ImageInventorySearchResult> searchByExistingEmbedding({
    required List<num> embedding,
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
  }) {
    embeddingFilterCalls.add(criteria);
    return onSearchByExistingEmbedding!(embedding, criteria, sortOption);
  }

  @override
  Future<ImageInventorySearchResult> searchByCriteria({
    required InventorySearchCriteria criteria,
    required InventorySortOption sortOption,
    bool allowFallback = true,
  }) {
    criteriaCalls.add(criteria);
    return onSearchByCriteria!(criteria, sortOption, allowFallback);
  }
}

SearchImageInput _dummyImage(String id) => SearchImageInput(
  id: id,
  mimeType: 'image/jpeg',
  initialBytes: Uint8List.fromList([1, 2, 3, 4]),
);

void main() {
  group('InventorySearchController mode switching & state isolation', () {
    test(
      'switching from Gemini to Embedded performs a full state reset and passes zero stale filters',
      () async {
        final gateway = _FakeGateway();
        var selectionResets = 0;

        gateway.onSearchByImage = (mode, criteria, sortOption) async {
          if (mode == ImageSearchMode.gemini) {
            return ImageInventorySearchResult(
              aiCriteria: const {
                'category': 'hoodie',
                'gender': 'férfi',
                'color': 'kék',
                'pattern': 'logo',
              },
              criteria: const InventorySearchCriteria(
                category: 'hoodie',
                gender: 'férfi',
                location: 'Csengery',
                size: 'L',
                color: 'kék',
                pattern: 'logo',
                brand: 'Nike',
                name: 'Tech Fleece',
                condition: 'good',
                onlyUnsold: true,
              ),
              matches: [
                {
                  'id': 'gem-1',
                  'name': 'Gemini Hoodie',
                  'category': 'hoodie',
                  'price_est': 12000,
                },
              ],
              usedFallback: true,
              resolvedMode: ImageSearchMode.gemini,
            );
          }
          return ImageInventorySearchResult(
            aiCriteria: null,
            criteria: criteria,
            matches: [
              {
                'id': 'vec-1',
                'name': 'Vector Item',
                'category': 'Póló',
                'price_est': 3000,
                'similarity': 0.92,
              },
            ],
            usedFallback: false,
            embedding: const [0.1, 0.2, 0.3],
            resolvedMode: ImageSearchMode.embedded,
          );
        };

        final controller = InventorySearchController(
          initialSearchMode: ImageSearchMode.gemini,
          initialImage: _dummyImage('img-1'),
          gateway: gateway,
          onSelectionReset: () => selectionResets++,
        );

        await controller.analyzeImage();
        expect(controller.selectedCategory, 'hoodie');
        expect(controller.selectedGender, 'férfi');
        expect(controller.selectedLocation, 'Csengery');
        expect(controller.sizeFilter, 'L');
        expect(controller.colorFilter, 'kék');
        expect(controller.patternFilter, 'logo');
        expect(controller.brandFilter, 'Nike');
        expect(controller.nameFilter, 'Tech Fleece');
        expect(controller.conditionFilter, 'good');
        expect(controller.usedFallback, isTrue);
        expect(controller.aiCriteria, isNotNull);

        await controller.setSortOption(InventorySortOption.priceDesc);
        expect(controller.sortOption, InventorySortOption.priceDesc);

        // Switch from Gemini -> Embedded vectors.
        final revisionBeforeSwitch = controller.filterRevision;
        await controller.switchSearchMode(ImageSearchMode.embedded);

        expect(selectionResets, 1);
        expect(controller.searchMode, ImageSearchMode.embedded);
        expect(controller.filterRevision, greaterThan(revisionBeforeSwitch));
        expect(controller.selectedCategory, 'Minden');
        expect(controller.selectedGender, 'Minden');
        expect(controller.selectedLocation, 'All locations');
        expect(controller.sizeFilter, '');
        expect(controller.colorFilter, '');
        expect(controller.patternFilter, '');
        expect(controller.brandFilter, '');
        expect(controller.nameFilter, '');
        expect(controller.conditionFilter, '');
        expect(controller.aiCriteria, isNull);
        expect(controller.usedFallback, isFalse);
        expect(controller.sortOption, InventorySortOption.relevance);
        expect(controller.results.map((e) => e['id']).toList(), ['vec-1']);

        // Verify the embedded call received completely clean criteria.
        final embeddedCall = gateway.imageCalls.last;
        expect(embeddedCall.mode, ImageSearchMode.embedded);
        expect(embeddedCall.criteria.category, 'Minden');
        expect(embeddedCall.criteria.gender, 'Minden');
        expect(embeddedCall.criteria.location, 'All locations');
        expect(embeddedCall.criteria.color, '');
        expect(embeddedCall.criteria.pattern, '');
        expect(embeddedCall.criteria.brand, '');

        controller.dispose();
      },
    );

    test(
      'stale async response from a previous search mode cannot overwrite newer results',
      () async {
        final gateway = _FakeGateway();
        final slowGeminiCompleter = Completer<ImageInventorySearchResult>();

        gateway.onSearchByImage = (mode, criteria, sortOption) {
          if (mode == ImageSearchMode.gemini) {
            return slowGeminiCompleter.future;
          }
          return Future.value(
            ImageInventorySearchResult(
              aiCriteria: null,
              criteria: criteria,
              matches: [
                {'id': 'fresh-vec', 'name': 'Fresh Vector', 'price_est': 4500},
              ],
              usedFallback: false,
              embedding: const [0.4, 0.5],
              resolvedMode: ImageSearchMode.embedded,
            ),
          );
        };

        final controller = InventorySearchController(
          initialSearchMode: ImageSearchMode.gemini,
          initialImage: _dummyImage('img-race'),
          gateway: gateway,
        );

        // Kick off slow Gemini request without awaiting.
        final geminiFuture = controller.analyzeImage();
        expect(controller.isLoading, isTrue);

        // User switches to Embedded while Gemini is still in flight.
        await controller.switchSearchMode(ImageSearchMode.embedded);
        expect(controller.searchMode, ImageSearchMode.embedded);
        expect(controller.isLoading, isFalse);
        expect(controller.results.map((e) => e['id']).toList(), ['fresh-vec']);

        // Now the stale Gemini request resolves late!
        slowGeminiCompleter.complete(
          const ImageInventorySearchResult(
            aiCriteria: {'category': 'dzseki', 'color': 'piros'},
            criteria: InventorySearchCriteria(
              category: 'dzseki',
              color: 'piros',
            ),
            matches: [
              {'id': 'stale-gem', 'name': 'Stale Gemini', 'price_est': 99000},
            ],
            usedFallback: false,
            resolvedMode: ImageSearchMode.gemini,
          ),
        );
        await geminiFuture;

        // State must STILL reflect the newer Embedded search!
        expect(controller.searchMode, ImageSearchMode.embedded);
        expect(controller.selectedCategory, 'Minden');
        expect(controller.colorFilter, '');
        expect(controller.aiCriteria, isNull);
        expect(controller.results.map((e) => e['id']).toList(), ['fresh-vec']);

        controller.dispose();
      },
    );

    test(
      'changing sort never triggers image analysis or embedding generation and sorts strictly',
      () async {
        final gateway = _FakeGateway();
        gateway.onSearchByImage = (mode, criteria, sortOption) async {
          return ImageInventorySearchResult(
            aiCriteria: null,
            criteria: criteria,
            matches: [
              {
                'id': '1',
                'price_est': '30 000 Ft',
                'similarity': 0.99,
                'created_at': '2026-01-01T00:00:00Z',
              },
              {
                'id': '2',
                'price_est': 3000,
                'similarity': 0.90,
                'created_at': '2026-03-01T00:00:00Z',
              },
              {
                'id': '3',
                'price_est': '2500',
                'similarity': 0.85,
                'created_at': '2026-02-01T00:00:00Z',
              },
              {
                'id': '4',
                'price_est': null,
                'similarity': 0.80,
                'created_at': '2026-04-01T00:00:00Z',
              },
            ],
            usedFallback: false,
            embedding: const [1, 2, 3],
            resolvedMode: ImageSearchMode.embedded,
          );
        };
        gateway.onSearchByExistingEmbedding =
            (embedding, criteria, sortOption) async {
              return ImageInventorySearchResult(
                aiCriteria: null,
                criteria: criteria,
                matches: [
                  {'id': '2', 'price_est': 3000, 'similarity': 0.90},
                  {'id': '1', 'price_est': '30 000 Ft', 'similarity': 0.99},
                ],
                usedFallback: false,
                embedding: embedding,
                resolvedMode: ImageSearchMode.embedded,
              );
            };

        final controller = InventorySearchController(
          initialSearchMode: ImageSearchMode.embedded,
          initialImage: _dummyImage('img-sort'),
          gateway: gateway,
        );

        await controller.analyzeImage();
        expect(gateway.imageCalls.length, 1);
        expect(controller.results.map((e) => e['id']).toList(), [
          '1',
          '2',
          '3',
          '4',
        ]);

        await controller.setSortOption(InventorySortOption.priceAsc);
        expect(controller.results.map((e) => e['id']).toList(), [
          '3',
          '2',
          '1',
          '4',
        ]);

        await controller.setSortOption(InventorySortOption.priceDesc);
        expect(controller.results.map((e) => e['id']).toList(), [
          '1',
          '2',
          '3',
          '4',
        ]);

        await controller.setSortOption(InventorySortOption.newest);
        expect(controller.results.map((e) => e['id']).toList(), [
          '4',
          '2',
          '3',
          '1',
        ]);

        // Zero additional image analysis or embedding calls!
        expect(gateway.imageCalls.length, 1);
        expect(gateway.embeddingFilterCalls.length, 0);
        expect(gateway.criteriaCalls.length, 0);

        // Changing category in embedded mode reuses cached embedding (no new image call!).
        await controller.setSortOption(InventorySortOption.priceAsc);
        await controller.setCategory('hoodie');
        expect(gateway.imageCalls.length, 1);
        expect(gateway.embeddingFilterCalls.length, 1);
        expect(controller.results.map((e) => e['id']).toList(), ['2', '1']);

        controller.dispose();
      },
    );
  });
}
