import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/di/providers.dart' as di_providers;
import '../../../core/services/model_downloader.dart';
import '../../../core/utils/device_capabilities.dart';

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
    final storageService = ref.watch(di_providers.storageServiceProvider);
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

  /// Actually request permission from the OS and update state.
  Future<void> requestPermission(String type) async {
    RequestType requestType;
    switch (type) {
      case 'camera':
        requestType = RequestType.image;
        break;
      case 'photos':
        requestType = RequestType.common;
        break;
      case 'microphone':
        requestType = RequestType.audio;
        break;
      default:
        return;
    }

    final result = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: requestType,
          mediaLocation: true,
        ),
      ),
    );
    final granted = result.isAuth || result == PermissionState.limited;

    switch (type) {
      case 'camera':
        state = state.copyWith(cameraPermissionGranted: granted);
        break;
      case 'photos':
        state = state.copyWith(photosPermissionGranted: granted);
        break;
      case 'microphone':
        state = state.copyWith(microphonePermissionGranted: granted);
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
    final storageService = ref.read(di_providers.storageServiceProvider);
    await storageService.setOnboardingCompleted(true);
    await storageService.setCloudBackupEnabled(state.storageMode == 'cloud');
    if (state.customStoragePath != null) {
      await storageService.setStoragePath(state.customStoragePath!);
    }
    state = state.copyWith(isCompleted: true, currentStep: 5);

    // Download default model in background without blocking onboarding UX.
    // Uses unawaited with proper error handling; not `void async`.
    _downloadDefaultModelWithGuard();
  }

  void _downloadDefaultModelWithGuard() {
    // ignore: discarded_futures
    _downloadDefaultModel().catchError((Object e, StackTrace st) {
      final logger = ref.read(di_providers.appLoggerProvider);
      logger.warning('Failed to download default model', error: e, stackTrace: st);
    });
  }

  Future<void> _downloadDefaultModel() async {
    // Determine the right model for this device tier
    final capabilities = await DeviceCapabilities.instance;
    final presetName = capabilities.recommendedModelPreset;
    final preset = ModelPresets.presets[presetName];
    if (preset == null) {
      final logger = ref.read(di_providers.appLoggerProvider);
      logger.warning('No model preset found for tier ${capabilities.tier.name}');
      return;
    }

    final result = await ref.read(di_providers.modelDownloaderProvider).downloadModelConfig(
      preset,
      progressCallback: (progress) {
        // Could update UI with progress if needed
      },
    );
    if (!result.isSuccess) {
      final logger = ref.read(di_providers.appLoggerProvider);
      logger.warning('Failed to download default model ($presetName): ${result.errorMessage}');
    }
  }

  Future<void> resetOnboarding() async {
    final storageService = ref.read(di_providers.storageServiceProvider);
    await storageService.setOnboardingCompleted(false);
    state = OnboardingState(isCompleted: false, currentStep: 1);
  }
}

final onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(OnboardingNotifier.new);