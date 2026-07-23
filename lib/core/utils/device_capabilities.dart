import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detects device capabilities and recommends optimal ONNX model preset.
class DeviceCapabilities {
  /// Private constructor - use [detect] instead.
  const DeviceCapabilities._({
    required this.tier,
    required this.totalRamBytes,
    required this.cpuCores,
    required this.hasNpu,
    required this.apiLevel,
    required this.modelName,
    required this.recommendedModelPreset,
    required this.useGpuDelegate,
    required this.maxBatchSize,
    required this.performanceMultiplier,
  });

  /// Device performance tier.
  final DeviceTier tier;

  /// Total RAM in bytes.
  final int totalRamBytes;

  /// Number of CPU cores.
  final int cpuCores;

  /// Whether device has neural engine/NPU (Android NNAPI, iOS CoreML).
  final bool hasNpu;

  /// Android API level (or iOS version equivalent).
  final int apiLevel;

  /// Device model name.
  final String modelName;

  /// Recommended model preset for this device.
  final String recommendedModelPreset;

  /// Whether to use GPU delegate (if available).
  final bool useGpuDelegate;

  /// Maximum batch size for inference.
  final int maxBatchSize;

  /// Estimated inference time multiplier (1.0 = baseline).
  final double performanceMultiplier;

  /// Singleton instance cache.
  static DeviceCapabilities? _instance;

  /// Get singleton instance (detects on first call).
  static Future<DeviceCapabilities> get instance async {
    _instance ??= await detect();
    return _instance!;
  }

  /// Reset for testing.
  static void reset() => _instance = null;

  /// Detect device capabilities and select optimal model.
  static Future<DeviceCapabilities> detect() async {
    if (kIsWeb) {
      return _webDefaults();
    }

    if (Platform.isAndroid) {
      return _detectAndroid();
    } else if (Platform.isIOS) {
      return _detectIOS();
    } else {
      return _desktopDefaults();
    }
  }

  /// Android device detection.
  static Future<DeviceCapabilities> _detectAndroid() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    final totalRamBytes = _readTotalRam();
    final cpuCores = _getCpuCoreCount();
    final apiLevel = androidInfo.version.sdkInt;
    final modelName = '${androidInfo.manufacturer} ${androidInfo.model}';
    final hasNpu = apiLevel >= 27 && _hasNnapiSupport();

    final tier = _classifyTier(
      totalRamBytes: totalRamBytes,
      cpuCores: cpuCores,
      hasNpu: hasNpu,
      apiLevel: apiLevel,
    );

    final modelPreset = _selectModelPreset(tier);
    final useGpuDelegate = hasNpu && tier.index >= DeviceTier.medium.index;
    final (batchSize, perfMult) = _getPerfParams(tier);

