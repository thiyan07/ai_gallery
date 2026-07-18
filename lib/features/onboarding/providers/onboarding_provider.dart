import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_providers.dart';

class OnboardingState {
  final int currentStep;
  final bool cameraPermissionGranted;
  final bool photosPermissionGranted;
  final bool microphonePermissionGranted;
  final String storageMode; // 'local' or 'cloud'
  final String? customStoragePath;
  final bool isCompleted;

  OnboardingState({
    this.currentStep = 1,
    this.cameraPermissionGranted = false,
    this.photosPermissionGranted = false,
    this.microphonePermissionGranted = false,
    this.storageMode = 'local',
    this.customStoragePath,
    this.isCompleted = false,
  });

  OnboardingState copyWith({
    int? currentStep,
    bool? cameraPermissionGranted,
    bool? photosPermissionGranted,
    bool? microphonePermissionGranted,
    String? storageMode,
    String? customStoragePath,
    bool? isCompleted,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      cameraPermissionGranted: cameraPermissionGranted ?? this.cameraPermissionGranted,
      photosPermissionGranted: photosPermissionGranted ?? this.photosPermissionGranted,
      microphonePermissionGranted: microphonePermissionGranted ?? this.microphonePermissionGranted,
      storageMode: storageMode ?? this.storageMode,
      customStoragePath: customStoragePath ?? this.customStoragePath,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    final storageService = ref.watch(storageServiceProvider);
    final completed = storageService.isOnboardingCompleted();
    final cloudBackup = storageService.isCloudBackupEnabled();
    final path = storageService.getStoragePath();
    return OnboardingState(
      isCompleted: completed,
      storageMode: cloudBackup ? 'cloud' : 'local',
      customStoragePath: path,
    );
  }

  void setStep(int step) {
    if (step >= 1 && step <= 5) {
      state = state.copyWith(currentStep: step);
    }
  }

  void togglePermission(String type) {
    switch (type) {
      case 'camera':
        state = state.copyWith(cameraPermissionGranted: !state.cameraPermissionGranted);
        break;
      case 'photos':
        state = state.copyWith(photosPermissionGranted: !state.photosPermissionGranted);
        break;
      case 'microphone':
        state = state.copyWith(microphonePermissionGranted: !state.microphonePermissionGranted);
        break;
    }
  }

  void setStorageMode(String mode) {
    state = state.copyWith(storageMode: mode);
  }

  void setCustomStoragePath(String? path) {
    state = state.copyWith(customStoragePath: path);
  }

  Future<void> completeOnboarding() async {
    final storageService = ref.read(storageServiceProvider);
    await storageService.setOnboardingCompleted(true);
    await storageService.setCloudBackupEnabled(state.storageMode == 'cloud');
    if (state.customStoragePath != null) {
      await storageService.setStoragePath(state.customStoragePath!);
    }
    state = state.copyWith(isCompleted: true, currentStep: 5);
  }

  Future<void> resetOnboarding() async {
    final storageService = ref.read(storageServiceProvider);
    await storageService.setOnboardingCompleted(false);
    state = OnboardingState(isCompleted: false, currentStep: 1);
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(OnboardingNotifier.new);
