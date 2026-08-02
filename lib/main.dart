import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/di/providers.dart' as di_providers;
import 'core/theme/app_theme.dart';
import 'core/theme/theme_providers.dart';
import 'features/onboarding/providers/onboarding_provider.dart';
import 'features/onboarding/screens/onboarding_screen.dart'
    show OnboardingScreen;
import 'features/gallery/screens/gallery_home_screen.dart';
import 'core/logging/app_logger.dart';

/// Global error widget builder - replaces the red screen of death with a friendly UI.
/// Uses [AppLogger] to log the error for debugging.
Widget buildErrorWidget(FlutterErrorDetails details) {
  final logger = const ConsoleAppLogger();
  logger.error(
    'Flutter framework error caught by ErrorWidget.builder',
    error: details.exception,
    stackTrace: details.stack,
  );

  return Material(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'An unexpected error occurred. '
              'The error has been logged. Please try again or restart the app.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Restart App'),
              onPressed: () {
                // In a real app, you might use a restart mechanism
                // For now, just pop to try recovering
                logger.info('User tapped restart app from error screen');
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set global error widget builder BEFORE runApp
  ErrorWidget.builder = buildErrorWidget;

  // Pre-load SharedPreferences synchronously to prevent visual flickering
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        // Inject pre-loaded SharedPreferences into the provider from di_providers
        di_providers.sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AIGalleryApp(),
    ),
  );
}

class AIGalleryApp extends ConsumerWidget {
  const AIGalleryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final accentColor = ref.watch(accentColorProvider);
    final onboardingState = ref.watch(onboardingProvider);

    return MaterialApp(
      title: 'AI Gallery',
      debugShowCheckedModeBanner: false,

      // Dynamic Theme configurations
      theme: AppTheme.getThemeData(
        seedColor: accentColor,
        brightness: Brightness.light,
      ),
      darkTheme: AppTheme.getThemeData(
        seedColor: accentColor,
        brightness: Brightness.dark,
      ),
      themeMode: themeMode,

      // Root routing switcher based on onboarding completion status
      home: onboardingState.isCompleted
          ? const GalleryHomeScreen()
          : const OnboardingScreen(),
    );
  }
}