    return DeviceCapabilities._(
      tier: tier,
      totalRamBytes: totalRamBytes,
      cpuCores: cpuCores,
      hasNpu: hasNpu,
      apiLevel: apiLevel,
      modelName: modelName,
      recommendedModelPreset: modelPreset,
      useGpuDelegate: useGpuDelegate,
      maxBatchSize: batchSize,
      performanceMultiplier: perfMult,
    );
  }

  /// iOS device detection.
  static Future<DeviceCapabilities> _detectIOS() async {
    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;

    final (ramBytes, tier) = _estimateIOSCapabilities(iosInfo.model);
    final cpuCores = _estimateIOSCpuCores(iosInfo.model);
    final hasNpu = _hasIOSNpu(iosInfo.model);
    final modelName = '${iosInfo.name} ${iosInfo.model}';
    final apiLevel = _parseIOSVersion(iosInfo.systemVersion);

    final modelPreset = _selectModelPreset(tier);
    final useGpuDelegate = hasNpu && tier.index >= DeviceTier.medium.index;
    final (batchSize, perfMult) = _getPerfParams(tier);

    return DeviceCapabilities._(
      tier: tier,
      totalRamBytes: ramBytes,
      cpuCores: cpuCores,
      hasNpu: hasNpu,
      apiLevel: apiLevel,
      modelName: modelName,
      recommendedModelPreset: modelPreset,
      useGpuDelegate: useGpuDelegate,
      maxBatchSize: batchSize,
      performanceMultiplier: perfMult,
    );
  }

  /// Desktop defaults (development).
  static DeviceCapabilities _desktopDefaults() {
    return DeviceCapabilities._(
      tier: DeviceTier.high,
      totalRamBytes: 16 * 1024 * 1024 * 1024,
      cpuCores: 8,
      hasNpu: false,
      apiLevel: 30,
      modelName: 'Desktop (Dev)',
      recommendedModelPreset: 'siglip-base-patch16-224',
      useGpuDelegate: false,
      maxBatchSize: 4,
      performanceMultiplier: 0.5,
    );
  }

  /// Web defaults.
  static DeviceCapabilities _webDefaults() {
    return DeviceCapabilities._(
      tier: DeviceTier.medium,
      totalRamBytes: 4 * 1024 * 1024 * 1024,
      cpuCores: 4,
      hasNpu: false,
      apiLevel: 0,
      modelName: 'Web Browser',
      recommendedModelPreset: 'mobileclip-s1',
      useGpuDelegate: false,
      maxBatchSize: 1,
      performanceMultiplier: 2.0,
    );
  }

  /// Read total RAM from /proc/meminfo (Linux/Android).
  static int _readTotalRam() {
    try {
      final file = File('/proc/meminfo');
      final contents = file.readAsStringSync();
      final match = RegExp(r'MemTotal:\s+(\d+)\s+kB').firstMatch(contents);
      if (match != null) {
        return int.parse(match.group(1)!) * 1024; // Convert kB to bytes
      }
    } catch (_) {
      // Ignore errors
    }
    return 4 * 1024 * 1024 * 1024; // Default 4GB
  }

  /// Get CPU core count.
  static int _getCpuCoreCount() {
    try {
      return Platform.numberOfProcessors;
    } catch (_) {
      return 4;
    }
  }

  /// Check if NNAPI is supported (API 27+).
  static bool _hasNnapiSupport() => true;

  /// Classify device tier based on specs.
  static DeviceTier _classifyTier({
    required int totalRamBytes,
    required int cpuCores,
    required bool hasNpu,
    required int apiLevel,
  }) {
    final ramGB = totalRamBytes / (1024 * 1024 * 1024);

    // Flagship criteria
    if (ramGB >= 8 && cpuCores >= 8 && hasNpu && apiLevel >= 30) {
      return DeviceTier.flagship;
    }

    // High-end
    if (ramGB >= 6 && cpuCores >= 6 && hasNpu && apiLevel >= 29) {
      return DeviceTier.high;
    }

    // Mid-range
    if (ramGB >= 3 && cpuCores >= 4 && apiLevel >= 28) {
      return DeviceTier.medium;
    }

    // Low-end
    return DeviceTier.low;
  }

  /// Select model preset based on device tier.
  static String _selectModelPreset(DeviceTier tier) {
    return switch (tier) {
      DeviceTier.low => 'mobileclip-s1',
      DeviceTier.medium => 'mobileclip-s2',
      DeviceTier.high => 'siglip-base-patch16-224',
      DeviceTier.flagship => 'siglip-base-patch16-256',
    };
  }

  /// Get batch size and performance multiplier for tier.
  static (int, double) _getPerfParams(DeviceTier tier) {
    return switch (tier) {
      DeviceTier.low => (1, 3.0),
      DeviceTier.medium => (1, 1.5),
      DeviceTier.high => (2, 1.0),
      DeviceTier.flagship => (4, 0.7),
    };
  }

  /// Estimate iOS RAM and tier from model identifier.
  static (int, DeviceTier) _estimateIOSCapabilities(String model) {
    // iPhone 13/14/15/16 series
    if (model.contains('iPhone15') || model.contains('iPhone16')) {
      return (6 * 1024 * 1024 * 1024, DeviceTier.high);
    }
    // iPhone 11/12 series
    if (model.contains('iPhone13') || model.contains('iPhone14')) {
      return (4 * 1024 * 1024 * 1024, DeviceTier.high);
    }
    // iPhone 8/X/XS/11 series
    if (model.contains('iPhone11') || model.contains('iPhone12')) {
      return (3 * 1024 * 1024 * 1024, DeviceTier.medium);
    }
    // iPhone 7/8/X
    if (model.contains('iPhone9') || model.contains('iPhone10')) {
      return (2 * 1024 * 1024 * 1024, DeviceTier.low);
    }
    // iPad Pro M1/M2
    if (model.contains('iPad13') || model.contains('iPad14')) {
      return (8 * 1024 * 1024 * 1024, DeviceTier.flagship);
    }
    // Other iPads
    if (model.contains('iPad')) {
      return (4 * 1024 * 1024 * 1024, DeviceTier.medium);
    }
    // Default
    return (3 * 1024 * 1024 * 1024, DeviceTier.medium);
  }

  /// Estimate iOS CPU cores from model.
  static int _estimateIOSCpuCores(String model) {
    if (model.contains('iPhone15') || model.contains('iPhone16')) return 8;
    if (model.contains('iPhone13') || model.contains('iPhone14')) return 6;
    if (model.contains('iPhone11') || model.contains('iPhone12')) return 6;
    if (model.contains('iPhone9') || model.contains('iPhone10')) return 6;
    if (model.contains('iPad13') || model.contains('iPad14')) return 8;
    return 4;
  }

  /// Check if iOS device has NPU (CoreML/Neural Engine).
  static bool _hasIOSNpu(String model) {
    // Neural Engine: A11 Bionic (iPhone 8/X) and later
    if (model.contains('iPhone10')) return true;
    if (model.contains('iPhone11')) return true;
    if (model.contains('iPhone12')) return true;
    if (model.contains('iPhone13')) return true;
    if (model.contains('iPhone14')) return true;
    if (model.contains('iPhone15')) return true;
    if (model.contains('iPhone16')) return true;
    if (model.contains('iPad13')) return true;
    if (model.contains('iPad14')) return true;
    return false;
  }

  /// Parse iOS version string to int (e.g., "17.2" -> 1702).
  static int _parseIOSVersion(String version) {
    final parts = version.split('.');
    final major = int.tryParse(parts[0]) ?? 15;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return major * 100 + minor;
  }

  @override
  String toString() {
    final ramGB = (totalRamBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
    return 'DeviceCapabilities('
        'tier: $tier, '
        'ram: ${ramGB}GB, '
        'cores: $cpuCores, '
        'npu: $hasNpu, '
        'model: $recommendedModelPreset, '
        'gpu: $useGpuDelegate, '
        'batch: $maxBatchSize, '
        'perf: ${performanceMultiplier.toStringAsFixed(1)}x'
        ')';
  }
}

/// Device performance tier.
enum DeviceTier {
  /// Low-end: < 3GB RAM, <= 4 cores, no NPU
  low,

  /// Mid-range: 3-6GB RAM, 4-6 cores, maybe NPU
  medium,

  /// High-end: 6-8GB RAM, 6-8 cores, NPU likely
  high,

  /// Flagship: > 8GB RAM, 8+ cores, NPU guaranteed
  flagship,
}