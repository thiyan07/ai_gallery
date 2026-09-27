import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:ai_gallery/core/utils/thumbnail_utils.dart';

void main() {
  group('ThumbnailSizes.forGrid', () {
    testWidgets('scales with columns and pixel ratio', (tester) async {
      ThumbnailSize? captured;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800), devicePixelRatio: 2.0),
          child: Builder(
            builder: (context) {
              captured = ThumbnailSizes.forGrid(context, 4);
              return const SizedBox();
            },
          ),
        ),
      );
      // (400 - 2*3) / 4 = 98.5 css px × 2 dpr ≈ 197
      expect(captured!.width, inInclusiveRange(190, 205));
      expect(captured!.width, captured!.height);
    });

    testWidgets('clamps tiny and huge requests', (tester) async {
      ThumbnailSize? tiny;
      ThumbnailSize? huge;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800), devicePixelRatio: 1.0),
          child: Builder(
            builder: (context) {
              tiny = ThumbnailSizes.forGrid(context, 12);
              huge = ThumbnailSizes.forGrid(context, 1);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(tiny!.width, 80);
      expect(huge!.width, 400);
    });
  });
}
