import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

import '../models/ai_recommendation.dart';
import '../models/pump_flow_rate.dart';
import '../models/sensor_data.dart';

String _formatAiDateTime(DateTime value) {
  return DateFormat('dd-MM-yyyy HH:mm').format(value);
}

String _formatAiDateTimeRange(DateTime start, DateTime end) {
  return '${_formatAiDateTime(start)} sampai ${_formatAiDateTime(end)}';
}

class FertilizerSolutionConcentration {
  const FertilizerSolutionConcentration({
    required this.nitrogenMgPerLiter,
    required this.phosphorusMgPerLiter,
    required this.potassiumMgPerLiter,
  });

  final double nitrogenMgPerLiter;
  final double phosphorusMgPerLiter;
  final double potassiumMgPerLiter;

  Map<String, dynamic> toJson() {
    return {
      'unit': 'mg/L',
      'nitrogen_mg_per_liter': nitrogenMgPerLiter,
      'phosphorus_mg_per_liter': phosphorusMgPerLiter,
      'potassium_mg_per_liter': potassiumMgPerLiter,
      'calculation_note':
          'Use these stock-solution concentrations as duration factors. Lower concentration may require longer runtime, but the final recommendation must remain within local safety bounds and pH/EC constraints.',
    };
  }
}

class PlantingMediumProfile {
  const PlantingMediumProfile({
    required this.id,
    required this.label,
    required this.assumedDepthCm,
    required this.bulkDensityKgPerM3,
    required this.note,
  });

  final String id;
  final String label;
  final double assumedDepthCm;
  final double bulkDensityKgPerM3;
  final String note;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'assumed_depth_cm': assumedDepthCm,
      'bulk_density_kg_per_m3': bulkDensityKgPerM3,
      'note': note,
    };
  }
}

class PlantTypeProfile {
  const PlantTypeProfile({
    required this.id,
    required this.label,
    required this.scientificName,
    required this.contextNote,
    required this.thresholds,
  });

  final String id;
  final String label;
  final String scientificName;
  final String contextNote;
  final Map<String, num> thresholds;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'scientific_name': scientificName,
      'context_note': contextNote,
      'thresholds': thresholds,
    };
  }
}

class AiAnalysisWindowProfile {
  const AiAnalysisWindowProfile({
    required this.id,
    required this.label,
    required this.duration,
    required this.description,
    this.customStartAt,
    this.customEndAt,
  });

