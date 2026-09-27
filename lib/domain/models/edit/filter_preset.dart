/// Defines a filter preset with specific parameter adjustments.
///
/// Filters work by applying a combination of parameter offsets to the image.
/// Each preset defines small, tasteful adjustments that combine to create
/// a cohesive visual style.
///
/// Filter presets are immutable and deterministic — the same preset always
/// produces the same result on the same input.
class FilterPreset {
  final String id;
  final String name;
  final String category;
  final Map<String, double> adjustments;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.adjustments,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'adjustments': adjustments,
      };

  factory FilterPreset.fromMap(Map<String, dynamic> map) => FilterPreset(
        id: map['id'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        adjustments: Map<String, double>.from(map['adjustments'] as Map),
      );
}

/// Curated collection of tasteful filter presets.
///
/// Each preset is designed to produce a genuinely different visual style.
/// Adjustments are small and deliberate — not just copied values.
class FilterPresets {
  FilterPresets._();

  static const List<FilterPreset> all = [
    // --- NATURAL ---
    natural,
    warm,
    cool,

    // --- PORTRAIT ---
    softPortrait,
    portraitWarm,
    portraitCool,

    // --- CINEMATIC ---
    cinematic,
    tealCinematic,
    moodyCinematic,

    // --- BLACK & WHITE ---
    classicBw,
    highContrastBw,
    softBw,

    // --- VINTAGE ---
    vintage,
    faded,
    retro,

    // --- VIBRANT ---
    vibrant,
    pop,
    rich,
  ];

  static const natural = FilterPreset(
    id: 'natural',
    name: 'Natural',
    category: 'Natural',
    adjustments: {
      'contrast': 0.08,
      'saturation': 0.05,
      'clarity': 0.1,
      'vibrance': 0.08,
    },
  );

  static const warm = FilterPreset(
    id: 'warm',
    name: 'Warm',
    category: 'Natural',
    adjustments: {
      'temperature': 0.18,
      'saturation': 0.08,
      'brightness': 0.04,
      'contrast': 0.05,
      'highlights': 0.06,
    },
  );

  static const cool = FilterPreset(
    id: 'cool',
    name: 'Cool',
    category: 'Natural',
    adjustments: {
      'temperature': -0.18,
      'saturation': -0.04,
      'brightness': 0.02,
      'contrast': 0.06,
      'shadows': 0.05,
    },
  );

  // --- PORTRAIT ---

  static const softPortrait = FilterPreset(
    id: 'soft_portrait',
    name: 'Soft Portrait',
    category: 'Portrait',
    adjustments: {
      'brightness': 0.06,
      'contrast': -0.08,
      'highlights': 0.1,
      'shadows': 0.12,
      'clarity': -0.1,
      'saturation': -0.06,
      'vibrance': 0.06,
      'vignette': -0.15,
    },
  );

  static const portraitWarm = FilterPreset(
    id: 'portrait_warm',
    name: 'Portrait Warm',
    category: 'Portrait',
    adjustments: {
      'temperature': 0.12,
      'brightness': 0.04,
      'contrast': -0.06,
      'highlights': 0.08,
      'shadows': 0.1,
      'saturation': 0.04,
      'vibrance': 0.08,
    },
  );

  static const portraitCool = FilterPreset(
    id: 'portrait_cool',
    name: 'Portrait Cool',
    category: 'Portrait',
    adjustments: {
      'temperature': -0.1,
      'brightness': 0.03,
      'contrast': 0.04,
      'highlights': 0.06,
      'shadows': 0.08,
      'saturation': -0.04,
      'clarity': 0.06,
    },
  );

  // --- CINEMATIC ---

  static const cinematic = FilterPreset(
    id: 'cinematic',
    name: 'Cinematic',
    category: 'Cinematic',
    adjustments: {
      'contrast': 0.15,
      'saturation': -0.12,
      'vibrance': -0.08,
      'temperature': 0.06,
      'blacks': 0.1,
      'shadows': 0.06,
      'highlights': -0.08,
      'clarity': 0.12,
      'vignette': -0.2,
    },
  );

  static const tealCinematic = FilterPreset(
    id: 'teal_cinematic',
    name: 'Teal Cinematic',
    category: 'Cinematic',
    adjustments: {
      'temperature': -0.14,
      'tint': 0.08,
      'contrast': 0.12,
      'saturation': -0.08,
      'vibrance': 0.06,
      'blacks': 0.08,
      'highlights': -0.06,
      'clarity': 0.08,
      'vignette': -0.15,
    },
  );

