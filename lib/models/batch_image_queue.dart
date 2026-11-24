import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class QueueItem {
  static const int maxAnalysisAttempts = 3;

  final XFile image;
  late final Future<Uint8List> bytes;
  Map<String, dynamic>? aiResult;
  String? aiModel;

  bool isAnalyzing = false;
  bool isReady = false;
  int analysisAttempts = 0;
  bool failedAfterRetries = false;

  QueueItem(this.image) {
    bytes = image.readAsBytes();
  }
}

class BatchImageQueue {
  final List<QueueItem> items;

  int currentIndex = 0;

  BatchImageQueue(this.items);

  bool get hasNext => currentIndex < items.length;

  QueueItem get current => items[currentIndex];

  int get total => items.length;

  int get currentNumber => currentIndex + 1;

  void moveNext() {
    currentIndex++;
  }

  /// Moves [item] to the end of the remaining queue so it will be retried after
  /// the other pending items. Returns `true` if another item is now in its slot.
  bool requeueItem(QueueItem item) {
    final index = items.indexOf(item);
    if (index < currentIndex || index < 0 || index == items.length - 1) {
      return false;
    }
    items.removeAt(index);
    items.add(item);
    return true;
  }

  void reset() {
    currentIndex = 0;
  }
}