  factory AiAnalysisWindowProfile.customRange({
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return AiAnalysisWindowProfile(
      id: 'custom',
      label: 'Custom',
      duration: null,
      description:
          'Analisis manual berdasarkan rentang tanggal dan jam yang dipilih.',
      customStartAt: startAt,
      customEndAt: endAt,
    );
  }

  final String id;
  final String label;
  final Duration? duration;
  final String description;
  final DateTime? customStartAt;
  final DateTime? customEndAt;

  bool get isCustom => id == 'custom';

  String get xaiLabel {
    final start = customStartAt;
    final end = customEndAt;
    if (!isCustom || start == null || end == null) return label;
    return _formatAiDateTimeRange(start, end);
  }

  AiAnalysisTimestampRange resolveRange(DateTime now) {
    final start = customStartAt;
    final end = customEndAt;
    if (isCustom && start != null && end != null) {
      return AiAnalysisTimestampRange(start: start, end: end);
    }

    final windowDuration = duration ?? const Duration(hours: 12);
    return AiAnalysisTimestampRange(
      start: now.subtract(windowDuration),
      end: now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'filter_method': 'timestamp_range',
      if (duration != null) 'duration_minutes': duration!.inMinutes,
      if (customStartAt != null)
        'custom_start_at': customStartAt!.toIso8601String(),
      if (customEndAt != null) 'custom_end_at': customEndAt!.toIso8601String(),
      if (customStartAt != null && customEndAt != null)
        'display_range': _formatAiDateTimeRange(customStartAt!, customEndAt!),
      'display_format': 'dd-MM-yyyy HH:mm',
      'description': description,
    };
  }
}

class AiAnalysisTimestampRange {
  const AiAnalysisTimestampRange({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;

  Map<String, dynamic> toJson() {
    return {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'display_range': _formatAiDateTimeRange(start, end),
      'display_format': 'dd-MM-yyyy HH:mm',
      'basis': 'Firestore timestamp field',
    };
  }
}

class AiRecommendationAgronomicInput {
  const AiRecommendationAgronomicInput({
    required this.plantType,
    required this.landAreaSquareMeters,
    required this.fertilizerConcentration,
    required this.plantingMedium,
    required this.analysisWindow,
  });

  final PlantTypeProfile plantType;
  final double landAreaSquareMeters;
  final FertilizerSolutionConcentration fertilizerConcentration;
  final PlantingMediumProfile plantingMedium;
  final AiAnalysisWindowProfile analysisWindow;

  Map<String, dynamic> toJson() {
    return {
      'plant_type': plantType.toJson(),
      'land_area_square_meters': landAreaSquareMeters,
      'fertilizer_solution_concentration': fertilizerConcentration.toJson(),
      'planting_medium': plantingMedium.toJson(),
      'analysis_window': analysisWindow.toJson(),
      'calculation_note':
          'Land area is fixed to 100 cm2 (0.01 m2) to match the local NPK sensor coverage and small pump safety limit. Media depth is an assumption from the selected planting medium because actual depth is not measured by the app.',
    };
  }
}

const AiAnalysisWindowProfile defaultAnalysisWindowProfile =
    AiAnalysisWindowProfile(
  id: '12h',
  label: '12 jam',
  duration: Duration(hours: 12),
  description: 'Analisis stabilitas setengah hari terakhir.',
);

const AiAnalysisWindowProfile customAnalysisWindowProfile =
    AiAnalysisWindowProfile(
  id: 'custom',
  label: 'Custom',
  duration: null,
  description:
      'Analisis manual berdasarkan rentang tanggal dan jam yang dipilih.',
);

const List<AiAnalysisWindowProfile> analysisWindowProfiles = [
  AiAnalysisWindowProfile(
    id: '1h',
    label: '1 jam',
    duration: Duration(hours: 1),
    description: 'Analisis cepat untuk kondisi sensor terbaru.',
  ),
  AiAnalysisWindowProfile(
    id: '6h',
    label: '6 jam',
    duration: Duration(hours: 6),
    description: 'Analisis perubahan kondisi dalam beberapa jam terakhir.',
  ),
  defaultAnalysisWindowProfile,
  AiAnalysisWindowProfile(
    id: '24h',
    label: '24 jam',
    duration: Duration(hours: 24),
    description: 'Analisis pola harian penuh.',
  ),
  AiAnalysisWindowProfile(
    id: '7d',
    label: '7 hari',
    duration: Duration(days: 7),
    description: 'Analisis tren mingguan untuk melihat kestabilan nutrisi.',
  ),
  AiAnalysisWindowProfile(
    id: '30d',
    label: '30 hari',
    duration: Duration(days: 30),
    description: 'Analisis tren jangka panjang satu bulan.',
  ),
  customAnalysisWindowProfile,
];

const PlantTypeProfile customPlantTypeProfile = PlantTypeProfile(
  id: 'custom',
  label: 'Lainnya',
  scientificName: 'Profil tanaman kustom',
  contextNote:
      'Gunakan pilihan ini jika tanaman belum tersedia di daftar. NutriXense akan menyesuaikan rekomendasi dari data sensor, area sensor tetap 100 cm2, dan media tanam yang Anda masukkan.',
  thresholds: {
    'nitrogen_min': 70,
    'nitrogen_max': 170,
    'phosphorus_min': 60,
    'phosphorus_max': 200,
    'potassium_min': 180,
    'potassium_max': 550,
    'moisture_min': 45,
    'moisture_max': 75,
    'ph_min': 5.5,
    'ph_max': 6.8,
    'temperature_min': 18,
    'temperature_max': 30,
    'ec_min': 1.0,
    'ec_max': 3.0,
  },
);

const List<PlantTypeProfile> plantTypeProfiles = [
  PlantTypeProfile(
    id: 'tea',
    label: 'Teh',
    scientificName: 'Camellia sinensis',
    contextNote:
        'Tanaman teh menyukai media asam, drainase baik, dan koreksi nutrisi bertahap agar akar tidak stres.',
    thresholds: {
      'nitrogen_min': 100,
      'nitrogen_max': 200,
      'phosphorus_min': 20,
      'phosphorus_max': 50,
      'potassium_min': 100,
      'potassium_max': 200,
      'moisture_min': 40,
      'moisture_max': 70,
      'ph_min': 4.5,
      'ph_max': 5.5,
      'temperature_min': 18,
      'temperature_max': 25,
      'ec_min': 0.8,
      'ec_max': 1.8,
    },
  ),
  PlantTypeProfile(
    id: 'chili',
    label: 'Cabai',
    scientificName: 'Capsicum annuum',
    contextNote:
        'Cabai membutuhkan kelembapan stabil, pH agak asam-netral, dan koreksi K bertahap untuk mendukung pembungaan dan buah.',
    thresholds: {
      'nitrogen_min': 70,
      'nitrogen_max': 160,
      'phosphorus_min': 60,
      'phosphorus_max': 180,
      'potassium_min': 180,
      'potassium_max': 450,
      'moisture_min': 45,
      'moisture_max': 75,
      'ph_min': 5.8,
      'ph_max': 6.8,
      'temperature_min': 22,
      'temperature_max': 30,
      'ec_min': 1.5,
      'ec_max': 2.8,
    },
  ),
  PlantTypeProfile(
    id: 'tomato',
    label: 'Tomat',
    scientificName: 'Solanum lycopersicum',
    contextNote:
        'Tomat membutuhkan K cukup tinggi saat generatif, kelembapan merata, dan pH agak asam-netral.',
    thresholds: {
      'nitrogen_min': 80,
      'nitrogen_max': 170,
      'phosphorus_min': 70,
      'phosphorus_max': 200,
      'potassium_min': 220,
      'potassium_max': 550,
      'moisture_min': 50,
      'moisture_max': 80,
      'ph_min': 5.8,
      'ph_max': 6.8,
      'temperature_min': 20,
      'temperature_max': 28,
      'ec_min': 2.0,
      'ec_max': 3.5,
    },
  ),
  PlantTypeProfile(
    id: 'lettuce',
    label: 'Selada',
    scientificName: 'Lactuca sativa',
    contextNote:
        'Selada sensitif terhadap EC tinggi dan panas, sehingga koreksi nutrisi sebaiknya ringan serta kelembapan dijaga stabil.',
    thresholds: {
      'nitrogen_min': 50,
      'nitrogen_max': 120,
      'phosphorus_min': 40,
      'phosphorus_max': 140,
      'potassium_min': 120,
      'potassium_max': 320,
      'moisture_min': 55,
      'moisture_max': 80,
      'ph_min': 5.5,
      'ph_max': 6.5,
      'temperature_min': 16,
      'temperature_max': 24,
      'ec_min': 0.8,
      'ec_max': 1.8,
    },
  ),
  customPlantTypeProfile,
];

const PlantingMediumProfile customPlantingMediumProfile = PlantingMediumProfile(
  id: 'custom',
  label: 'Lainnya',
  assumedDepthCm: 20,
  bulkDensityKgPerM3: 900,
  note:
      'Gunakan pilihan ini jika media tanam belum tersedia di daftar. NutriXense akan menyesuaikan rekomendasi dari data sensor dan jenis tanaman yang Anda pilih.',
);

const List<PlantingMediumProfile> plantingMediumProfiles = [
  PlantingMediumProfile(
    id: 'potting_mix',
    label: 'Media pot ringan',
    assumedDepthCm: 18,
    bulkDensityKgPerM3: 650,
    note: 'Campuran kompos/cocopeat/sekam; asumsi ringan dan poros.',
  ),
  PlantingMediumProfile(
    id: 'loam_soil',
    label: 'Tanah gembur',
    assumedDepthCm: 20,
    bulkDensityKgPerM3: 900,
    note: 'Tanah mineral gembur dengan drainase cukup baik.',
  ),
  PlantingMediumProfile(
    id: 'clay_soil',
    label: 'Tanah liat',
    assumedDepthCm: 15,
    bulkDensityKgPerM3: 1200,
    note: 'Media lebih padat; koreksi dibuat lebih bertahap.',
  ),
  PlantingMediumProfile(
    id: 'sandy_fast_drying_soil',
    label: 'Tanah berpasir',
    assumedDepthCm: 18,
    bulkDensityKgPerM3: 1100,
    note: 'Media berdrainase cepat; penyiraman dan nutrisi dibuat bertahap.',
  ),
  PlantingMediumProfile(
    id: 'raised_bed',
    label: 'Bedengan',
    assumedDepthCm: 25,
    bulkDensityKgPerM3: 850,
    note: 'Profil akar dangkal-menengah untuk koreksi permukaan bertahap.',
  ),
  customPlantingMediumProfile,
];

class GeminiRecommendationService {
  GeminiRecommendationService({
    FirebaseFirestore? firestore,
    String? apiKey,
    String? modelName,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _apiKeyOverride = apiKey,
        _modelNameOverride = modelName;

  static const _collection = 'sensor_data';
  static const _configAssetPath = 'assets/config/gemini_config.json';
  static const _dartDefineApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _dartDefineModelName = String.fromEnvironment('GEMINI_MODEL');
  static const _busyMessage =
      'AI sedang sibuk karena trafik tinggi. Silakan coba lagi dalam beberapa saat.';
  static const _requestTimeout = Duration(minutes: 1);
  static const _singleAttemptTimeout = Duration(seconds: 25);
  static const _maxRetryAttempts = 3;
  static const _defaultModelName = 'gemini-3.6-flash';
  static const _fallbackModelNames = [
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash',
  ];
  static const _responseCacheTtl = Duration(minutes: 2);
  static const _gradualCorrectionFraction = 0.25;
  static const _maxPumpRunSeconds = 30;
  static const _doseBaselineConcentrationMgPerLiter = 500.0;
  static const _minConcentrationDurationFactor = 0.001;
  static const _maxConcentrationDurationFactor = 100.0;
  static _CachedAiRecommendation? _cachedRecommendation;

  // Default threshold target keeps the original tea-plant behavior.
  static final Map<String, num> thresholds = plantTypeProfiles.first.thresholds;

  final FirebaseFirestore _firestore;
  final String? _apiKeyOverride;
  final String? _modelNameOverride;

  Future<AiRecommendationResponse> requestRecommendation({
    required AiRecommendationAgronomicInput input,
  }) async {
    final config = await _resolveConfig();

    if (config.apiKey.trim().isEmpty) {
      throw StateError(
        'GEMINI_API_KEY belum dikonfigurasi. Isi $_configAssetPath atau '
        'jalankan Flutter dengan --dart-define=GEMINI_API_KEY=YOUR_KEY.',
      );
    }

    final requestedTimestampRange =
        input.analysisWindow.resolveRange(DateTime.now());
    if (!requestedTimestampRange.end.isAfter(requestedTimestampRange.start)) {
      throw StateError(
        'Rentang analisis timestamp tidak valid. Waktu akhir harus setelah waktu mulai.',
      );
    }

    final readings = await _fetchReadingsByTimestampRange(
      requestedTimestampRange,
    );
    if (readings.isEmpty) {
      throw StateError(
        'Belum ada data sensor di koleksi $_collection pada rentang timestamp '
        '${requestedTimestampRange.start.toIso8601String()} sampai '
        '${requestedTimestampRange.end.toIso8601String()}.',
      );
    }

    final summary = SensorHistorySummary.fromReadings(readings);
    final activeThresholds = _thresholdsFor(input);
    final requestFingerprint = _buildRequestFingerprint(
      summary,
      input,
      activeThresholds,
    );
    final cachedResponse = _readCachedRecommendation(requestFingerprint);
    if (cachedResponse != null) return cachedResponse;

    final deterministicPlan = buildDeterministicDecisionPlan(
      summary,
      input,
      activeThresholds,
    );
    final dynamicDoseReference = _dynamicFertilizerDoseReferenceToJson(
      _buildDynamicFertilizerDoses(
        summary,
        input,
        activeThresholds,
      ),
    );
    final payload = jsonEncode({
      'task':
          'Calculate hybrid Gemini dose recommendations for ${input.plantType.label} and return JSON only.',
      'crop_context':
          '${input.plantType.label} (${input.plantType.scientificName}). ${input.plantType.contextNote}',
      'selected_plant_context': {
        'id': input.plantType.id,
        'label': input.plantType.label,
        'scientific_name': input.plantType.scientificName,
        'agronomic_note': input.plantType.contextNote,
        'thresholds': activeThresholds,
      },
      'selected_planting_medium_context': {
        'id': input.plantingMedium.id,
        'label': input.plantingMedium.label,
        'assumed_depth_cm': input.plantingMedium.assumedDepthCm,
        'bulk_density_kg_per_m3': input.plantingMedium.bulkDensityKgPerM3,
        'medium_note': input.plantingMedium.note,
        'estimated_soil_mass_kg': _roundDouble(_estimatedSoilMassKg(input)),
      },
      'language': 'id',
      'control_policy':
          'Do not directly activate pumps. Return decision support only; the user must confirm and may adjust pump duration. Treat CWT RS485 NPK as estimated trends derived from conductivity behavior, not independent laboratory-grade elemental N/P/K measurements.',
      'pump_mapping': {
        'activate_nitrogen_pump':
            'Pompa A - Larutan Nitrogen (N), used in EC-based recipe dosing',
        'activate_phosphorus_pump':
            'Pompa B - Larutan Fosfor (P), used in EC-based recipe dosing',
        'activate_potassium_pump':
            'Pompa C - Larutan Kalium (K), used in EC-based recipe dosing',
        'activate_water_pump': 'Pompa D - Air (H2O)',
      },
      'sensor_interpretation_policy': {
        'npk_sensor_values': 'estimated_trend_only',
        'primary_nutrient_control_signal': 'EC',
        'fertilizer_control_method': 'dynamic EC-gated stock-solution dosing',
        'warning':
            'Do not infer independent N, P, or K deficiency solely from CWT NPK values. They are displayed as trends and supporting indicators only.',
      },
      'dynamic_fertilizer_dose_reference': dynamicDoseReference,
      'concentration_dose_model': {
        'baseline_mg_per_liter': _doseBaselineConcentrationMgPerLiter,
        'formula':
            'duration_factor = baseline_mg_per_liter / fertilizer_concentration_mg_per_liter',
        'clamp_range': [
          _minConcentrationDurationFactor,
          _maxConcentrationDurationFactor,
        ],
        'interpretation':
            'This fixed-baseline model makes concentration comparable across requests. Very concentrated solutions produce shorter pulses; very dilute solutions request longer pulses but are capped by local safety bounds.',
      },
      'cultivation_area': {
        'square_meters': input.landAreaSquareMeters,
        'unit': 'm2',
        'calculation_note':
            'This area is fixed to 100 cm2 (0.01 m2) because the RS485 NPK sensor only represents a small local measurement zone and the pump/tube hardware is small.',
      },
      'agronomic_input': input.toJson(),
      'analysis_window': input.analysisWindow.toJson(),
      'selected_timestamp_filter': requestedTimestampRange.toJson(),
      'pump_flow_rates_ml_per_second': PumpFlowRates.toPromptJson(),
      'output_rules': [
        'Return one complete JSON object only.',
        'Do not use markdown.',
        'Keep every string concise and close all quotes.',
        'Use history_summary, agronomic_input, pump_flow_rates_ml_per_second, thresholds, and local_safety_bounds to calculate pump_recommendations.',
        'Treat selected_plant_context and selected_planting_medium_context as primary decision context, not decoration.',
        'Recommendations must be specific to ${input.plantType.label}, not generic plant advice.',
        'Recommendations must be specific to ${input.plantingMedium.label}; explain how the medium depth, bulk density, porosity/drainage note, or estimated soil mass changes watering/fertilizer decisions.',
        'Use deterministic_decision_plan only as a safety reference and local calculation comparison, not as a fixed template.',
        'You may determine plant_health_percentage dynamically from current values, averages, trends, thresholds, and plant context.',
        'You may determine each recommendation item status and group membership dynamically from the sensor history and thresholds.',
        'You may rewrite message, explanation, recommendation, sensor_summary, automation trigger reason, pump reasons, and schedule reason in your own agronomic wording.',
        'Keep item ids stable when they refer to the same sensor parameter, but you may adjust title text to be clearer.',
        'Automation trigger booleans should reflect your decision support, but they will still be safety-checked by the app before any pump action.',
        'For Pompa A/B/C stock nutrient recommendations, EC below ec_min is the nutrient activation gate, but choose pump durations dynamically from dynamic_fertilizer_dose_reference, estimated N/P/K trend severity, pH risk, fertilizer concentration, plant context, medium context, and pump flow rates.',
        'Estimated N, P, and K values may influence relative fertilizer priority and duration, but they are not independent pump triggers because the CWT RS485 NPK reading is an estimated trend/proxy.',
        'For EC low, calculate stock-solution pump seconds from EC deficit severity, historical N/P/K trend, fertilizer concentration, pH safety, deterministic_decision_plan, and pump flow rates; keep the correction gradual.',
        'A lower fertilizer concentration may require a longer pump duration, but never exceed local safety bounds; if pH is already below ph_min, reduce or postpone acidifying fertilizer such as urea/N even when estimated N trend is low.',
        'Use the fixed concentration_dose_model baseline. Do not normalize fertilizer concentration against the other N/P/K input values.',
        'You may recommend only the fertilizer pumps that are suitable. Do not include every A/B/C pump when pH, EC, estimated trend, or concentration data argues against one pump.',
        'For EC high, never recommend fertilizer stock pumps; recommend dilution/flush monitoring with water only when moisture and context make it safe.',
        'For moisture, estimate water volume from current-to-minimum moisture percentage gap, fixed 100 cm2 area, assumed medium depth, estimated local medium volume, and safe gradual correction.',
        'Calculate recommended_seconds as recommended_volume_ml / pump_flow_rate_ml_per_second rounded to nearest whole second.',
        'Do not round recommended_seconds down to 1 second when fertilizer concentration is low or nutrient deficit is large. Compare your dose with deterministic_decision_plan.pump_recommendations and keep the same order of magnitude unless you explicitly justify a smaller gradual dose.',
        'Do not exceed local_safety_bounds.max_seconds_per_pump or local_safety_bounds.max_volume_ml_per_pump.',
        'For daily_schedule_recommendation, choose hour, minute, pump_indexes, and duration_seconds dynamically from history_summary, plant context, pump_recommendations, and pump_flow_rates_ml_per_second.',
        'daily_schedule_recommendation.duration_seconds may differ from the largest pump_recommendations item when you intentionally recommend a smaller scheduled maintenance dose; explain this in the reason.',
        'daily_schedule_recommendation.pump_indexes should include only pumps that are useful for the selected schedule; do not include every pump unless every pump should run.',
        'Prefer morning schedule times for watering or fertilizer correction unless sensor history suggests another safe daytime window.',
        'If a calculation is uncertain, recommend a smaller gradual dose and explain the assumption.',
        'Narasi XAI must explain that depth/media values are estimates from selected planting medium because actual media depth is not measured.',
        'sensor_summary maximum 2 sentences and must mention ${input.plantType.label}, ${input.plantingMedium.label}, and the selected analysis window (${input.analysisWindow.xaiLabel}), not the number of analyzed rows.',
        'When writing dates or times for users, use the provided display_range/display_format (dd-MM-yyyy HH:mm). Do not expose ISO timestamps with T, seconds, milliseconds, or timezone suffixes in sensor_summary.',
        'For each item, message maximum 1 sentence, explanation maximum 2 sentences, recommendation maximum 2 sentences.',
        'For each recommendation item, explanation must explain current value, threshold, average, trend, selected plant relevance, selected medium relevance, and the dose basis when correction is needed.',
        'For each recommendation item, recommendation must explain practical follow-up actions for ${input.plantType.label} on ${input.plantingMedium.label} and require user confirmation before pump activation.',
        'Pump recommendation reasons must mention the relevant pump flow rate, EC-based recipe basis for A/B/C, and why the chosen duration fits ${input.plantingMedium.label} and ${input.plantType.label}.',
        'Daily schedule reason must explain why the chosen time, pump indexes, and duration fit ${input.plantType.label}, ${input.plantingMedium.label}, and recent sensor trends.',
        'Do not mention or assume any specific cultivation container unless the input data explicitly states it.',
        'Return pump_recommendations and daily_schedule_recommendation when pump correction is needed.',
      ],
      'thresholds': activeThresholds,
      'history_summary': summary.toJson(activeThresholds),
      'local_safety_bounds': _safetyBoundsToJson(input),
      'deterministic_decision_plan': deterministicPlan,
    });

    late final _GeminiContentResult geminiResult;
    try {
      geminiResult = await _generateContentWithModelFallback(
        config,
        [Content.text(payload)],
      );
    } on Object catch (error) {
      if (_shouldUseLocalFallback(error)) {
        debugPrint(
          'Gemini daily request limit reached, using local DSS/XAI fallback: $error',
        );
        final fallbackResponse = _responseWithDecisionPlan(
          _buildAiUnavailableFallbackResponse(
            summary,
            error,
            input,
            activeThresholds,
          ),
          summary,
          input,
          activeThresholds: activeThresholds,
          useGeminiPumpRecommendations: false,
        );
        return _cacheRecommendation(
          requestFingerprint,
          fallbackResponse,
        );
      }
      rethrow;
    }

    final text = geminiResult.response.text;
    if (text == null || text.trim().isEmpty) {
      throw StateError('Gemini tidak mengembalikan teks JSON.');
    }

    final decoded = await _decodeJsonResponse(
      config: config,
      rawText: text,
      originalPayload: payload,
      summary: summary,
      input: input,
      activeThresholds: activeThresholds,
    );
    final merged = _mergeGeminiNarrativeWithDecisionPlan(
      deterministicPlan,
      summary,
      decoded,
    );
    final responseWithDecisionPlan = _responseWithDecisionPlan(
      merged,
      summary,
      input,
      activeThresholds: activeThresholds,
      useGeminiPumpRecommendations: true,
    );
    return _cacheRecommendation(
      requestFingerprint,
      responseWithDecisionPlan,
    );
  }

  static AiRecommendationResponse _responseWithDecisionPlan(
    Map<String, dynamic> decoded,
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input, {
    required Map<String, num> activeThresholds,
    required bool useGeminiPumpRecommendations,
  }) {
    final displayDecoded = _decodedWithReadableSensorSummary(decoded);
    final guardedResponse =
        AiRecommendationResponse.fromJson(displayDecoded).withAutomationGuard(
      canActivateWaterPump: summary.canActivateWaterPump(activeThresholds),
      canActivateNitrogenPump:
          summary.canActivateFertilizerRecipe(activeThresholds),
      canActivatePhosphorusPump:
          summary.canActivateFertilizerRecipe(activeThresholds),
      canActivatePotassiumPump:
          summary.canActivateFertilizerRecipe(activeThresholds),
    );
    final localPumpRecommendations = _buildPumpRecommendations(
      summary,
      input,
      activeThresholds,
    );
    final geminiPumpRecommendations = useGeminiPumpRecommendations
        ? _validateGeminiPumpRecommendations(
            decoded,
            summary,
            input,
            activeThresholds,
            localPumpRecommendations,
          )
        : const <PumpFertilizationRecommendation>[];
    final pumpRecommendations = geminiPumpRecommendations.isNotEmpty
        ? geminiPumpRecommendations
        : localPumpRecommendations;
    final scheduleRecommendation = pumpRecommendations.isEmpty
        ? null
        : _validateGeminiSchedule(decoded, pumpRecommendations, input) ??
            DailyFertilizationScheduleRecommendation.fromPlan(
              recommendations: pumpRecommendations,
              reason:
                  'Jadwal harian ${input.plantType.label} direkomendasikan dari kalkulasi hybrid Gemini dengan validasi batas aman lokal, area sensor 100 cm2, dan asumsi media ${input.plantingMedium.label}.',
            );
    final recommendedPumpIndexes =
        pumpRecommendations.map((item) => item.pumpIndex).toSet();
    final refinedTriggers = guardedResponse.automationTriggers.copyWith(
      activateNitrogenPump: recommendedPumpIndexes.contains(0),
      activatePhosphorusPump: recommendedPumpIndexes.contains(1),
      activatePotassiumPump: recommendedPumpIndexes.contains(2),
      activateWaterPump: recommendedPumpIndexes.contains(3),
      reason:
          '${guardedResponse.automationTriggers.reason} Trigger akhir diselaraskan dengan rekomendasi pompa yang lolos validasi lokal.',
    );
    final xaiContributions = _buildHistoricalShapContributions(
      summary,
      input,
      activeThresholds,
      pumpRecommendations,
    );

    return guardedResponse.copyWith(
      automationTriggers: refinedTriggers,
      pumpRecommendations: pumpRecommendations,
      dailyScheduleRecommendation: scheduleRecommendation,
      xaiContributions: xaiContributions,
    );
  }

  static Map<String, dynamic> _decodedWithReadableSensorSummary(
    Map<String, dynamic> decoded,
  ) {
    final sensorSummary = decoded['sensor_summary'];
    if (sensorSummary is! String || sensorSummary.isEmpty) return decoded;

    return {
      ...decoded,
      'sensor_summary': _replaceIsoTimestampsForDisplay(sensorSummary),
    };
  }

  static String _replaceIsoTimestampsForDisplay(String value) {
    var replaced = value.replaceAllMapped(
      RegExp(
        r'(\d{4})-(\d{2})-(\d{2})(?:T|\s+)(\d{2}:\d{2})(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?',
      ),
      (match) =>
          '${match.group(3)}-${match.group(2)}-${match.group(1)} ${match.group(4)}',
    );
    replaced = replaced.replaceAllMapped(
      RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b'),
      (match) => '${match.group(3)}-${match.group(2)}-${match.group(1)}',
    );
    replaced = replaced
        .replaceAll('untuk rentang Custom ', 'mulai dari ')
        .replaceAll('untuk rentang Custom', 'mulai dari')
        .replaceAll('Pengukuran NPK RS485 digunakan', 'Pengukuran nilai N, P, K oleh sensor digunakan')
        .replaceAll('Pengukuran NPK RS485', 'Pengukuran nilai N, P, K oleh sensor');

    if (replaced.endsWith('berbasis EC') || replaced.endsWith('berbasis EC ')) {
      replaced = '${replaced.trim()}.';
    }

    return replaced;
  }

  Future<_GeminiRuntimeConfig> _resolveConfig() async {
    final localConfig = await _loadLocalConfig();

    return _GeminiRuntimeConfig(
      apiKey: _firstNonEmpty([
        _apiKeyOverride,
        _dartDefineApiKey,
        localConfig.apiKey,
      ]),
      modelName: _firstNonEmpty([
        _modelNameOverride,
        _dartDefineModelName,
        localConfig.modelName,
      ], fallback: _defaultModelName),
    );
  }

  Future<_GeminiRuntimeConfig> _loadLocalConfig() async {
    try {
      final text = await rootBundle.loadString(_configAssetPath);
      final json = jsonDecode(text) as Map<String, dynamic>;
      return _GeminiRuntimeConfig(
        apiKey: json['apiKey'] as String? ?? '',
        modelName: json['modelName'] as String? ?? '',
      );
    } on FormatException {
      return const _GeminiRuntimeConfig();
    } on TypeError {
      return const _GeminiRuntimeConfig();
    } on FlutterError {
      return const _GeminiRuntimeConfig();
    }
  }

  String _firstNonEmpty(List<String?> values, {String fallback = ''}) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return fallback;
  }

  Future<List<_SensorReadingSnapshot>> _fetchReadingsByTimestampRange(
    AiAnalysisTimestampRange range,
  ) async {
    final query = _firestore
        .collection(_collection)
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
        )
        .where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(range.end),
        )
        .orderBy('timestamp', descending: false);

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => _SensorReadingSnapshot.fromFirestore(doc.data()))
        .where((item) => item.hasAnySensorValue)
        .toList();
  }

