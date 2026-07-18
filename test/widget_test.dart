import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/core/theme/theme_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AIGalleryApp displays Onboarding screen by default', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const AIGalleryApp(),
      ),
    );

    // Re-render and wait for animations
    await tester.pumpAndSettle();

    // Verify Onboarding wizard starts at Step 1 (Welcome page)
    expect(find.text('AI Gallery'), findsOneWidget);
    expect(find.text('Smart AI photo gallery for your memories.'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Verify Navigation Rail or Bottom bar is not shown during onboarding
    expect(find.text('Gallery'), findsNothing);
    expect(find.text('Albums'), findsNothing);
  });
}
