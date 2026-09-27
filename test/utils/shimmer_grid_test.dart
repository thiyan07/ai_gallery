import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/core/widgets/shimmer_grid.dart';

void main() {
  group('ShimmerGrid', () {
    testWidgets('renders the expected number of skeleton tiles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ShimmerGrid(columns: 3, itemCount: 9),
            ),
          ),
        ),
      );
      await tester.pump();
      // 9 skeleton tiles, no spinner.
      expect(find.byType(DecoratedBox), findsNWidgets(9));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
