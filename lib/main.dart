import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_providers.dart';
import 'features/onboarding/providers/onboarding_provider.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'features/gallery/screens/gallery_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Pre-load SharedPreferences synchronously to prevent visual flickering
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        // Inject pre-loaded SharedPreferences into the provider
        sharedPreferencesProvider.overrideWithValue(prefs),
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