  static String _buildRequestFingerprint(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    return jsonEncode({
      'agronomic_input': input.toJson(),
      'thresholds': activeThresholds,
      'summary': summary.toJson(activeThresholds),
    });
  }

  static AiRecommendationResponse? _readCachedRecommendation(
    String fingerprint,
  ) {
    final cached = _cachedRecommendation;
    if (cached == null || cached.fingerprint != fingerprint) return null;

    final age = DateTime.now().difference(cached.createdAt);
    if (age > _responseCacheTtl) return null;

    return cached.response;
  }

  static AiRecommendationResponse _cacheRecommendation(
    String fingerprint,
    AiRecommendationResponse response,
  ) {
    _cachedRecommendation = _CachedAiRecommendation(
      fingerprint: fingerprint,
      response: response,
      createdAt: DateTime.now(),
    );
    return response;
  }

  static String _stripCodeFence(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    return trimmed
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }

  static Future<Map<String, dynamic>> _decodeJsonResponse({
    required _GeminiRuntimeConfig config,
    required String rawText,
    required String originalPayload,
    required SensorHistorySummary summary,
    required AiRecommendationAgronomicInput input,
    required Map<String, num> activeThresholds,
  }) async {
    final cleaned = _stripCodeFence(rawText);
    final decoded = _tryDecodeJsonObject(cleaned);
    if (decoded != null) return decoded;

    dynamic repairResponse;
    try {
      final repairResult = await _generateContentWithModelFallback(
        config,
        [
          Content.text(jsonEncode({
            'task':
                'Repair the malformed model output into one valid minified JSON object matching the schema. Do not add markdown or explanation.',
            'schema_keys': [
              'plant_health_percentage',
              'sensor_summary',
              'recommendations',
              'automation_triggers',
              'pump_recommendations',
              'daily_schedule_recommendation',
            ],
            'automation_trigger_keys': [
              'activate_nitrogen_pump',
              'activate_phosphorus_pump',
              'activate_potassium_pump',
              'activate_water_pump',
              'reason',
            ],
            'recommendation_item_keys': [
              'id',
              'title',
              'status',
              'message',
              'explanation',
              'recommendation',
            ],
            'pump_recommendation_item_keys': [
              'relay',
              'pump_index',
              'pump_name',
              'nutrient',
              'unit',
              'current_value',
              'target_minimum',
              'deficit',
              'deficit_percent',
              'recommended_volume_ml',
              'recommended_seconds',
              'reason',
              'calculation_basis',
            ],
            'original_input': originalPayload,
            'malformed_output': cleaned,
          })),
        ],
      );
      repairResponse = repairResult.response;
    } on Object catch (error) {
      if (_shouldUseLocalFallback(error)) {
        debugPrint(
          'Gemini repair unavailable because daily request limit was reached, using local DSS/XAI fallback: $error',
        );
        return _buildAiUnavailableFallbackResponse(
          summary,
          error,
          input,
          activeThresholds,
        );
      }
      rethrow;
    }

    final repairedText = repairResponse.text;
    final repaired = _tryDecodeJsonObject(_stripCodeFence(repairedText ?? ''));
    if (repaired != null) return repaired;

    throw StateError(
      'Gemini mengembalikan JSON yang belum valid setelah repair. '
      'Preview: ${_shortPreview(cleaned)}',
    );
  }

  @visibleForTesting
  static Map<String, dynamic> buildDeterministicDecisionPlan(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final pumpRecommendations = _buildPumpRecommendations(
      summary,
      input,
      activeThresholds,
    );
    final dailyScheduleRecommendation = pumpRecommendations.isEmpty
        ? null
        : DailyFertilizationScheduleRecommendation.fromPlan(
            recommendations: pumpRecommendations,
            reason:
                'Jadwal harian ${input.plantType.label} direkomendasikan dari kebutuhan koreksi EC/air terbaru berdasarkan rentang analisis ${input.analysisWindow.xaiLabel}, area sensor 100 cm2, dan asumsi media ${input.plantingMedium.label}.',
          );

    return {
      ..._buildLocalFallbackResponse(summary, input, activeThresholds),
      'pump_recommendations': _pumpRecommendationsToJson(pumpRecommendations),
      if (dailyScheduleRecommendation != null)
        'daily_schedule_recommendation':
            _dailyScheduleRecommendationToJson(dailyScheduleRecommendation),
    };
  }

  static Map<String, dynamic> _mergeGeminiNarrativeWithDecisionPlan(
    Map<String, dynamic> deterministicPlan,
    SensorHistorySummary summary,
    Map<String, dynamic> geminiResponse,
  ) {
    final geminiRecommendations = _asMap(geminiResponse['recommendations']);
    final geminiAutomationTriggers =
        _asMap(geminiResponse['automation_triggers']);
    final hasGeminiRecommendations =
        _hasCompleteRecommendationGroups(geminiRecommendations);
    final hasGeminiAutomationTriggers =
        _hasCompleteAutomationTriggers(geminiAutomationTriggers);

    return {
      ...deterministicPlan,
      if (geminiResponse['pump_recommendations'] != null)
        'pump_recommendations': geminiResponse['pump_recommendations'],
      if (geminiResponse['daily_schedule_recommendation'] != null)
        'daily_schedule_recommendation':
            geminiResponse['daily_schedule_recommendation'],
      'plant_health_percentage': geminiResponse['plant_health_percentage'] ??
          deterministicPlan['plant_health_percentage'],
      'sensor_summary': _nonEmptyText(geminiResponse['sensor_summary']) ??
          _nonEmptyText(deterministicPlan['sensor_summary']) ??
          'Analisis dibuat dari perhitungan DSS lokal berdasarkan data sensor terbaru.',
      'recommendations': hasGeminiRecommendations
          ? geminiRecommendations
          : deterministicPlan['recommendations'],
      'automation_triggers': hasGeminiAutomationTriggers
          ? geminiAutomationTriggers
          : deterministicPlan['automation_triggers'],
      'ai_output_policy': {
        'source': hasGeminiRecommendations
            ? 'gemini_dynamic_response'
            : 'local_fallback_response',
        'history_end': summary.endTime.toIso8601String(),
        'gemini_owned_fields': [
          'plant_health_percentage',
          'sensor_summary',
          'recommendations',
          'automation_trigger_reason',
          'pump_recommendation_reason',
          'daily_schedule_reason',
        ],
        'local_safety_guards': [
          'pump relay validation',
          'pump duration limit',
          'automation trigger threshold guard',
          'safe schedule hour guard',
        ],
      },
    };
  }

  static bool _hasCompleteRecommendationGroups(Map<String, dynamic> value) {
    final all = _asMapList(value['all']);
    return all.isNotEmpty &&
        value['kritis'] is List &&
        value['awas'] is List &&
        value['baik'] is List;
  }

  static bool _hasCompleteAutomationTriggers(Map<String, dynamic> value) {
    return value.containsKey('activate_nitrogen_pump') &&
        value.containsKey('activate_phosphorus_pump') &&
        value.containsKey('activate_potassium_pump') &&
        value.containsKey('activate_water_pump') &&
        _nonEmptyText(value['reason']) != null;
  }

