import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/scanner/application/scanner_controller.dart';
import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';

void main() {
  final dummyBytes = Uint8List.fromList([0, 1, 2]);
  final corners = DocumentCorners.fullFrame(const Size(100, 100));

  late ScannerController ctrl;

  setUp(() {
    ctrl = ScannerController();
  });

  group('ScannerController - initial state', () {
    test('starts in capturing stage with no pages', () {
      expect(ctrl.state.stage, equals(ScanStage.capturing));
      expect(ctrl.state.pages, isEmpty);
      expect(ctrl.state.hasPages, isFalse);
      expect(ctrl.state.pageCount, equals(0));
    });

    test('initial OCR state is idle', () {
      expect(ctrl.state.recognizedText, isEmpty);
      expect(ctrl.state.ocrProgressIndex, equals(-1));
      expect(ctrl.state.searchablePdf, isTrue);
      expect(ctrl.state.isOcrRunning, isFalse);
    });
  });

  group('ScannerController - goToTextDetection', () {
    test('transitions stage to textDetection', () {
      // First add a page and go to review
      ctrl.addCapture(dummyBytes, corners);
      ctrl.confirmCrop();
      expect(ctrl.state.stage, equals(ScanStage.reviewing));

      ctrl.goToTextDetection();
      expect(ctrl.state.stage, equals(ScanStage.textDetection));
    });

    test('clears active index when entering text detection', () {
      ctrl.addCapture(dummyBytes, corners);
      // activeIndex should be 0 after addCapture
      expect(ctrl.state.activeIndex, equals(0));

      ctrl.goToTextDetection();
      expect(ctrl.state.activeIndex, isNull);
    });
  });

  group('ScannerController - setPageOcrText', () {
    test('stores OCR text for a specific page', () {
      final page = ctrl.addCapture(dummyBytes, corners);
      ctrl.setPageOcrText(page.id, 'Hello World');

      final updatedPage =
          ctrl.state.pages.firstWhere((p) => p.id == page.id);
      expect(updatedPage.extractedText, equals('Hello World'));
      expect(updatedPage.ocrProcessing, isFalse);
    });

    test('rebuilds recognizedText from all pages', () {
      final page1 = ctrl.addCapture(dummyBytes, corners);
      ctrl.confirmCrop();
      ctrl.resumeCapture();
      final page2 = ctrl.addCapture(dummyBytes, corners);

      ctrl.setPageOcrText(page1.id, 'Page one text');
      ctrl.setPageOcrText(page2.id, 'Page two text');

      expect(ctrl.state.recognizedText, contains('Page one text'));
      expect(ctrl.state.recognizedText, contains('Page two text'));
      expect(ctrl.state.recognizedText, contains('--- Page 1 ---'));
      expect(ctrl.state.recognizedText, contains('--- Page 2 ---'));
    });

    test('skips pages with no text in recognizedText', () {
      final page1 = ctrl.addCapture(dummyBytes, corners);
      ctrl.confirmCrop();
      ctrl.resumeCapture();
      ctrl.addCapture(dummyBytes, corners);

      ctrl.setPageOcrText(page1.id, 'Only first page');
      // Page 2 has no text set
      expect(ctrl.state.recognizedText, contains('--- Page 1 ---'));
      expect(ctrl.state.recognizedText, isNot(contains('--- Page 2 ---')));
    });
  });

  group('ScannerController - OCR progress', () {
    test('setOcrProgress updates the progress index', () {
      ctrl.setOcrProgress(0);
      expect(ctrl.state.ocrProgressIndex, equals(0));
      expect(ctrl.state.isOcrRunning, isTrue);

      ctrl.setOcrProgress(2);
      expect(ctrl.state.ocrProgressIndex, equals(2));
    });

    test('finishOcr resets progress index to -1', () {
      ctrl.setOcrProgress(3);
      ctrl.finishOcr();
      expect(ctrl.state.ocrProgressIndex, equals(-1));
      expect(ctrl.state.isOcrRunning, isFalse);
    });
  });

  group('ScannerController - markOcrProcessing', () {
    test('marks a page as currently processing OCR', () {
      final page = ctrl.addCapture(dummyBytes, corners);
      ctrl.markOcrProcessing(page.id, true);

      final updated =
          ctrl.state.pages.firstWhere((p) => p.id == page.id);
      expect(updated.ocrProcessing, isTrue);
    });

    test('can unmark OCR processing', () {
      final page = ctrl.addCapture(dummyBytes, corners);
      ctrl.markOcrProcessing(page.id, true);
      ctrl.markOcrProcessing(page.id, false);

      final updated =
          ctrl.state.pages.firstWhere((p) => p.id == page.id);
      expect(updated.ocrProcessing, isFalse);
    });
  });

  group('ScannerController - clearOcr', () {
    test('clears extractedText from all pages', () {
      final page1 = ctrl.addCapture(dummyBytes, corners);
      ctrl.confirmCrop();
      ctrl.resumeCapture();
      final page2 = ctrl.addCapture(dummyBytes, corners);

      ctrl.setPageOcrText(page1.id, 'text1');
      ctrl.setPageOcrText(page2.id, 'text2');

      ctrl.clearOcr();

      for (final p in ctrl.state.pages) {
        expect(p.extractedText, isNull);
      }
    });

    test('resets recognizedText to empty', () {
      final page = ctrl.addCapture(dummyBytes, corners);
      ctrl.setPageOcrText(page.id, 'some text');
      expect(ctrl.state.recognizedText, isNotEmpty);

      ctrl.clearOcr();
      expect(ctrl.state.recognizedText, isEmpty);
    });

    test('resets ocrProgressIndex to -1', () {
      ctrl.setOcrProgress(2);
      ctrl.clearOcr();
      expect(ctrl.state.ocrProgressIndex, equals(-1));
    });
  });

  group('ScannerController - toggleSearchablePdf', () {
    test('toggles searchablePdf from true to false', () {
      expect(ctrl.state.searchablePdf, isTrue);
      ctrl.toggleSearchablePdf();
      expect(ctrl.state.searchablePdf, isFalse);
    });

    test('toggles searchablePdf from false to true', () {
      ctrl.toggleSearchablePdf(); // true -> false
      ctrl.toggleSearchablePdf(); // false -> true
      expect(ctrl.state.searchablePdf, isTrue);
    });
  });

  group('ScannerController - stage transitions flow', () {
    test('full flow: capture -> crop -> review -> textDetection -> review', () {
      // Start capturing
      expect(ctrl.state.stage, equals(ScanStage.capturing));

      // Capture a page
      ctrl.addCapture(dummyBytes, corners);
      expect(ctrl.state.stage, equals(ScanStage.cropping));

      // Confirm crop -> go to review
      ctrl.confirmCrop();
      expect(ctrl.state.stage, equals(ScanStage.reviewing));

      // Enter text detection
      ctrl.goToTextDetection();
      expect(ctrl.state.stage, equals(ScanStage.textDetection));

      // Go back to review
      ctrl.goToReview();
      expect(ctrl.state.stage, equals(ScanStage.reviewing));
    });

    test('can resume capture from any stage', () {
      ctrl.addCapture(dummyBytes, corners);
      ctrl.confirmCrop();
      ctrl.goToTextDetection();

      ctrl.resumeCapture();
      expect(ctrl.state.stage, equals(ScanStage.capturing));
    });
  });

  group('ScannerController - ScannerState.isOcrRunning', () {
    test('returns false when ocrProgressIndex is -1', () {
      expect(ctrl.state.isOcrRunning, isFalse);
    });

    test('returns true when ocrProgressIndex >= 0', () {
      ctrl.setOcrProgress(0);
      expect(ctrl.state.isOcrRunning, isTrue);
    });
  });

  group('ScannerController - reset clears OCR state', () {
    test('reset clears all OCR-related state', () {
      final page = ctrl.addCapture(dummyBytes, corners);
      ctrl.setPageOcrText(page.id, 'text');
      ctrl.setOcrProgress(1);
      ctrl.toggleSearchablePdf(); // false

      ctrl.reset();

      expect(ctrl.state.pages, isEmpty);
      expect(ctrl.state.recognizedText, isEmpty);
      expect(ctrl.state.ocrProgressIndex, equals(-1));
      expect(ctrl.state.searchablePdf, isTrue);
      expect(ctrl.state.stage, equals(ScanStage.capturing));
    });
  });
}
