import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/core/theme/theme_providers.dart' as theme_providers;
import 'package:ai_gallery/core/di/providers.dart' as di_providers;
import 'package:ai_gallery/core/storage/storage_service.dart';
import 'package:ai_gallery/core/services/model_manager.dart';
import 'package:ai_gallery/core/services/model_downloader.dart';
import 'package:ai_gallery/core/logging/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AIGalleryApp displays Onboarding screen by default', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final logger = const ConsoleAppLogger();
    final storageService = StorageService(prefs);
    final modelDownloader = ModelDownloader(logger: logger);
    final modelManager = ModelManager(downloader: modelDownloader, logger: logger);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Providers used by main.dart (theme providers)
          theme_providers.sharedPreferencesProvider.overrideWithValue(prefs),
          theme_providers.storageServiceProvider.overrideWithValue(storageService),
          // Providers used by onboarding_provider.dart
          di_providers.storageServiceProvider.overrideWithValue(storageService),
          di_providers.modelManagerProvider.overrideWithValue(modelManager),
          di_providers.modelDownloaderProvider.overrideWithValue(modelDownloader),
          di_providers.appLoggerProvider.overrideWithValue(logger),
        ],
        child: const AIGalleryApp(),
      ),
    );

    // Wait for all frames and animations to complete
    await tester.pumpAndSettle();

    // Debug: print all texts found
    final allTexts = tester.widgetList(find.byType(Text));
    print('Found ${allTexts.length} Text widgets');
    for (final widget in allTexts) {
      final textWidget = widget as Text;
      if (textWidget.data != null) {
        print('  Text: "${textWidget.data}"');
      }
    }

    // Verify Onboarding wizard starts at Step 1 (Welcome page)
    expect(find.text('AI Gallery'), findsOneWidget);
    expect(
      find.text('Smart AI photo gallery for your memories.'),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsOneWidget);

    // Verify Navigation Rail or Bottom bar is not shown during onboarding
    expect(find.text('Gallery'), findsNothing);
    expect(find.text('Albums'), findsNothing);
  });
}