  static const moodyCinematic = FilterPreset(
    id: 'moody_cinematic',
    name: 'Moody Cinematic',
    category: 'Cinematic',
    adjustments: {
      'contrast': 0.18,
      'brightness': -0.06,
      'saturation': -0.18,
      'vibrance': -0.1,
      'temperature': -0.06,
      'blacks': 0.12,
      'shadows': -0.08,
      'clarity': 0.14,
      'vignette': -0.25,
    },
  );

  // --- BLACK & WHITE ---

  static const classicBw = FilterPreset(
    id: 'classic_bw',
    name: 'Classic B&W',
    category: 'B&W',
    adjustments: {
      'saturation': -1.0,
      'contrast': 0.1,
      'brightness': 0.02,
      'clarity': 0.06,
      'vignette': -0.1,
    },
  );

  static const highContrastBw = FilterPreset(
    id: 'high_contrast_bw',
    name: 'High Contrast B&W',
    category: 'B&W',
    adjustments: {
      'saturation': -1.0,
      'contrast': 0.3,
      'highlights': 0.12,
      'blacks': -0.12,
      'clarity': 0.12,
      'sharpness': 0.15,
    },
  );

  static const softBw = FilterPreset(
    id: 'soft_bw',
    name: 'Soft B&W',
    category: 'B&W',
    adjustments: {
      'saturation': -1.0,
      'contrast': -0.08,
      'brightness': 0.06,
      'highlights': 0.1,
      'shadows': 0.1,
      'clarity': -0.08,
    },
  );

  // --- VINTAGE ---

  static const vintage = FilterPreset(
    id: 'vintage',
    name: 'Vintage',
    category: 'Vintage',
    adjustments: {
      'temperature': 0.14,
      'saturation': -0.16,
      'contrast': -0.1,
      'brightness': 0.04,
      'blacks': 0.15,
      'highlights': -0.08,
      'vignette': -0.18,
    },
  );

  static const faded = FilterPreset(
    id: 'faded',
    name: 'Faded',
    category: 'Vintage',
    adjustments: {
      'saturation': -0.2,
      'contrast': -0.15,
      'brightness': 0.08,
      'blacks': 0.2,
      'shadows': 0.12,
      'clarity': -0.1,
      'vignette': -0.1,
    },
  );

  static const retro = FilterPreset(
    id: 'retro',
    name: 'Retro',
    category: 'Vintage',
    adjustments: {
      'temperature': 0.1,
      'saturation': -0.12,
      'contrast': 0.08,
      'blacks': 0.1,
      'highlights': -0.1,
      'vibrance': 0.04,
      'vignette': -0.15,
    },
  );

  // --- VIBRANT ---

  static const vibrant = FilterPreset(
    id: 'vibrant',
    name: 'Vibrant',
    category: 'Vibrant',
    adjustments: {
      'saturation': 0.18,
      'vibrance': 0.2,
      'contrast': 0.08,
      'clarity': 0.06,
      'highlights': 0.04,
    },
  );

  static const pop = FilterPreset(
    id: 'pop',
    name: 'Pop',
    category: 'Vibrant',
    adjustments: {
      'saturation': 0.25,
      'vibrance': 0.15,
      'contrast': 0.15,
      'brightness': 0.04,
      'clarity': 0.1,
      'sharpness': 0.08,
    },
  );

  static const rich = FilterPreset(
    id: 'rich',
    name: 'Rich',
    category: 'Vibrant',
    adjustments: {
      'saturation': 0.12,
      'vibrance': 0.18,
      'contrast': 0.1,
      'blacks': -0.06,
      'highlights': 0.06,
      'clarity': 0.08,
      'temperature': 0.04,
    },
  );

  /// Lookup a preset by ID.
  static FilterPreset? findById(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// Get all unique categories.
  static List<String> get categories {
    final cats = <String>{};
    for (final preset in all) {
      cats.add(preset.category);
    }
    return cats.toList();
  }

  /// Get presets for a specific category.
  static List<FilterPreset> forCategory(String category) {
    return all.where((p) => p.category == category).toList();
  }
}