  static List<Map<String, dynamic>> _pumpRecommendationsToJson(
    List<PumpFertilizationRecommendation> recommendations,
  ) {
    return recommendations
        .map(
          (item) => {
            'relay': item.relay,
            'pump_index': item.pumpIndex,
            'pump_name': item.pumpName,
            'nutrient': item.nutrient,
            'unit': item.unit,
            'current_value': item.currentValue,
            'target_minimum': item.targetMinimum,
            'deficit': item.deficit,
            'deficit_percent': item.deficitPercent,
            'recommended_seconds': item.recommendedSeconds,
            'average_flow_rate_ml_per_second': item.averageFlowRateMlPerSecond,
            'estimated_volume_ml': _roundDouble(item.estimatedVolumeMl),
            'reason': item.reason,
          },
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _dailyScheduleRecommendationToJson(
    DailyFertilizationScheduleRecommendation recommendation,
  ) {
    final pumpIndexes = recommendation.pumpIndexes.toList()..sort();
    return {
      'hour': recommendation.hour,
      'minute': recommendation.minute,
      'pump_indexes': pumpIndexes,
      'duration_seconds': recommendation.durationSeconds,
      'reason': recommendation.reason,
    };
  }

  static List<PumpFertilizationRecommendation>
      _validateGeminiPumpRecommendations(
    Map<String, dynamic> decoded,
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
    List<PumpFertilizationRecommendation> localFallback,
  ) {
    final rawItems = _asMapList(decoded['pump_recommendations']);
    if (rawItems.isEmpty) return const [];

    final fallbackByRelay = {
      for (final item in localFallback) item.relay: item,
    };
    final validated = <PumpFertilizationRecommendation>[];
    final usedRelays = <int>{};

    for (final raw in rawItems) {
      final relay = _readJsonInt(raw['relay']);
      final pumpIndex = _readJsonInt(raw['pump_index']).clamp(0, 3);
      final resolvedRelay = relay >= 1 && relay <= 4 ? relay : pumpIndex + 1;
      if (!usedRelays.add(resolvedRelay)) continue;
      if (resolvedRelay >= 1 &&
          resolvedRelay <= 3 &&
          !fallbackByRelay.containsKey(resolvedRelay)) {
        continue;
      }

      final metadata = _pumpMetadata(resolvedRelay, activeThresholds);
      if (metadata == null) continue;

      final current = summary.parameters[metadata.sensorKey]?.current;
      if (current == null || current >= metadata.minimum) continue;

      final rawVolume = _readJsonDouble(
        raw['recommended_volume_ml'] ?? raw['estimated_volume_ml'],
      );
      final rawSeconds = _readJsonInt(raw['recommended_seconds']);
      final secondsFromVolume = rawVolume > 0
          ? PumpFlowRates.secondsForVolume(
              pumpIndex: metadata.pumpIndex,
              volumeMl: rawVolume,
            )
          : 0;
      final candidateSeconds = rawSeconds > 0 ? rawSeconds : secondsFromVolume;
      if (candidateSeconds <= 0) continue;

      final maxSeconds = _maxSafeSecondsForPump(metadata.pumpIndex, input);
      final localReferenceSeconds =
          fallbackByRelay[resolvedRelay]?.recommendedSeconds ?? 0;
      final isFertilizerRelay = resolvedRelay >= 1 && resolvedRelay <= 3;
      final doseAwareSeconds = isFertilizerRelay && localReferenceSeconds > 0
          ? localReferenceSeconds
          : localReferenceSeconds > candidateSeconds
              ? localReferenceSeconds
              : candidateSeconds;
      final safeSeconds = doseAwareSeconds.clamp(1, maxSeconds).toInt();
      final wasAdjustedToDoseReference =
          candidateSeconds.toInt() != safeSeconds ||
              (isFertilizerRelay &&
                  localReferenceSeconds > 0 &&
                  candidateSeconds.toInt() != localReferenceSeconds);
      final deficit = _roundDouble(metadata.minimum - current);
      final deficitPercent = _roundDouble((deficit / metadata.minimum) * 100);
      final flowRate =
          PumpFlowRates.byPumpIndex(metadata.pumpIndex).averageMlPerSecond;
      final estimatedVolumeMl = PumpFlowRates.volumeForDuration(
        pumpIndex: metadata.pumpIndex,
        seconds: safeSeconds,
      );
      final basis = _nonEmptyText(raw['calculation_basis']);
      final reason = _nonEmptyText(raw['reason']) ??
          _nonEmptyText(raw['explanation']) ??
          fallbackByRelay[resolvedRelay]?.reason ??
          '${metadata.nutrient} saat ini ${_formatNumber(current)} ${metadata.unit}, kurang ${_formatNumber(deficit)} ${metadata.unit} dari ambang minimum ${_formatNumber(metadata.minimum)} ${metadata.unit}.';
      final doseReferenceNote = wasAdjustedToDoseReference
          ? ' Durasi diselaraskan dari rekomendasi mentah ${candidateSeconds.toInt()} detik ke $safeSeconds detik mengikuti model dosis lokal berbasis EC, tren estimasi NPK, pH, konsentrasi larutan, media, dan batas aman pompa.'
          : '';

      validated.add(
        PumpFertilizationRecommendation(
          relay: resolvedRelay,
          pumpIndex: metadata.pumpIndex,
          pumpName: metadata.pumpName,
          nutrient: metadata.nutrient,
          unit: metadata.unit,
          currentValue: current,
          targetMinimum: metadata.minimum,
          deficit: deficit,
          deficitPercent: deficitPercent,
          recommendedSeconds: safeSeconds,
          reason:
              '$reason ${basis == null ? '' : 'Dasar hitung: $basis '}$doseReferenceNote Durasi telah divalidasi dengan batas aman maksimal $maxSeconds detik dan debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk estimasi ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.',
        ),
      );
    }

    return validated;
  }

  static DailyFertilizationScheduleRecommendation? _validateGeminiSchedule(
    Map<String, dynamic> decoded,
    List<PumpFertilizationRecommendation> recommendations,
    AiRecommendationAgronomicInput input,
  ) {
    final rawSchedule = _asMap(decoded['daily_schedule_recommendation']);
    final schedule = DailyFertilizationScheduleRecommendation.fromJson(
      rawSchedule,
    );
    if (schedule == null) return null;
    if (schedule.hour < 5 || schedule.hour > 17) return null;

    final validPumpIndexes =
        recommendations.map((item) => item.pumpIndex).toSet();
    final requestedPumpIndexes = schedule.pumpIndexes
        .where((pumpIndex) => validPumpIndexes.contains(pumpIndex))
        .toSet();
    final pumpIndexes =
        requestedPumpIndexes.isEmpty ? validPumpIndexes : requestedPumpIndexes;
    if (pumpIndexes.isEmpty) return null;

    final recommendedByPumpIndex = {
      for (final item in recommendations)
        item.pumpIndex: item.recommendedSeconds,
    };
    final maxDoseSeconds = pumpIndexes
        .map((pumpIndex) => recommendedByPumpIndex[pumpIndex] ?? 1)
        .reduce((a, b) => a > b ? a : b);
    final maxSafeSeconds = pumpIndexes
        .map((pumpIndex) => _maxSafeSecondsForPump(pumpIndex, input))
        .reduce((a, b) => a < b ? a : b);
    final maxAllowedSeconds =
        maxDoseSeconds < maxSafeSeconds ? maxDoseSeconds : maxSafeSeconds;
    final durationSeconds =
        schedule.durationSeconds.clamp(1, maxAllowedSeconds).toInt();
    final wasAdjusted = durationSeconds != schedule.durationSeconds ||
        pumpIndexes.length != schedule.pumpIndexes.length;

    return DailyFertilizationScheduleRecommendation(
      hour: schedule.hour,
      minute: schedule.minute,
      pumpIndexes: pumpIndexes,
      durationSeconds: durationSeconds,
      reason: [
        schedule.reason.isEmpty
            ? 'Jadwal dipilih Gemini dari data historis, kebutuhan tanaman, dan debit pompa.'
            : schedule.reason,
        if (wasAdjusted)
          'Durasi/pompa dijaga dalam batas aman aplikasi berdasarkan rekomendasi dosis dan debit masing-masing pompa.',
      ].join(' '),
    );
  }

  static Map<String, dynamic> _safetyBoundsToJson(
    AiRecommendationAgronomicInput input,
  ) {
    return {
      'gradual_correction_fraction': _gradualCorrectionFraction,
      'max_seconds_per_pump': _maxPumpRunSeconds,
      'max_volume_ml_per_pump': {
        for (final item in PumpFlowRates.values)
          item.pumpName:
              _roundDouble(item.averageMlPerSecond * _maxPumpRunSeconds),
      },
      'max_safe_seconds_by_pump_index': {
        for (final item in PumpFlowRates.values)
          item.pumpIndex.toString(): _maxSafeSecondsForPump(
            item.pumpIndex,
            input,
          ),
      },
      'recommended_schedule_hour_range': '05:00-17:59',
      'estimated_soil_mass_kg': _roundDouble(_estimatedSoilMassKg(input)),
    };
  }

  static Map<String, num> _thresholdsFor(
    AiRecommendationAgronomicInput input,
  ) {
    return input.plantType.thresholds;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static String? _nonEmptyText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static Map<String, dynamic>? _tryDecodeJsonObject(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  static bool _shouldUseLocalFallback(Object error) {
    return _isDailyRequestLimitError(error);
  }

  static bool _isDailyRequestLimitError(Object error) {
    final text = error.toString().toLowerCase();
    final compact = text.replaceAll(RegExp(r'[\s_\-]'), '');
    final hasLimitSignal = text.contains('429') ||
        text.contains('quota') ||
        text.contains('resource exhausted') ||
        text.contains('rate limit') ||
        text.contains('rate-limit');
    final hasDailySignal = text.contains('requests per day') ||
        text.contains('request per day') ||
        text.contains('per day') ||
        text.contains('daily') ||
        text.contains('rpd') ||
        compact.contains('requestsperday') ||
        compact.contains('requestperday');

    return hasLimitSignal && hasDailySignal;
  }

  static Future<_GeminiContentResult> _generateContentWithModelFallback(
    _GeminiRuntimeConfig config,
    List<Content> contents,
  ) async {
    Object? lastError;

    for (final modelName in _candidateModelNames(config.modelName)) {
      final model = _buildModel(config, modelName);
      try {
        final response = await _generateContentWithRetry(
          model,
          contents,
          modelName: modelName,
        );
        return _GeminiContentResult(
          modelName: modelName,
          response: response,
        );
      } on Object catch (error) {
        lastError = error;
        if (_shouldUseLocalFallback(error) || !_shouldTryFallbackModel(error)) {
          rethrow;
        }
        debugPrint(
          'Gemini model $modelName failed, trying fallback model: $error',
        );
      }
    }

    debugPrint('All Gemini fallback models failed: $lastError');
    throw AiRecommendationException(
      '$_busyMessage Semua model Gemini cadangan sudah dicoba otomatis.',
    );
  }

  static GenerativeModel _buildModel(
    _GeminiRuntimeConfig config,
    String modelName,
  ) {
    final generationConfig = _shouldSendTemperature(modelName)
        ? GenerationConfig(
            temperature: 0.35,
            maxOutputTokens: 8192,
            responseMimeType: 'application/json',
            responseSchema: _responseSchema,
          )
        : GenerationConfig(
            maxOutputTokens: 8192,
            responseMimeType: 'application/json',
            responseSchema: _responseSchema,
          );

    return GenerativeModel(
      model: modelName,
      apiKey: config.apiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: generationConfig,
    );
  }

  static List<String> _candidateModelNames(String primaryModelName) {
    final names = <String>[];

    void addIfMissing(String modelName) {
      final normalized = modelName.trim();
      if (normalized.isEmpty || names.contains(normalized)) return;
      names.add(normalized);
    }

    addIfMissing(primaryModelName);
    for (final fallbackModelName in _fallbackModelNames) {
      addIfMissing(fallbackModelName);
    }
    return names;
  }

  static Future<dynamic> _generateContentWithRetry(
    GenerativeModel model,
    List<Content> contents, {
    required String modelName,
  }) async {
    final startedAt = DateTime.now();
    var attempt = 0;
    Object? lastError;

    while (attempt < _maxRetryAttempts &&
        DateTime.now().difference(startedAt) < _requestTimeout) {
      attempt += 1;
      final remaining = _requestTimeout - DateTime.now().difference(startedAt);
      if (remaining <= Duration.zero) break;
      final attemptTimeout =
          remaining < _singleAttemptTimeout ? remaining : _singleAttemptTimeout;

      try {
        return await model.generateContent(contents).timeout(attemptTimeout);
      } on Object catch (error) {
        lastError = error;
        if (!_shouldRetryAiRequest(error)) rethrow;
        if (attempt >= _maxRetryAttempts) break;

        final delay = _retryDelay(attempt);
        final remainingAfterDelay =
            _requestTimeout - DateTime.now().difference(startedAt);
        if (remainingAfterDelay <= delay) break;
        debugPrint(
          'Gemini $modelName attempt $attempt failed, retrying in '
          '${delay.inSeconds}s: $error',
        );
        await Future<void>.delayed(delay);
      }
    }

    debugPrint(
      'Gemini $modelName failed after $attempt attempt(s): $lastError',
    );
    throw AiRecommendationException(
      '$_busyMessage Gemini $modelName sudah dicoba otomatis beberapa kali.',
    );
  }

  static bool _shouldRetryAiRequest(Object error) {
    if (error is TimeoutException) return true;
    if (_isDailyRequestLimitError(error)) return false;

    final text = error.toString().toLowerCase();
    return text.contains('503') ||
        text.contains('429') ||
        text.contains('rate limit') ||
        text.contains('rate-limit') ||
        text.contains('resource exhausted') ||
        text.contains('server error') ||
        text.contains('unavailable') ||
        text.contains('overloaded') ||
        text.contains('traffic') ||
        text.contains('timeout');
  }

  static bool _shouldTryFallbackModel(Object error) {
    if (_isDailyRequestLimitError(error)) return false;
    if (error is TimeoutException || error is AiRecommendationException) {
      return true;
    }

    final text = error.toString().toLowerCase();
    return _shouldRetryAiRequest(error) ||
        text.contains('400') ||
        text.contains('404') ||
        text.contains('invalid argument') ||
        text.contains('model not found') ||
        text.contains('not found') ||
        text.contains('not supported');
  }

  static bool _shouldSendTemperature(String modelName) {
    final normalized = modelName.toLowerCase();
    return !normalized.contains('3.6') &&
        !normalized.contains('3.5-flash-lite');
  }

  static Duration _retryDelay(int attempt) {
    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
    ];
    if (attempt <= delays.length) return delays[attempt - 1];
    return delays.last;
  }

  static Map<String, dynamic> _buildLocalFallbackResponse(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final items = <Map<String, dynamic>>[];
    final dynamicFertilizerDoses = _buildDynamicFertilizerDoses(
      summary,
      input,
      activeThresholds,
    );
    final dynamicPumpIndexes =
        dynamicFertilizerDoses.map((item) => item.pumpIndex).toSet();

    void addItem({
      required String id,
      required String title,
      required String status,
      required String message,
      required String explanation,
      required String recommendation,
    }) {
      items.add({
        'id': id,
        'title': title,
        'status': status,
        'message': message,
        'explanation': explanation,
        'recommendation': recommendation,
      });
    }

    void evaluateRange({
      required String key,
      required String label,
      required String unit,
      required num min,
      required num max,
      required String lowTitle,
      required String highTitle,
      required String lowAction,
      required String highAction,
      required String normalAction,
    }) {
      final stats = summary.parameters[key];
      final current = stats?.current;
      if (stats == null || current == null) return;

      final currentText = _formatNumber(current);
      final avgText = _formatNullable(stats.average);
      final trendText = _translateTrend(stats.trend);
      if (current < min) {
        addItem(
          id: '${key.toLowerCase()}_low',
          title: lowTitle,
          status: 'kritis',
          message:
              '$label saat ini $currentText $unit, di bawah batas minimum ${_formatNumber(min)} $unit.',
          explanation:
              'Nilai terakhir $label berada di bawah ambang dan rata-rata data terbaru adalah $avgText $unit dengan tren $trendText. Kondisi ini dapat membatasi penyerapan hara, pertumbuhan akar/daun, atau stabilitas media tanam sesuai parameter yang terdampak.',
          recommendation: lowAction,
        );
      } else if (current > max) {
        addItem(
          id: '${key.toLowerCase()}_high',
          title: highTitle,
          status: 'awas',
          message:
              '$label saat ini $currentText $unit, di atas batas maksimum ${_formatNumber(max)} $unit.',
          explanation:
              'Nilai terakhir $label melewati ambang atas dan rata-rata data terbaru adalah $avgText $unit dengan tren $trendText. Jika kondisi ini berlanjut, tanaman dapat mengalami stres lingkungan atau ketidakseimbangan nutrisi.',
          recommendation: highAction,
        );
      } else {
        addItem(
          id: '${key.toLowerCase()}_normal',
          title: '$label dalam Rentang Aman',
          status: 'baik',
          message:
              '$label saat ini $currentText $unit dan masih berada dalam rentang target.',
          explanation:
              'Nilai terakhir masih berada di antara ${_formatNumber(min)}-${_formatNumber(max)} $unit, dengan rata-rata $avgText $unit dan tren $trendText. Parameter ini belum menunjukkan kebutuhan koreksi mendesak.',
          recommendation: normalAction,
        );
      }
    }

    evaluateRange(
      key: 'N',
      label: 'Estimasi Nitrogen',
      unit: 'mg/kg',
      min: activeThresholds['nitrogen_min']!,
      max: activeThresholds['nitrogen_max']!,
      lowTitle: 'Tren Nitrogen Rendah',
      highTitle: 'Tren Nitrogen Tinggi',
      lowAction:
          'Gunakan tren N sebagai analisis pendukung. Pompa A tidak dijalankan hanya dari estimasi N; koreksi nutrisi dilakukan melalui recipe dosing jika EC juga rendah.',
      highAction:
          'Pantau EC dan respons daun ${input.plantType.label}. Jika EC tinggi, tunda pupuk; jika EC normal, perlakukan kenaikan ini sebagai tren sensor cepat, bukan bukti kelebihan N terpisah.',
      normalAction:
          'Pertahankan pemantauan tren N bersama EC, pH, dan kelembapan.',
    );
    evaluateRange(
      key: 'P',
      label: 'Estimasi Fosfor',
      unit: 'mg/kg',
      min: activeThresholds['phosphorus_min']!,
      max: activeThresholds['phosphorus_max']!,
      lowTitle: 'Tren Fosfor Rendah',
      highTitle: 'Tren Fosfor Tinggi',
      lowAction:
          'Gunakan tren P sebagai sinyal pendukung. Pompa B hanya masuk resep nutrisi saat EC rendah, bukan karena estimasi P rendah sendirian.',
      highAction:
          'Pantau EC dan pH media tanam. Jika EC tidak tinggi, jangan menyimpulkan fosfor aktual berlebih dari sensor cepat saja.',
      normalAction: 'Pertahankan pemantauan tren P bersama EC dan pH.',
    );
    evaluateRange(
      key: 'K',
      label: 'Estimasi Kalium',
      unit: 'mg/kg',
      min: activeThresholds['potassium_min']!,
      max: activeThresholds['potassium_max']!,
      lowTitle: 'Tren Kalium Rendah',
      highTitle: 'Tren Kalium Tinggi',
      lowAction:
          'Gunakan tren K untuk memperkuat analisis, tetapi Pompa C hanya dijalankan sebagai bagian resep nutrisi saat EC rendah.',
      highAction:
          'Tunda keputusan koreksi K spesifik sampai EC, kondisi tanaman, atau uji pembanding mendukung. Nilai ini adalah tren sensor cepat.',
      normalAction:
          'Tren K terbaca dalam rentang target; lanjutkan pemantauan bersama EC.',
    );
    evaluateRange(
      key: 'pH',
      label: 'pH',
      unit: 'pH',
      min: activeThresholds['ph_min']!,
      max: activeThresholds['ph_max']!,
      lowTitle: 'pH Terlalu Asam',
      highTitle: 'pH Terlalu Basa',
      lowAction:
          'Naikkan pH secara sangat bertahap menggunakan korektor pH up dosis kecil. Sesuaikan dengan rentang aman ${input.plantType.label} dan hindari koreksi berlebihan.',
      highAction:
          'Turunkan pH secara bertahap menggunakan korektor pH down agar media kembali ke rentang ${input.plantType.label}. Hindari koreksi besar sekaligus karena akar rentan stres terhadap perubahan pH mendadak.',
      normalAction:
          'pH berada pada zona yang sesuai untuk serapan hara ${input.plantType.label}, pertahankan prosedur pemantauan.',
    );
    evaluateRange(
      key: 'Moisture',
      label: 'Kelembapan',
      unit: '%',
      min: activeThresholds['moisture_min']!,
      max: activeThresholds['moisture_max']!,
      lowTitle: 'Kelembapan Media Rendah',
      highTitle: 'Kelembapan Media Tinggi',
      lowAction: _buildWateringLowAction(summary, input, activeThresholds),
      highAction:
          'Tunda penyiraman dan periksa drainase media tanam. Jika kelembapan tetap tinggi, kurangi frekuensi irigasi untuk mencegah akar ${input.plantType.label} kekurangan oksigen.',
      normalAction:
          'Kelembapan media cukup, pertahankan jadwal penyiraman saat ini.',
    );
    evaluateRange(
      key: 'Temp',
      label: 'Suhu',
      unit: '°C',
      min: activeThresholds['temperature_min']!,
      max: activeThresholds['temperature_max']!,
      lowTitle: 'Suhu Terlalu Rendah',
      highTitle: 'Suhu Terlalu Tinggi',
      lowAction:
          'Kurangi paparan dingin dan jaga lingkungan tumbuh ${input.plantType.label} tetap stabil. Pantau suhu bersama kelembapan karena perubahan suhu memengaruhi penguapan media.',
      highAction:
          'Berikan naungan dan tingkatkan ventilasi untuk menurunkan stres panas pada ${input.plantType.label}. Gunakan Pump D Water seperlunya dengan durasi pendek agar media tidak terlalu basah.',
      normalAction:
          'Suhu berada dalam rentang aman, lanjutkan pemantauan normal.',
    );
    evaluateRange(
      key: 'EC',
      label: 'Electrical Conductivity',
      unit: 'mS/cm',
      min: activeThresholds['ec_min']!,
      max: activeThresholds['ec_max']!,
      lowTitle: 'EC Rendah',
      highTitle: 'EC Tinggi',
      lowAction: dynamicFertilizerDoses.isEmpty
          ? 'EC rendah, tetapi kondisi pH/tren/konsentrasi larutan membuat pupuk perlu ditunda atau diberikan sangat hati-hati. Ukur ulang pH dan EC sebelum aktivasi pompa nutrisi.'
          : 'Tambahkan larutan nutrisi secara bertahap melalui ${dynamicFertilizerDoses.map((item) => item.pumpName).join(', ')} sesuai durasi dinamis berbasis EC, pH, tren estimasi NPK, konsentrasi larutan, dan media ${input.plantingMedium.label}.',
      highAction:
          'Encerkan larutan dengan air bersih secara bertahap dan tunda penambahan pupuk. Pantau ulang EC serta pH asam setelah larutan stabil.',
      normalAction:
          'EC stabil untuk ${input.plantType.label}, pertahankan konsentrasi larutan dan pantau perubahan setelah irigasi.',
    );

    final kritis = items
        .where((item) => item['status'] == 'kritis')
        .toList(growable: false);
    final awas =
        items.where((item) => item['status'] == 'awas').toList(growable: false);
    final baik =
        items.where((item) => item['status'] == 'baik').toList(growable: false);
    final scorePenalty = (kritis.length * 15) + (awas.length * 8);

    return {
      'plant_health_percentage': (100 - scorePenalty).clamp(0, 100),
      'sensor_summary':
          'Analisis kondisi tanaman ${input.plantType.label} pada media ${input.plantingMedium.label} mulai dari ${input.analysisWindow.xaiLabel} menunjukkan defisit kelembapan dan EC serta pH yang terlalu basa. Pengukuran nilai N, P, K oleh sensor digunakan sebagai inikator tren estimasi pendukung kontrol nutrisi berbasis EC.',
      'recommendations': {
        'all': items,
        'kritis': kritis,
        'awas': awas,
        'baik': baik,
      },
      'automation_triggers': {
        'activate_nitrogen_pump': dynamicPumpIndexes.contains(0),
        'activate_phosphorus_pump': dynamicPumpIndexes.contains(1),
        'activate_potassium_pump': dynamicPumpIndexes.contains(2),
        'activate_water_pump': summary.canActivateWaterPump(activeThresholds),
        'reason':
            'Trigger pompa N/P/K mengikuti gerbang EC rendah, lalu dipilih dinamis dari pH, tren estimasi NPK, konsentrasi larutan, media, dan batas aman durasi.',
      },
    };
  }

  static Map<String, dynamic> _buildAiUnavailableFallbackResponse(
    SensorHistorySummary summary,
    Object error,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final fallback = _buildLocalFallbackResponse(
      summary,
      input,
      activeThresholds,
    );
    final prefix = _isDailyRequestLimitError(error)
        ? 'Kuota harian Gemini API (RPD) sudah tercapai, sehingga rekomendasi sementara dibuat memakai analisis DSS/XAI lokal.'
        : 'Rekomendasi dibuat memakai analisis DSS/XAI lokal.';

    return {
      ...fallback,
      'sensor_summary': '$prefix ${fallback['sensor_summary']}',
    };
  }

  static List<PumpFertilizationRecommendation> _buildPumpRecommendations(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final recommendations = <PumpFertilizationRecommendation>[];

    void addWaterIfLow({
      required String key,
      required int relay,
      required int pumpIndex,
      required String pumpName,
      required String nutrient,
      required String unit,
      required double minimum,
    }) {
      final current = summary.parameters[key]?.current;
      if (current == null || current >= minimum) return;

      final deficit = _roundDouble(minimum - current);
      final deficitPercent = _roundDouble((deficit / minimum) * 100);

      final currentTemperature = summary.parameters['Temp']?.current;
      final maxTemperature = activeThresholds['temperature_max']?.toDouble();
      final isHighTemp = currentTemperature != null &&
          maxTemperature != null &&
          currentTemperature > maxTemperature;

      final baseTargetVolumeMl = _estimatedWaterVolumeMl(
        currentMoisturePercent: current,
        targetMinimumPercent: minimum,
        input: input,
      );
      final targetVolumeMl = isHighTemp
          ? _roundDouble(baseTargetVolumeMl * 1.15)
          : baseTargetVolumeMl;

      final recommendedSeconds = PumpFlowRates.secondsForVolume(
        pumpIndex: pumpIndex,
        volumeMl: targetVolumeMl,
      ).clamp(1, _maxSafeSecondsForPump(pumpIndex, input)).toInt();
      final flowRate = PumpFlowRates.byPumpIndex(pumpIndex).averageMlPerSecond;
      final estimatedVolumeMl = PumpFlowRates.volumeForDuration(
        pumpIndex: pumpIndex,
        seconds: recommendedSeconds,
      );

      final tempNote = isHighTemp
          ? ' Suhu tanah (${_formatNumber(currentTemperature)} °C) terdeteksi tinggi (di atas ${_formatNumber(maxTemperature)} °C), sehingga durasi disesuaikan +15% untuk kompensasi laju penguapan (evapotranspirasi).'
          : '';

      recommendations.add(
        PumpFertilizationRecommendation(
          relay: relay,
          pumpIndex: pumpIndex,
          pumpName: pumpName,
          nutrient: nutrient,
          unit: unit,
          currentValue: current,
          targetMinimum: minimum,
          deficit: deficit,
          deficitPercent: deficitPercent,
          recommendedSeconds: recommendedSeconds,
          reason:
              '$nutrient saat ini ${_formatNumber(current)} $unit, kurang ${_formatNumber(deficit)} $unit dari ambang minimum ${_formatNumber(minimum)} $unit.$tempNote Estimasi penyiraman memakai area sensor 100 cm2, kedalaman media ${_formatNumber(input.plantingMedium.assumedDepthCm)} cm, dan koreksi bertahap sekitar ${PumpFlowRates.formatMl(targetVolumeMl)} ml; durasi pompa dihitung dari debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk keluaran sekitar ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.',
        ),
      );
    }

    _buildEcRecipePumpRecommendations(
      summary,
      input,
      activeThresholds,
    ).forEach(recommendations.add);

    addWaterIfLow(
      key: 'Moisture',
      relay: 4,
      pumpIndex: 3,
      pumpName: 'Pompa D',
      nutrient: 'Air',
      unit: '%',
      minimum: activeThresholds['moisture_min']!.toDouble(),
    );

    return recommendations;
  }

  static List<PumpFertilizationRecommendation>
      _buildEcRecipePumpRecommendations(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final currentEc = summary.parameters['EC']?.current;
    final minEc = activeThresholds['ec_min']!.toDouble();
    if (currentEc == null || currentEc >= minEc || minEc <= 0) {
      return const [];
    }

    final deficit = _roundDouble(minEc - currentEc);
    final deficitPercent = _roundDouble((deficit / minEc) * 100);

    return _buildDynamicFertilizerDoses(
      summary,
      input,
      activeThresholds,
    )
        .map(
          (dose) => _recipePumpRecommendation(
            dose: dose,
            currentEc: currentEc,
            minEc: minEc,
            deficit: deficit,
            deficitPercent: deficitPercent,
            input: input,
          ),
        )
        .toList(growable: false);
  }

  static PumpFertilizationRecommendation _recipePumpRecommendation({
    required _DynamicFertilizerDose dose,
    required double currentEc,
    required double minEc,
    required double deficit,
    required double deficitPercent,
    required AiRecommendationAgronomicInput input,
  }) {
    final recommendedSeconds = dose.recommendedSeconds;
    final flowRate =
        PumpFlowRates.byPumpIndex(dose.pumpIndex).averageMlPerSecond;
    final estimatedVolumeMl = PumpFlowRates.volumeForDuration(
      pumpIndex: dose.pumpIndex,
      seconds: recommendedSeconds,
    );

    return PumpFertilizationRecommendation(
      relay: dose.relay,
      pumpIndex: dose.pumpIndex,
      pumpName: dose.pumpName,
      nutrient: dose.nutrient,
      unit: 'mS/cm',
      currentValue: currentEc,
      targetMinimum: minEc,
      deficit: deficit,
      deficitPercent: deficitPercent,
      recommendedSeconds: recommendedSeconds,
      reason:
          'EC saat ini ${_formatNumber(currentEc)} mS/cm, kurang ${_formatNumber(deficit)} mS/cm dari ambang minimum ${_formatNumber(minEc)} mS/cm. ${dose.pumpName} dipilih dari analisis dinamis: ${dose.basis}. Durasi $recommendedSeconds detik divalidasi dengan debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk estimasi ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml pada media ${input.plantingMedium.label}.',
    );
  }

  static List<_DynamicFertilizerDose> _buildDynamicFertilizerDoses(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final currentEc = summary.parameters['EC']?.current;
    final minEc = activeThresholds['ec_min']!.toDouble();
    if (currentEc == null || currentEc >= minEc || minEc <= 0) {
      return const [];
    }

    final ecSeverity = _deficitRatio(currentEc, minEc);
    final baseSeconds = _ecRecipeBaseSeconds(ecSeverity * 100);
    final phStats = summary.parameters['pH'];
    final phCurrent = phStats?.current;
    final phMin = activeThresholds['ph_min']!.toDouble();
    final phMax = activeThresholds['ph_max']!.toDouble();
    final climateFactor = _climateFertilizerFactor(summary, activeThresholds);
    final mediumFactor = _mediumFertilizerFactor(input.plantingMedium);
    final concentrations = <int, double>{
      0: input.fertilizerConcentration.nitrogenMgPerLiter,
      1: input.fertilizerConcentration.phosphorusMgPerLiter,
      2: input.fertilizerConcentration.potassiumMgPerLiter,
    };
    final configs = [
      _FertilizerPumpConfig(
        relay: 1,
        pumpIndex: 0,
        pumpName: 'Pompa A',
        nutrient: 'Larutan Nitrogen',
        trendKey: 'N',
        thresholdMinKey: 'nitrogen_min',
        thresholdMaxKey: 'nitrogen_max',
        acidifyingRisk: 1,
        concentrationMgPerLiter: concentrations[0] ?? 0,
        fertilizerNote: 'N/urea cenderung menurunkan pH',
      ),
      _FertilizerPumpConfig(
        relay: 2,
        pumpIndex: 1,
        pumpName: 'Pompa B',
        nutrient: 'Larutan Fosfor',
        trendKey: 'P',
        thresholdMinKey: 'phosphorus_min',
        thresholdMaxKey: 'phosphorus_max',
        acidifyingRisk: 0.55,
        concentrationMgPerLiter: concentrations[1] ?? 0,
        fertilizerNote: 'P sedang dipengaruhi ketersediaan pH',
      ),
      _FertilizerPumpConfig(
        relay: 3,
        pumpIndex: 2,
        pumpName: 'Pompa C',
        nutrient: 'Larutan Kalium',
        trendKey: 'K',
        thresholdMinKey: 'potassium_min',
        thresholdMaxKey: 'potassium_max',
        acidifyingRisk: 0.2,
        concentrationMgPerLiter: concentrations[2] ?? 0,
        fertilizerNote: 'K relatif lebih netral terhadap pH',
      ),
    ];

    final doses = <_DynamicFertilizerDose>[];
    for (final config in configs) {
      final concentration = config.concentrationMgPerLiter;
      if (!concentration.isFinite || concentration <= 0) continue;

      final trendStats = summary.parameters[config.trendKey];
      final nutrientSeverity = _nutrientTrendSeverity(
        trendStats,
        activeThresholds[config.thresholdMinKey]!.toDouble(),
        activeThresholds[config.thresholdMaxKey]!.toDouble(),
      );
      final phFactor = _phFertilizerFactor(
        currentPh: phCurrent,
        minPh: phMin,
        maxPh: phMax,
        acidifyingRisk: config.acidifyingRisk,
      );
      final concentrationFactor = _concentrationDurationFactor(concentration);
      final concentrationNote = _concentrationDoseNote(concentration);
      final suitabilityScore = _fertilizerSuitabilityScore(
        ecSeverity: ecSeverity,
        nutrientSeverity: nutrientSeverity,
        phFactor: phFactor,
        climateFactor: climateFactor,
      );

      final shouldSkip = _shouldSkipFertilizerDose(
        ecSeverity: ecSeverity,
        nutrientSeverity: nutrientSeverity,
        phFactor: phFactor,
        acidifyingRisk: config.acidifyingRisk,
      );
      if (shouldSkip) continue;

      final severityFactor =
          (0.60 + (ecSeverity * 0.55) + (nutrientSeverity * 0.40))
              .clamp(0.35, 1.65)
              .toDouble();
      final rawSeconds = baseSeconds *
          concentrationFactor *
          severityFactor *
          phFactor *
          climateFactor *
          mediumFactor;
      final maxSafeSeconds = _maxSafeSecondsForPump(config.pumpIndex, input);
      final recommendedSeconds =
          rawSeconds.round().clamp(1, maxSafeSeconds).toInt();

      doses.add(
        _DynamicFertilizerDose(
          relay: config.relay,
          pumpIndex: config.pumpIndex,
          pumpName: config.pumpName,
          nutrient: config.nutrient,
          trendKey: config.trendKey,
          concentrationMgPerLiter: concentration,
          recommendedSeconds: recommendedSeconds,
          suitabilityScore: _roundDouble(suitabilityScore),
          ecSeverity: _roundDouble(ecSeverity),
          nutrientTrendSeverity: _roundDouble(nutrientSeverity),
          concentrationFactor: _roundDouble(concentrationFactor),
          phFactor: _roundDouble(phFactor),
          mediumFactor: _roundDouble(mediumFactor),
          climateFactor: _roundDouble(climateFactor),
          concentrationNote: concentrationNote,
          basis:
              'defisit EC ${_formatNumber(ecSeverity * 100)}%, tren estimasi ${config.trendKey} ${_formatNumber(nutrientSeverity * 100)}%, konsentrasi larutan ${_formatNumber(concentration)} mg/L dibanding baseline ${_formatNumber(_doseBaselineConcentrationMgPerLiter)} mg/L, faktor konsentrasi ${_formatNumber(concentrationFactor)} ($concentrationNote), faktor pH ${_formatNumber(phFactor)} (${config.fertilizerNote}), faktor media ${_formatNumber(mediumFactor)}, dan faktor suhu/kelembapan ${_formatNumber(climateFactor)}',
        ),
      );
    }

    doses.sort((a, b) => b.suitabilityScore.compareTo(a.suitabilityScore));
    return doses;
  }

  static List<XaiFeatureContribution> _buildHistoricalShapContributions(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
    List<PumpFertilizationRecommendation> pumpRecommendations,
  ) {
    if (pumpRecommendations.isEmpty) return const [];

    final hasFertilizer = pumpRecommendations
        .any((item) => item.relay >= 1 && item.relay <= 3);
    final hasWater = pumpRecommendations.any((item) => item.relay == 4);
    final items = <XaiFeatureContribution>[];

    void add({
      required String feature,
      required String label,
      required double contribution,
      required double featureValue,
      required double featureValueRatio,
      required String direction,
      required String detail,
    }) {
      if (!contribution.isFinite || contribution.abs() < 0.05) return;
      items.add(
        XaiFeatureContribution(
          feature: feature,
          label: label,
          contribution: _roundDouble(contribution.clamp(-6.0, 6.0).toDouble()),
          featureValue: _roundDouble(featureValue),
          featureValueRatio: featureValueRatio.clamp(0.0, 1.0).toDouble(),
          direction: direction,
          detail: detail,
        ),
      );
    }

    final ec = summary.parameters['EC'];
    final ecCurrent = ec?.current;
    final ecMin = activeThresholds['ec_min']!.toDouble();
    final ecMax = activeThresholds['ec_max']!.toDouble();
    if (ecCurrent != null) {
      final lowSeverity = _deficitRatio(ecCurrent, ecMin);
      final highSeverity = _excessRatio(ecCurrent, ecMax);
      if (lowSeverity > 0) {
        add(
          feature: 'ec_deficit',
          label: 'EC rendah',
          contribution: 1.4 + (lowSeverity * 5.2),
          featureValue: ecCurrent,
          featureValueRatio: _rangeValueRatio(ecCurrent, ecMin, ecMax),
          direction: 'Mendorong pemupukan',
          detail:
              'EC historis/current berada di bawah target, sehingga membuka gerbang rekomendasi nutrisi.',
        );
      } else if (highSeverity > 0) {
        add(
          feature: 'ec_high',
          label: 'EC tinggi',
          contribution: -(1.2 + highSeverity * 4.5),
          featureValue: ecCurrent,
          featureValueRatio: _rangeValueRatio(ecCurrent, ecMin, ecMax),
          direction: 'Menahan pupuk',
          detail:
              'EC berada di atas target, sehingga pupuk ditahan untuk mencegah over-fertilization.',
        );
      } else if (hasFertilizer) {
        add(
          feature: 'ec_safe_gate',
          label: 'EC dalam kendali',
          contribution: 0.6,
          featureValue: ecCurrent,
          featureValueRatio: _rangeValueRatio(ecCurrent, ecMin, ecMax),
          direction: 'Mendukung ringan',
          detail:
              'EC masih menjadi sinyal utama sebelum fitur lain menyesuaikan durasi.',
        );
      }
    }

    void addNpkTrend({
      required String key,
      required String label,
      required String minKey,
      required String maxKey,
      required int relay,
    }) {
      final stats = summary.parameters[key];
      final current = stats?.current;
      if (stats == null || current == null) return;

      final min = activeThresholds[minKey]!.toDouble();
      final max = activeThresholds[maxKey]!.toDouble();
      final severity = _nutrientTrendSeverity(stats, min, max);
      final pumpSelected =
          pumpRecommendations.any((item) => item.relay == relay);
      final trendBoost = stats.trend == 'decreasing' ? 0.55 : 0.0;
      final contribution = severity >= 0
          ? (severity * (pumpSelected ? 4.4 : 2.4)) + trendBoost
          : severity * 4.0;
      add(
        feature: '${key.toLowerCase()}_estimated_trend',
        label: 'Tren estimasi $label',
        contribution: contribution,
        featureValue: current,
        featureValueRatio: _rangeValueRatio(current, min, max),
        direction: contribution >= 0 ? 'Mendorong prioritas' : 'Menahan',
        detail:
            'Dihitung dari nilai terakhir, rata-rata historis, dan tren ${_translateTrend(stats.trend)} terhadap ambang $label.',
      );
    }

    addNpkTrend(
      key: 'N',
      label: 'N',
      minKey: 'nitrogen_min',
      maxKey: 'nitrogen_max',
      relay: 1,
    );
    addNpkTrend(
      key: 'P',
      label: 'P',
      minKey: 'phosphorus_min',
      maxKey: 'phosphorus_max',
      relay: 2,
    );
    addNpkTrend(
      key: 'K',
      label: 'K',
      minKey: 'potassium_min',
      maxKey: 'potassium_max',
      relay: 3,
    );

    final ph = summary.parameters['pH'];
    final phCurrent = ph?.current;
    final phMin = activeThresholds['ph_min']!.toDouble();
    final phMax = activeThresholds['ph_max']!.toDouble();
    if (phCurrent != null) {
      final acidSeverity = _deficitRatio(phCurrent, phMin);
      final baseSeverity = _excessRatio(phCurrent, phMax);
      if (acidSeverity > 0) {
        add(
          feature: 'ph_acid_risk',
          label: 'pH terlalu asam',
          contribution: -(1.0 + acidSeverity * 5.0),
          featureValue: phCurrent,
          featureValueRatio: _rangeValueRatio(phCurrent, phMin, phMax),
          direction: 'Menahan durasi',
          detail:
              'pH asam menahan dosis, terutama pada pupuk yang berisiko menurunkan pH.',
        );
      } else if (baseSeverity > 0) {
        add(
          feature: 'ph_high',
          label: 'pH terlalu basa',
          contribution: -1.0 - (baseSeverity * 2.2),
          featureValue: phCurrent,
          featureValueRatio: _rangeValueRatio(phCurrent, phMin, phMax),
          direction: 'Menahan durasi',
          detail:
              'pH basa membuat koreksi nutrisi tetap bertahap sambil memantau ketersediaan hara.',
        );
      } else if (hasFertilizer) {
        add(
          feature: 'ph_safe',
          label: 'pH dalam rentang',
          contribution: 0.8,
          featureValue: phCurrent,
          featureValueRatio: _rangeValueRatio(phCurrent, phMin, phMax),
          direction: 'Mendukung ringan',
          detail:
              'pH berada dalam rentang aman sehingga tidak banyak menahan rekomendasi nutrisi.',
        );
      }
    }

    final moisture = summary.parameters['Moisture'];
    final moistureCurrent = moisture?.current;
    final moistureMin = activeThresholds['moisture_min']!.toDouble();
    final moistureMax = activeThresholds['moisture_max']!.toDouble();
    if (moistureCurrent != null) {
      final severity = _deficitRatio(moistureCurrent, moistureMin);
      if (severity > 0) {
        add(
          feature: 'moisture_deficit',
          label: 'Kelembapan rendah',
          contribution: hasWater ? 1.2 + (severity * 4.8) : -(severity * 2.2),
          featureValue: moistureCurrent,
          featureValueRatio:
              _rangeValueRatio(moistureCurrent, moistureMin, moistureMax),
          direction: hasWater ? 'Mendorong air' : 'Menahan pupuk',
          detail:
              'Kelembapan rendah dari data historis mendorong air atau membuat pupuk lebih hati-hati.',
        );
      }
    }

    final temp = summary.parameters['Temp'];
    final tempCurrent = temp?.current;
    final tempMin = activeThresholds['temperature_min']!.toDouble();
    final tempMax = activeThresholds['temperature_max']!.toDouble();
    if (tempCurrent != null) {
      final hotSeverity = _excessRatio(tempCurrent, tempMax);
      if (hotSeverity > 0) {
        add(
          feature: 'soil_temperature_high',
          label: 'Suhu tanah tinggi',
          contribution:
              hasWater ? 1.0 + (hotSeverity * 4.5) : -(hotSeverity * 2.0),
          featureValue: tempCurrent,
          featureValueRatio: _rangeValueRatio(tempCurrent, tempMin, tempMax),
          direction: hasWater ? 'Mendorong air' : 'Menahan pupuk',
          detail:
              'Suhu tinggi pada histori mendorong penyiraman ringan atau menahan pemupukan.',
        );
      }
    }

    void addConcentration({
      required String key,
      required String label,
      required double concentration,
      required int relay,
    }) {
      if (concentration <= 0 ||
          !pumpRecommendations.any((item) => item.relay == relay)) {
        return;
      }
      final factor = _concentrationDurationFactor(concentration);
      final contribution = factor >= 1
          ? (factor - 1).clamp(0.2, 6.0).toDouble()
          : -((1 - factor) * 5.0).clamp(0.2, 5.6).toDouble();
      add(
        feature: '${key}_solution_concentration',
        label: 'Konsentrasi larutan $label',
        contribution: contribution,
        featureValue: concentration,
        featureValueRatio: (concentration /
                (concentration + _doseBaselineConcentrationMgPerLiter))
            .clamp(0.0, 1.0)
            .toDouble(),
        direction: contribution >= 0 ? 'Menaikkan durasi' : 'Menurunkan durasi',
        detail:
            'Dibanding baseline ${_formatNumber(_doseBaselineConcentrationMgPerLiter)} mg/L; larutan pekat menurunkan durasi, larutan encer menaikkan durasi.',
      );
    }

    addConcentration(
      key: 'n',
      label: 'N',
      concentration: input.fertilizerConcentration.nitrogenMgPerLiter,
      relay: 1,
    );
    addConcentration(
      key: 'p',
      label: 'P',
      concentration: input.fertilizerConcentration.phosphorusMgPerLiter,
      relay: 2,
    );
    addConcentration(
      key: 'k',
      label: 'K',
      concentration: input.fertilizerConcentration.potassiumMgPerLiter,
      relay: 3,
    );

    final mediumFactor = _mediumFertilizerFactor(input.plantingMedium);
    if (hasFertilizer && mediumFactor < 0.98) {
      add(
        feature: 'planting_medium',
        label: 'Media ${input.plantingMedium.label}',
        contribution: -((1 - mediumFactor) * 5.0).clamp(0.2, 4.0).toDouble(),
        featureValue: mediumFactor,
        featureValueRatio: mediumFactor.clamp(0.0, 1.0).toDouble(),
        direction: 'Menahan durasi',
        detail:
            'Profil media historis/input membuat koreksi pupuk dilakukan lebih bertahap.',
      );
    }

    if (hasFertilizer || hasWater) {
      add(
        feature: 'plant_type_threshold',
        label: 'Jenis tanaman ${input.plantType.label}',
        contribution: 0.75,
        featureValue: 1,
        featureValueRatio: 0.75,
        direction: 'Mengatur ambang',
        detail:
            'Jenis tanaman menentukan ambang EC, pH, suhu, dan kelembapan yang dipakai model.',
      );
    }

    items.sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));
    return items.take(8).toList(growable: false);
  }

  static Map<String, dynamic> _dynamicFertilizerDoseReferenceToJson(
    List<_DynamicFertilizerDose> doses,
  ) {
    return {
      'method':
          'EC-gated dose-aware reference. EC low opens the nutrient gate; each pump uses duration_factor = 100 mg/L / fertilizer_concentration_mg_per_liter, then adjusts by estimated N/P/K trend, pH risk, medium, temperature, moisture, pump flow, and local safety bounds.',
      'baseline_concentration_mg_per_liter':
          _doseBaselineConcentrationMgPerLiter,
      'concentration_factor_clamp_range': [
        _minConcentrationDurationFactor,
        _maxConcentrationDurationFactor,
      ],
      'items': doses
          .map(
            (item) => {
              'relay': item.relay,
              'pump_index': item.pumpIndex,
              'pump_name': item.pumpName,
              'nutrient': item.nutrient,
              'trend_key': item.trendKey,
              'fertilizer_concentration_mg_per_liter':
                  item.concentrationMgPerLiter,
              'recommended_seconds': item.recommendedSeconds,
              'suitability_score': item.suitabilityScore,
              'ec_severity': item.ecSeverity,
              'estimated_npk_trend_severity': item.nutrientTrendSeverity,
              'concentration_factor': item.concentrationFactor,
              'concentration_note': item.concentrationNote,
              'ph_factor': item.phFactor,
              'medium_factor': item.mediumFactor,
              'climate_factor': item.climateFactor,
              'basis': item.basis,
            },
          )
          .toList(growable: false),
    };
  }

  static double _deficitRatio(double current, double minimum) {
    if (minimum <= 0 || current >= minimum) return 0;
    return ((minimum - current) / minimum).clamp(0.0, 1.0).toDouble();
  }

  static double _excessRatio(double current, double maximum) {
    if (maximum <= 0 || current <= maximum) return 0;
    return ((current - maximum) / maximum).clamp(0.0, 1.0).toDouble();
  }

  static double _rangeValueRatio(double current, double minimum, double maximum) {
    if (maximum <= minimum) return 0.5;
    return ((current - minimum) / (maximum - minimum))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static double _nutrientTrendSeverity(
    _ParameterStats? stats,
    double minimum,
    double maximum,
  ) {
    final current = stats?.current;
    if (stats == null || current == null || minimum <= 0) return 0.25;
    if (current > maximum && maximum > 0) return -0.35;

    var severity = current < minimum ? _deficitRatio(current, minimum) : 0.10;
    final average = stats.average;
    if (average != null && average < minimum) {
      severity += _deficitRatio(average, minimum) * 0.35;
    }
    if (stats.trend == 'decreasing') {
      severity += 0.18;
    } else if (stats.trend == 'increasing') {
      severity -= 0.08;
    }
    return severity.clamp(-0.35, 1.0).toDouble();
  }

  static double _concentrationDurationFactor(double concentration) {
    if (concentration <= 0) return 1;
    return (_doseBaselineConcentrationMgPerLiter / concentration)
        .clamp(
          _minConcentrationDurationFactor,
          _maxConcentrationDurationFactor,
        )
        .toDouble();
  }

  static String _concentrationDoseNote(double concentration) {
    if (concentration <= 0) return 'larutan tidak digunakan';
    final rawFactor = _doseBaselineConcentrationMgPerLiter / concentration;
    if (rawFactor > _maxConcentrationDurationFactor) {
      return 'larutan sangat encer; kebutuhan durasi dibatasi oleh batas aman';
    }
    if (rawFactor < _minConcentrationDurationFactor) {
      return 'larutan sangat pekat; durasi dipertahankan sebagai pulsa minimum aman';
    }
    if (rawFactor > 1) {
      return 'lebih encer dari baseline sehingga durasi dinaikkan';
    }
    if (rawFactor < 1) {
      return 'lebih pekat dari baseline sehingga durasi diturunkan';
    }
    return 'setara baseline kalibrasi';
  }

  static double _phFertilizerFactor({
    required double? currentPh,
    required double minPh,
    required double maxPh,
    required double acidifyingRisk,
  }) {
    if (currentPh == null || minPh <= 0 || maxPh <= 0) return 1;
    if (currentPh < minPh) {
      final acidGap = (minPh - currentPh).clamp(0.0, 1.5).toDouble();
      final reduction = acidGap >= 0.45
          ? 0.75
          : acidGap >= 0.20
              ? 0.55
              : 0.35;
      return (1 - (acidifyingRisk * reduction)).clamp(0.20, 1.0).toDouble();
    }
    if (currentPh > maxPh) {
      return (1 + (acidifyingRisk * 0.08)).clamp(1.0, 1.08).toDouble();
    }
    if (currentPh <= minPh + 0.20) {
      return (1 - (acidifyingRisk * 0.18)).clamp(0.70, 1.0).toDouble();
    }
    return 1;
  }

  static double _climateFertilizerFactor(
    SensorHistorySummary summary,
    Map<String, num> activeThresholds,
  ) {
    var factor = 1.0;
    final moisture = summary.parameters['Moisture']?.current;
    final minMoisture = activeThresholds['moisture_min']!.toDouble();
    if (moisture != null && moisture < minMoisture) factor *= 0.85;

    final temperature = summary.parameters['Temp']?.current;
    final maxTemperature = activeThresholds['temperature_max']!.toDouble();
    if (temperature != null && temperature > maxTemperature) factor *= 0.82;

    return factor.clamp(0.65, 1.0).toDouble();
  }

  static double _mediumFertilizerFactor(PlantingMediumProfile medium) {
    switch (medium.id) {
      case 'clay_soil':
        return 0.80;
      case 'potting_mix':
        return 0.88;
      case 'sandy_fast_drying_soil':
        return 0.92;
      case 'raised_bed':
        return 0.95;
      case 'loam_soil':
        return 1.0;
      default:
        return 0.90;
    }
  }

  static double _fertilizerSuitabilityScore({
    required double ecSeverity,
    required double nutrientSeverity,
    required double phFactor,
    required double climateFactor,
  }) {
    return ((ecSeverity * 0.50) +
            (nutrientSeverity.clamp(0.0, 1.0) * 0.35) +
            (phFactor * 0.10) +
            (climateFactor * 0.05))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static bool _shouldSkipFertilizerDose({
    required double ecSeverity,
    required double nutrientSeverity,
    required double phFactor,
    required double acidifyingRisk,
  }) {
    if (nutrientSeverity < -0.20 && ecSeverity < 0.75) return true;
    if (acidifyingRisk >= 0.9 &&
        phFactor <= 0.35 &&
        nutrientSeverity < 0.55 &&
        ecSeverity < 0.80) {
      return true;
    }
    return false;
  }

  static int _ecRecipeBaseSeconds(double deficitPercent) {
    if (deficitPercent <= 30) return 1;
    if (deficitPercent <= 60) return 2;
    return 3;
  }

  static String _buildWateringLowAction(
    SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final current = summary.parameters['Moisture']?.current;
    final minimum = activeThresholds['moisture_min']!.toDouble();
    if (current == null || current >= minimum) {
      return 'Pertahankan penyiraman bertahap dan pastikan media ${input.plantType.label} lembap merata tetapi tidak tergenang.';
    }

    final waterVolumeMl = _estimatedWaterVolumeMl(
      currentMoisturePercent: current,
      targetMinimumPercent: minimum,
      input: input,
    );
    final seconds = PumpFlowRates.secondsForVolume(
      pumpIndex: 3,
      volumeMl: waterVolumeMl,
    ).clamp(1, _maxSafeSecondsForPump(3, input));

    return 'Aktifkan Pump D Water sekitar $seconds detik sebagai penyiraman bertahap awal untuk area sensor 100 cm2 dengan estimasi kebutuhan ${PumpFlowRates.formatMl(waterVolumeMl)} ml. Asumsi media ${input.plantingMedium.label} dipakai karena kedalaman aktual belum tersedia; ukur ulang kelembapan setelah larutan merata.';
  }

  static double _estimatedWaterVolumeMl({
    required double currentMoisturePercent,
    required double targetMinimumPercent,
    required AiRecommendationAgronomicInput input,
  }) {
    final safeArea =
        input.landAreaSquareMeters <= 0 ? 0 : input.landAreaSquareMeters;
    final depthMeters = input.plantingMedium.assumedDepthCm <= 0
        ? 0
        : input.plantingMedium.assumedDepthCm / 100;
    final localMediumVolumeMl = safeArea * depthMeters * 1000000;
    final safeCurrent = currentMoisturePercent.clamp(0, 100).toDouble();
    final safeTarget = targetMinimumPercent.clamp(0, 100).toDouble();
    final deficitFraction = ((safeTarget - safeCurrent) / 100).clamp(0, 1);
    final volumeMl =
        localMediumVolumeMl * deficitFraction * _gradualCorrectionFraction;
    return _roundDouble(volumeMl < 1 ? 1 : volumeMl);
  }

  static double _estimatedSoilMassKg(AiRecommendationAgronomicInput input) {
    final safeArea =
        input.landAreaSquareMeters <= 0 ? 0 : input.landAreaSquareMeters;
    final depthMeters = input.plantingMedium.assumedDepthCm / 100;
    return safeArea * depthMeters * input.plantingMedium.bulkDensityKgPerM3;
  }

  static int _maxSafeSecondsForPump(
    int pumpIndex,
    AiRecommendationAgronomicInput input,
  ) {
    return _maxPumpRunSeconds;
  }

  static _PumpMetadata? _pumpMetadata(
    int relay,
    Map<String, num> activeThresholds,
  ) {
    switch (relay) {
      case 1:
        return _PumpMetadata(
          sensorKey: 'EC',
          relay: 1,
          pumpIndex: 0,
          pumpName: 'Pompa A',
          nutrient: 'Larutan Nitrogen',
          unit: 'mS/cm',
          minimum: activeThresholds['ec_min']!.toDouble(),
        );
      case 2:
        return _PumpMetadata(
          sensorKey: 'EC',
          relay: 2,
          pumpIndex: 1,
          pumpName: 'Pompa B',
          nutrient: 'Larutan Fosfor',
          unit: 'mS/cm',
          minimum: activeThresholds['ec_min']!.toDouble(),
        );
      case 3:
        return _PumpMetadata(
          sensorKey: 'EC',
          relay: 3,
          pumpIndex: 2,
          pumpName: 'Pompa C',
          nutrient: 'Larutan Kalium',
          unit: 'mS/cm',
          minimum: activeThresholds['ec_min']!.toDouble(),
        );
      case 4:
        return _PumpMetadata(
          sensorKey: 'Moisture',
          relay: 4,
          pumpIndex: 3,
          pumpName: 'Pompa D',
          nutrient: 'Air',
          unit: '%',
          minimum: activeThresholds['moisture_min']!.toDouble(),
        );
      default:
        return null;
    }
  }

  static int _readJsonInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readJsonDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _roundDouble(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static String _formatNullable(double? value) {
    if (value == null) return 'tidak tersedia';
    return _formatNumber(value);
  }

  static String _formatNumber(num value) {
    final rounded = value.toDouble().toStringAsFixed(4);
    return rounded.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _translateTrend(String trend) {
    switch (trend) {
      case 'increasing':
        return 'meningkat';
      case 'decreasing':
        return 'menurun';
      case 'stable':
        return 'stabil';
      default:
        return 'belum tersedia';
    }
  }

  static String _shortPreview(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 220) return normalized;
    return '${normalized.substring(0, 220)}...';
  }
}

class AiRecommendationException implements Exception {
  const AiRecommendationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PumpMetadata {
  const _PumpMetadata({
    required this.sensorKey,
    required this.relay,
    required this.pumpIndex,
    required this.pumpName,
    required this.nutrient,
    required this.unit,
    required this.minimum,
  });

  final String sensorKey;
  final int relay;
  final int pumpIndex;
  final String pumpName;
  final String nutrient;
  final String unit;
  final double minimum;
}

class _FertilizerPumpConfig {
  const _FertilizerPumpConfig({
    required this.relay,
    required this.pumpIndex,
    required this.pumpName,
    required this.nutrient,
    required this.trendKey,
    required this.thresholdMinKey,
    required this.thresholdMaxKey,
    required this.acidifyingRisk,
    required this.concentrationMgPerLiter,
    required this.fertilizerNote,
  });

  final int relay;
  final int pumpIndex;
  final String pumpName;
  final String nutrient;
  final String trendKey;
  final String thresholdMinKey;
  final String thresholdMaxKey;
  final double acidifyingRisk;
  final double concentrationMgPerLiter;
  final String fertilizerNote;
}

class _DynamicFertilizerDose {
  const _DynamicFertilizerDose({
    required this.relay,
    required this.pumpIndex,
    required this.pumpName,
    required this.nutrient,
    required this.trendKey,
    required this.concentrationMgPerLiter,
    required this.recommendedSeconds,
    required this.suitabilityScore,
    required this.ecSeverity,
    required this.nutrientTrendSeverity,
    required this.concentrationFactor,
    required this.phFactor,
    required this.mediumFactor,
    required this.climateFactor,
    required this.concentrationNote,
    required this.basis,
  });

  final int relay;
  final int pumpIndex;
  final String pumpName;
  final String nutrient;
  final String trendKey;
  final double concentrationMgPerLiter;
  final int recommendedSeconds;
  final double suitabilityScore;
  final double ecSeverity;
  final double nutrientTrendSeverity;
  final double concentrationFactor;
  final double phFactor;
  final double mediumFactor;
  final double climateFactor;
  final String concentrationNote;
  final String basis;
}

class _CachedAiRecommendation {
  const _CachedAiRecommendation({
    required this.fingerprint,
    required this.response,
    required this.createdAt,
  });

  final String fingerprint;
  final AiRecommendationResponse response;
  final DateTime createdAt;
}

const _systemPrompt =
    'You are an expert agronomist calculator and an Explainable AI (XAI) narrator. Calculate candidate nutrient-stock and watering doses from sensor history, crop-specific thresholds, selected plant type, selected planting medium, fertilizer concentration, pH risk, EC condition, and estimated N/P/K trends. Treat CWT RS485 NPK values as estimated trend/proxy readings, not independent laboratory-grade N, P, and K measurements. Use EC as the primary nutrient-control gate; Pompa A/B/C may receive different durations after evaluating estimated N/P/K trend priority, fertilizer concentration, pH safety such as urea/N acidifying risk, medium behavior, temperature, moisture, and pump flow rates. Your explanations and recommendations must be specific to the chosen plant and medium, including how plant tolerance, target thresholds, medium depth, bulk density, drainage/porosity note, and estimated soil mass affect watering and fertilizer decisions. Use the fixed 100 cm2 local sensor coverage area and pump flow rates for gradual dose calculations. The app will validate pump recommendations with local safety rules before any user confirmation. Explain that media depth is estimated from the selected medium because actual media depth is not measured. Output your entire response STRICTLY as a single, minified JSON object matching the requested schema.';

final _recommendationItemSchema = Schema.object(
  properties: {
    'id': Schema.string(),
    'title': Schema.string(),
    'status': Schema.enumString(enumValues: ['kritis', 'awas', 'baik']),
    'message': Schema.string(),
    'explanation': Schema.string(),
    'recommendation': Schema.string(),
  },
  requiredProperties: [
    'id',
    'title',
    'status',
    'message',
    'explanation',
    'recommendation',
  ],
);

final _pumpRecommendationSchema = Schema.object(
  properties: {
    'relay': Schema.integer(),
    'pump_index': Schema.integer(),
    'pump_name': Schema.string(),
    'nutrient': Schema.string(),
    'unit': Schema.string(),
    'current_value': Schema.number(),
    'target_minimum': Schema.number(),
    'deficit': Schema.number(),
    'deficit_percent': Schema.number(),
    'recommended_volume_ml': Schema.number(),
    'recommended_seconds': Schema.integer(),
    'reason': Schema.string(),
    'calculation_basis': Schema.string(),
  },
  requiredProperties: [
    'relay',
    'pump_index',
    'pump_name',
    'nutrient',
    'unit',
    'current_value',
    'target_minimum',
    'deficit',
    'deficit_percent',
    'recommended_volume_ml',
    'recommended_seconds',
    'reason',
    'calculation_basis',
  ],
);

final _responseSchema = Schema.object(
  properties: {
    'plant_health_percentage': Schema.integer(),
    'sensor_summary': Schema.string(),
    'recommendations': Schema.object(
      properties: {
        'all': Schema.array(items: _recommendationItemSchema),
        'kritis': Schema.array(items: _recommendationItemSchema),
        'awas': Schema.array(items: _recommendationItemSchema),
        'baik': Schema.array(items: _recommendationItemSchema),
      },
      requiredProperties: ['all', 'kritis', 'awas', 'baik'],
    ),
    'automation_triggers': Schema.object(
      properties: {
        'activate_nitrogen_pump': Schema.boolean(),
        'activate_phosphorus_pump': Schema.boolean(),
        'activate_potassium_pump': Schema.boolean(),
        'activate_water_pump': Schema.boolean(),
        'reason': Schema.string(),
      },
      requiredProperties: [
        'activate_nitrogen_pump',
        'activate_phosphorus_pump',
        'activate_potassium_pump',
        'activate_water_pump',
        'reason',
      ],
    ),
    'pump_recommendations': Schema.array(items: _pumpRecommendationSchema),
    'daily_schedule_recommendation': Schema.object(
      properties: {
        'hour': Schema.integer(),
        'minute': Schema.integer(),
        'pump_indexes': Schema.array(items: Schema.integer()),
        'duration_seconds': Schema.integer(),
        'reason': Schema.string(),
      },
      requiredProperties: [
        'hour',
        'minute',
        'pump_indexes',
        'duration_seconds',
        'reason',
      ],
    ),
  },
  requiredProperties: [
    'plant_health_percentage',
    'sensor_summary',
    'recommendations',
    'automation_triggers',
    'pump_recommendations',
    'daily_schedule_recommendation',
  ],
);

class _GeminiRuntimeConfig {
  const _GeminiRuntimeConfig({
    this.apiKey = '',
    this.modelName = '',
  });

  final String apiKey;
  final String modelName;
}

class _GeminiContentResult {
  const _GeminiContentResult({
    required this.modelName,
    required this.response,
  });

  final String modelName;
  final dynamic response;
}

class _SensorReadingSnapshot {
  const _SensorReadingSnapshot({
    required this.timestamp,
    this.nitrogen,
    this.phosphorus,
    this.potassium,
    this.ph,
    this.temperature,
    this.moisture,
    this.ec,
  });

  final DateTime timestamp;
  final double? nitrogen;
  final double? phosphorus;
  final double? potassium;
  final double? ph;
  final double? temperature;
  final double? moisture;
  final double? ec;

  factory _SensorReadingSnapshot.fromFirestore(Map<String, dynamic> data) {
    return _SensorReadingSnapshot(
      timestamp: _readTimestamp(data),
      nitrogen: _readDouble(data, ['N', 'n', 'nitrogen']),
      phosphorus: _readDouble(data, ['P', 'p', 'phosphorus']),
      potassium: _readDouble(data, ['K', 'k', 'potassium']),
      ph: _readDouble(data, ['pH', 'ph', 'PH']),
      temperature: _readDouble(data, ['Temp', 'temp', 'temperature']),
      moisture: _readDouble(data, ['Moisture', 'moisture']),
      ec: _readDouble(data, ['EC', 'ec', 'electrical_conductivity']),
    );
  }

  bool get hasAnySensorValue =>
      nitrogen != null ||
      phosphorus != null ||
      potassium != null ||
      ph != null ||
      temperature != null ||
      moisture != null ||
      ec != null;

  static DateTime _readTimestamp(Map<String, dynamic> data) {
    final raw = data['timestamp'] ?? data['createdAt'] ?? data['time'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    return DateTime.now();
  }

  static double? _readDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}

@visibleForTesting
class SensorHistorySummary {
  const SensorHistorySummary({
    required this.rowCount,
    required this.startTime,
    required this.endTime,
    required this.parameters,
  });

  final int rowCount;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, _ParameterStats> parameters;

  factory SensorHistorySummary.fromHistory(List<SensorDataPoint> history) {
    final snapshots = history
        .map(
          (item) => _SensorReadingSnapshot(
            timestamp: item.time,
            nitrogen: item.nitrogen,
            phosphorus: item.phosphorus,
            potassium: item.potassium,
            ph: item.ph,
            temperature: item.temperature,
            moisture: item.moisture,
            ec: item.ec,
          ),
        )
        .toList();
    return SensorHistorySummary.fromReadings(snapshots);
  }

  factory SensorHistorySummary.fromReadings(
    List<_SensorReadingSnapshot> readings,
  ) {
    return SensorHistorySummary(
      rowCount: readings.length,
      startTime: readings.first.timestamp,
      endTime: readings.last.timestamp,
      parameters: {
        'N': _ParameterStats.fromValues(
          readings.map((item) => item.nitrogen).nonNulls.toList(),
        ),
        'P': _ParameterStats.fromValues(
          readings.map((item) => item.phosphorus).nonNulls.toList(),
        ),
        'K': _ParameterStats.fromValues(
          readings.map((item) => item.potassium).nonNulls.toList(),
        ),
        'pH': _ParameterStats.fromValues(
          readings.map((item) => item.ph).nonNulls.toList(),
        ),
        'Temp': _ParameterStats.fromValues(
          readings.map((item) => item.temperature).nonNulls.toList(),
        ),
        'Moisture': _ParameterStats.fromValues(
          readings.map((item) => item.moisture).nonNulls.toList(),
        ),
        'EC': _ParameterStats.fromValues(
          readings.map((item) => item.ec).nonNulls.toList(),
        ),
      },
    );
  }

  bool canActivateWaterPump(Map<String, num> activeThresholds) {
    final moisture = parameters['Moisture']?.current;
    return moisture != null && moisture < activeThresholds['moisture_min']!;
  }

  bool canActivateFertilizerRecipe(Map<String, num> activeThresholds) {
    final ec = parameters['EC']?.current;
    return ec != null && ec < activeThresholds['ec_min']!;
  }

  bool canActivateNitrogenPump(Map<String, num> activeThresholds) {
    return canActivateFertilizerRecipe(activeThresholds);
  }

  bool canActivatePhosphorusPump(Map<String, num> activeThresholds) {
    return canActivateFertilizerRecipe(activeThresholds);
  }

  bool canActivatePotassiumPump(Map<String, num> activeThresholds) {
    return canActivateFertilizerRecipe(activeThresholds);
  }

  Map<String, dynamic> toJson(Map<String, num> activeThresholds) {
    return {
      'row_count': rowCount,
      'time_range': {
        'start': startTime.toIso8601String(),
        'end': endTime.toIso8601String(),
        'display_range': _formatAiDateTimeRange(startTime, endTime),
        'display_format': 'dd-MM-yyyy HH:mm',
      },
      'sensor_interpretation': {
        'N': 'estimated_trend_only',
        'P': 'estimated_trend_only',
        'K': 'estimated_trend_only',
        'primary_nutrient_control_signal': 'EC',
      },
      'parameters': parameters.map((key, value) => MapEntry(
            key,
            value.toJson(),
          )),
      'local_threshold_flags': {
        'water_pump_allowed': canActivateWaterPump(activeThresholds),
        'fertilizer_recipe_allowed':
            canActivateFertilizerRecipe(activeThresholds),
        'nitrogen_pump_allowed': canActivateFertilizerRecipe(activeThresholds),
        'phosphorus_pump_allowed':
            canActivateFertilizerRecipe(activeThresholds),
        'potassium_pump_allowed': canActivateFertilizerRecipe(activeThresholds),
      },
    };
  }
}

class _ParameterStats {
  const _ParameterStats({
    required this.current,
    required this.average,
    required this.minimum,
    required this.maximum,
    required this.trend,
    required this.samples,
  });

  final double? current;
  final double? average;
  final double? minimum;
  final double? maximum;
  final String trend;
  final int samples;

  factory _ParameterStats.fromValues(List<double> values) {
    if (values.isEmpty) {
      return const _ParameterStats(
        current: null,
        average: null,
        minimum: null,
        maximum: null,
        trend: 'unavailable',
        samples: 0,
      );
    }

    final sum = values.reduce((a, b) => a + b);
    final firstWindow = values.take((values.length / 3).ceil()).toList();
    final lastWindow =
        values.reversed.take((values.length / 3).ceil()).toList();
    final firstAvg = firstWindow.reduce((a, b) => a + b) / firstWindow.length;
    final lastAvg = lastWindow.reduce((a, b) => a + b) / lastWindow.length;
    final delta = lastAvg - firstAvg;

    return _ParameterStats(
      current: _round(values.last),
      average: _round(sum / values.length),
      minimum: _round(values.reduce((a, b) => a < b ? a : b)),
      maximum: _round(values.reduce((a, b) => a > b ? a : b)),
      trend: delta.abs() < 0.5
          ? 'stable'
          : delta > 0
              ? 'increasing'
              : 'decreasing',
      samples: values.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'current': current,
      'average': average,
      'minimum': minimum,
      'maximum': maximum,
      'trend': trend,
      'samples': samples,
    };
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));
}
