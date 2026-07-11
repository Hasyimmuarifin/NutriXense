import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/ai_recommendation.dart';
import '../models/pump_flow_rate.dart';

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
          'Convert mg/L by dividing by 1000 before calculating pump volume in milliliters.',
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
    required this.rowLimit,
    required this.description,
  });

  final String id;
  final String label;
  final int rowLimit;
  final String description;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'row_limit': rowLimit,
      'description': description,
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
  rowLimit: 720,
  description: 'Analisis stabilitas setengah hari terakhir.',
);

const List<AiAnalysisWindowProfile> analysisWindowProfiles = [
  AiAnalysisWindowProfile(
    id: '1h',
    label: '1 jam',
    rowLimit: 60,
    description: 'Analisis cepat untuk kondisi sensor terbaru.',
  ),
  AiAnalysisWindowProfile(
    id: '6h',
    label: '6 jam',
    rowLimit: 360,
    description: 'Analisis perubahan kondisi dalam beberapa jam terakhir.',
  ),
  defaultAnalysisWindowProfile,
  AiAnalysisWindowProfile(
    id: '24h',
    label: '24 jam',
    rowLimit: 1440,
    description: 'Analisis pola harian penuh.',
  ),
  AiAnalysisWindowProfile(
    id: '7d',
    label: '7 hari',
    rowLimit: 10080,
    description: 'Analisis tren mingguan untuk melihat kestabilan nutrisi.',
  ),
  AiAnalysisWindowProfile(
    id: '30d',
    label: '30 hari',
    rowLimit: 43200,
    description: 'Analisis tren jangka panjang satu bulan.',
  ),
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
    label: 'Tanah liat/padat',
    assumedDepthCm: 15,
    bulkDensityKgPerM3: 1200,
    note: 'Media lebih padat; koreksi dibuat lebih bertahap.',
  ),
  PlantingMediumProfile(
    id: 'sandy_fast_drying_soil',
    label: 'Tanah berpasir/cepat kering',
    assumedDepthCm: 18,
    bulkDensityKgPerM3: 1100,
    note: 'Media berdrainase cepat; penyiraman dan nutrisi dibuat bertahap.',
  ),
  PlantingMediumProfile(
    id: 'raised_bed',
    label: 'Bedengan/lahan teh',
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
  static const _responseCacheTtl = Duration(minutes: 2);
  static const _gradualCorrectionFraction = 0.25;
  static const _maxPumpRunSeconds = 300;
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

    final readings = await _fetchRecentReadings(
      limit: input.analysisWindow.rowLimit,
    );
    if (readings.isEmpty) {
      throw StateError('Belum ada data sensor di koleksi $_collection.');
    }

    final summary = _SensorHistorySummary.fromReadings(readings);
    final activeThresholds = _thresholdsFor(input);
    final requestFingerprint = _buildRequestFingerprint(
      summary,
      input,
      activeThresholds,
    );
    final cachedResponse = _readCachedRecommendation(requestFingerprint);
    if (cachedResponse != null) return cachedResponse;

    final deterministicPlan = _buildDeterministicDecisionPlan(
      summary,
      input,
      activeThresholds,
    );
    final model = GenerativeModel(
      model: config.modelName,
      apiKey: config.apiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.35,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json',
        responseSchema: _responseSchema,
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
          'Do not directly activate pumps. Return decision support only; the user must confirm and may adjust pump duration.',
      'pump_mapping': {
        'activate_nitrogen_pump': 'Pompa A - Nitrogen (N)',
        'activate_phosphorus_pump': 'Pompa B - Fosfor (P)',
        'activate_potassium_pump': 'Pompa C - Kalium (K)',
        'activate_water_pump': 'Pompa D - Air (H2O)',
      },
      'cultivation_area': {
        'square_meters': input.landAreaSquareMeters,
        'unit': 'm2',
        'calculation_note':
            'This area is fixed to 100 cm2 (0.01 m2) because the RS485 NPK sensor only represents a small local measurement zone and the pump/tube hardware is small.',
      },
      'agronomic_input': input.toJson(),
      'analysis_window': input.analysisWindow.toJson(),
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
        'Only recommend a pump when the matching current parameter is below its minimum threshold.',
        'For N, P, and K, estimate soil mass as area_m2 * assumed_depth_m * bulk_density_kg_per_m3.',
        'For N, P, and K, estimate element deficit as threshold_gap_mg_per_kg * soil_mass_kg, then apply gradual_correction_fraction before converting to ml using fertilizer concentration in mg/L.',
        'When calculating pump volume in ml from fertilizer concentration in mg/L, divide the concentration by 1000 first.',
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
        'sensor_summary maximum 2 sentences and must mention ${input.plantType.label}, ${input.plantingMedium.label}, and the selected analysis window (${input.analysisWindow.label}), not the number of analyzed rows.',
        'For each item, message maximum 1 sentence, explanation maximum 2 sentences, recommendation maximum 2 sentences.',
        'For each recommendation item, explanation must explain current value, threshold, average, trend, selected plant relevance, selected medium relevance, and the dose basis when correction is needed.',
        'For each recommendation item, recommendation must explain practical follow-up actions for ${input.plantType.label} on ${input.plantingMedium.label} and require user confirmation before pump activation.',
        'Pump recommendation reasons must mention the relevant pump flow rate and why the chosen duration fits ${input.plantingMedium.label} and ${input.plantType.label}.',
        'Daily schedule reason must explain why the chosen time, pump indexes, and duration fit ${input.plantType.label}, ${input.plantingMedium.label}, and recent sensor trends.',
        'Do not mention or assume any specific cultivation container unless the input data explicitly states it.',
        'Return pump_recommendations and daily_schedule_recommendation when pump correction is needed.',
      ],
      'thresholds': activeThresholds,
      'history_summary': summary.toJson(activeThresholds),
      'local_safety_bounds': _safetyBoundsToJson(input),
      'deterministic_decision_plan': deterministicPlan,
    });

    dynamic response;
    try {
      response = await _generateContentWithRetry(
        model,
        [Content.text(payload)],
      );
    } on Object catch (error) {
      if (_shouldUseLocalFallback(error)) {
        debugPrint(
          'Gemini unavailable, using local DSS/XAI fallback: $error',
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

    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw StateError('Gemini tidak mengembalikan teks JSON.');
    }

    final decoded = await _decodeJsonResponse(
      model: model,
      rawText: text,
      originalPayload: payload,
      summary: summary,
      input: input,
      activeThresholds: activeThresholds,
      deterministicPlan: deterministicPlan,
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
    _SensorHistorySummary summary,
    AiRecommendationAgronomicInput input, {
    required Map<String, num> activeThresholds,
    required bool useGeminiPumpRecommendations,
  }) {
    final guardedResponse =
        AiRecommendationResponse.fromJson(decoded).withAutomationGuard(
      canActivateWaterPump: summary.canActivateWaterPump(activeThresholds),
      canActivateNitrogenPump:
          summary.canActivateNitrogenPump(activeThresholds),
      canActivatePhosphorusPump:
          summary.canActivatePhosphorusPump(activeThresholds),
      canActivatePotassiumPump:
          summary.canActivatePotassiumPump(activeThresholds),
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

    return guardedResponse.copyWith(
      pumpRecommendations: pumpRecommendations,
      dailyScheduleRecommendation: scheduleRecommendation,
    );
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
      ], fallback: 'gemini-3.5-flash'),
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

  Future<List<_SensorReadingSnapshot>> _fetchRecentReadings({
    required int limit,
  }) async {
    final query = _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(limit);

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => _SensorReadingSnapshot.fromFirestore(doc.data()))
        .where((item) => item.hasAnySensorValue)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  static String _buildRequestFingerprint(
    _SensorHistorySummary summary,
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
    required GenerativeModel model,
    required String rawText,
    required String originalPayload,
    required _SensorHistorySummary summary,
    required AiRecommendationAgronomicInput input,
    required Map<String, num> activeThresholds,
    required Map<String, dynamic> deterministicPlan,
  }) async {
    final cleaned = _stripCodeFence(rawText);
    final decoded = _tryDecodeJsonObject(cleaned);
    if (decoded != null) return decoded;

    dynamic repairResponse;
    try {
      repairResponse = await _generateContentWithRetry(
        model,
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
    } on Object catch (error) {
      if (_shouldUseLocalFallback(error)) {
        debugPrint(
          'Gemini repair unavailable, using local DSS/XAI fallback: $error',
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

    debugPrint(
      'Gemini returned malformed JSON after repair. Using local fallback. '
      'Preview: ${_shortPreview(cleaned)}',
    );
    return deterministicPlan;
  }

  static Map<String, dynamic> _buildDeterministicDecisionPlan(
    _SensorHistorySummary summary,
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
                'Jadwal harian ${input.plantType.label} direkomendasikan dari selisih parameter terbaru terhadap ambang minimum berdasarkan rentang analisis ${input.analysisWindow.label}, area sensor 100 cm2, dan asumsi media ${input.plantingMedium.label}.',
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
    _SensorHistorySummary summary,
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
    _SensorHistorySummary summary,
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
      final doseAwareSeconds = localReferenceSeconds > candidateSeconds
          ? localReferenceSeconds
          : candidateSeconds;
      final safeSeconds = doseAwareSeconds.clamp(1, maxSeconds).toInt();
      final wasRaisedToDoseReference =
          localReferenceSeconds > 0 && candidateSeconds < localReferenceSeconds;
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
      final doseReferenceNote = wasRaisedToDoseReference
          ? ' Durasi dinaikkan dari rekomendasi mentah ${candidateSeconds.toInt()} detik ke $safeSeconds detik agar tidak lebih rendah dari kalkulasi dosis lokal berbasis defisit, massa media, konsentrasi larutan, dan debit pompa.'
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
              '$reason ${basis == null ? '' : 'Dasar hitung: $basis '}$doseReferenceNote Durasi telah divalidasi dengan batas aman lokal maksimal $maxSeconds detik dan debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk estimasi ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.',
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
    return error is AiRecommendationException ||
        _isQuotaOrRateLimitError(error);
  }

  static bool _isQuotaOrRateLimitError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('429') ||
        text.contains('quota') ||
        text.contains('rate limit') ||
        text.contains('rate-limit') ||
        text.contains('resource exhausted') ||
        text.contains('free_tier') ||
        text.contains('free tier') ||
        text.contains('retrydelay') ||
        text.contains('retry in');
  }

  static Future<dynamic> _generateContentWithRetry(
    GenerativeModel model,
    List<Content> contents,
  ) async {
    final startedAt = DateTime.now();
    var attempt = 0;
    Object? lastError;

    while (DateTime.now().difference(startedAt) < _requestTimeout) {
      attempt += 1;
      final remaining = _requestTimeout - DateTime.now().difference(startedAt);
      if (remaining <= Duration.zero) break;

      try {
        return await model.generateContent(contents).timeout(remaining);
      } on Object catch (error) {
        lastError = error;
        if (!_shouldRetryAiRequest(error)) rethrow;

        final delay = _retryDelay(attempt);
        final remainingAfterDelay =
            _requestTimeout - DateTime.now().difference(startedAt);
        if (remainingAfterDelay <= delay) break;
        await Future<void>.delayed(delay);
      }
    }

    debugPrint('Gemini request failed after retry: $lastError');
    throw const AiRecommendationException(_busyMessage);
  }

  static bool _shouldRetryAiRequest(Object error) {
    if (error is TimeoutException) return true;

    final text = error.toString().toLowerCase();
    return text.contains('503') ||
        text.contains('server error') ||
        text.contains('unavailable') ||
        text.contains('overloaded') ||
        text.contains('traffic') ||
        text.contains('timeout');
  }

  static Duration _retryDelay(int attempt) {
    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 12),
      Duration(seconds: 15),
    ];
    if (attempt <= delays.length) return delays[attempt - 1];
    return delays.last;
  }

  static Map<String, dynamic> _buildLocalFallbackResponse(
    _SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final items = <Map<String, dynamic>>[];

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
      label: 'Nitrogen',
      unit: 'mg/kg',
      min: activeThresholds['nitrogen_min']!,
      max: activeThresholds['nitrogen_max']!,
      lowTitle: 'Nitrogen Rendah',
      highTitle: 'Nitrogen Berlebih',
      lowAction:
          'Aktifkan Pompa A dalam dosis kecil sesuai DSS untuk ${input.plantType.label}, lalu pantau ulang NPK setelah larutan merata. Hindari penambahan besar sekaligus karena perubahan EC mendadak dapat menekan akar.',
      highAction:
          'Tunda penambahan nitrogen dan lakukan pengenceran bertahap bila EC ikut tinggi. Pantau respons daun ${input.plantType.label} dan ulangi pembacaan N serta EC sebelum koreksi berikutnya.',
      normalAction:
          'Pertahankan dosis nitrogen saat ini dan lanjutkan pemantauan berkala untuk menjaga pertumbuhan ${input.plantType.label} tetap stabil.',
    );
    evaluateRange(
      key: 'P',
      label: 'Fosfor',
      unit: 'mg/kg',
      min: activeThresholds['phosphorus_min']!,
      max: activeThresholds['phosphorus_max']!,
      lowTitle: 'Fosfor Rendah',
      highTitle: 'Fosfor Berlebih',
      lowAction:
          'Aktifkan Pump B secara bertahap dan pastikan larutan tercampur sebelum evaluasi ulang. Jaga pH media sesuai rentang ${input.plantType.label} karena pH yang tidak sesuai dapat menghambat ketersediaan fosfor.',
      highAction:
          'Hentikan sementara suplai fosfor dan pantau EC serta pH media tanam. Lakukan pengenceran ringan jika konsentrasi nutrisi keseluruhan meningkat.',
      normalAction:
          'Pertahankan suplai fosfor dan pantau tren harian untuk mencegah penurunan.',
    );
    evaluateRange(
      key: 'K',
      label: 'Kalium',
      unit: 'mg/kg',
      min: activeThresholds['potassium_min']!,
      max: activeThresholds['potassium_max']!,
      lowTitle: 'Kalium Rendah',
      highTitle: 'Kalium Berlebih',
      lowAction:
          'Aktifkan Pump C sesuai durasi DSS, lalu ulangi pembacaan setelah nutrisi tersebar merata. Kalium penting untuk ketahanan dan fase produktif ${input.plantType.label}, tetapi tetap jaga keseimbangan NPK agar EC tidak melonjak.',
      highAction:
          'Tunda penambahan kalium dan pantau EC. Jika nilai tetap tinggi, kurangi konsentrasi larutan secara bertahap.',
      normalAction:
          'Kadar kalium sudah memadai untuk ${input.plantType.label}, lanjutkan pemantauan bersama N dan P.',
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
      lowAction:
          'Tambahkan nutrisi secara bertahap melalui pompa NPK yang sesuai dengan unsur rendah. Ukur ulang EC setelah pencampuran agar ${input.plantType.label} tetap menerima koreksi kecil dan stabil.',
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
          'Analisis ${input.plantType.label} dibuat dari rentang ${input.analysisWindow.label} terakhir, area sensor tetap 100 cm2, konsentrasi NPK, dan asumsi media ${input.plantingMedium.label}. Kedalaman media belum diukur langsung, sehingga dosis dihitung sebagai koreksi bertahap berbasis estimasi.',
      'recommendations': {
        'all': items,
        'kritis': kritis,
        'awas': awas,
        'baik': baik,
      },
      'automation_triggers': {
        'activate_nitrogen_pump':
            summary.canActivateNitrogenPump(activeThresholds),
        'activate_phosphorus_pump':
            summary.canActivatePhosphorusPump(activeThresholds),
        'activate_potassium_pump':
            summary.canActivatePotassiumPump(activeThresholds),
        'activate_water_pump': summary.canActivateWaterPump(activeThresholds),
        'reason':
            'Trigger mengikuti flag ambang lokal dari data sensor terbaru.',
      },
    };
  }

  static Map<String, dynamic> _buildAiUnavailableFallbackResponse(
    _SensorHistorySummary summary,
    Object error,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final fallback = _buildLocalFallbackResponse(
      summary,
      input,
      activeThresholds,
    );
    final prefix = _isQuotaOrRateLimitError(error)
        ? 'Kuota atau rate limit Gemini API sedang tercapai, sehingga rekomendasi sementara dibuat memakai analisis DSS/XAI lokal.'
        : 'Rekomendasi dibuat memakai analisis DSS/XAI lokal.';

    return {
      ...fallback,
      'sensor_summary': '$prefix ${fallback['sensor_summary']}',
    };
  }

  static List<PumpFertilizationRecommendation> _buildPumpRecommendations(
    _SensorHistorySummary summary,
    AiRecommendationAgronomicInput input,
    Map<String, num> activeThresholds,
  ) {
    final recommendations = <PumpFertilizationRecommendation>[];

    void addIfLow({
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
      final targetVolumeMl = key == 'Moisture'
          ? _estimatedWaterVolumeMl(
              currentMoisturePercent: current,
              targetMinimumPercent: minimum,
              input: input,
            )
          : _estimatedNutrientVolumeMl(
              sensorKey: key,
              deficitMgPerKg: deficit,
              input: input,
            );
      final recommendedSeconds = PumpFlowRates.secondsForVolume(
        pumpIndex: pumpIndex,
        volumeMl: targetVolumeMl,
      ).clamp(1, _maxSafeSecondsForPump(pumpIndex, input)).toInt();
      final flowRate = PumpFlowRates.byPumpIndex(pumpIndex).averageMlPerSecond;
      final estimatedVolumeMl = PumpFlowRates.volumeForDuration(
        pumpIndex: pumpIndex,
        seconds: recommendedSeconds,
      );

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
          reason: key == 'Moisture'
              ? '$nutrient saat ini ${_formatNumber(current)} $unit, kurang ${_formatNumber(deficit)} $unit dari ambang minimum ${_formatNumber(minimum)} $unit. Estimasi penyiraman memakai area sensor 100 cm2, kedalaman media ${_formatNumber(input.plantingMedium.assumedDepthCm)} cm, dan koreksi bertahap sekitar ${PumpFlowRates.formatMl(targetVolumeMl)} ml; durasi pompa dihitung dari debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk keluaran sekitar ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.'
              : '$nutrient saat ini ${_formatNumber(current)} $unit, kurang ${_formatNumber(deficit)} $unit dari ambang minimum ${_formatNumber(minimum)} $unit. Estimasi nutrisi memakai media ${input.plantingMedium.label}, kedalaman asumsi ${_formatNumber(input.plantingMedium.assumedDepthCm)} cm, massa tanah sekitar ${_formatNumber(_estimatedSoilMassKg(input))} kg, dan konsentrasi larutan ${_formatNumber(_concentrationMgPerLiterForKey(key, input))} mg/L; durasi pompa dihitung dari debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk keluaran sekitar ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.',
        ),
      );
    }

    addIfLow(
      key: 'N',
      relay: 1,
      pumpIndex: 0,
      pumpName: 'Pompa A',
      nutrient: 'Nitrogen',
      unit: 'mg/kg',
      minimum: activeThresholds['nitrogen_min']!.toDouble(),
    );
    addIfLow(
      key: 'P',
      relay: 2,
      pumpIndex: 1,
      pumpName: 'Pompa B',
      nutrient: 'Fosfor',
      unit: 'mg/kg',
      minimum: activeThresholds['phosphorus_min']!.toDouble(),
    );
    addIfLow(
      key: 'K',
      relay: 3,
      pumpIndex: 2,
      pumpName: 'Pompa C',
      nutrient: 'Kalium',
      unit: 'mg/kg',
      minimum: activeThresholds['potassium_min']!.toDouble(),
    );
    addIfLow(
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

  static double _estimatedNutrientVolumeMl({
    required String sensorKey,
    required double deficitMgPerKg,
    required AiRecommendationAgronomicInput input,
  }) {
    final concentrationMgPerMilliliter =
        _concentrationMgPerMilliliterForCalculation(sensorKey, input);
    final deficitMg = deficitMgPerKg *
        _estimatedSoilMassKg(input) *
        _gradualCorrectionFraction;
    final volumeMl = (concentrationMgPerMilliliter <= 0
            ? 1
            : deficitMg / concentrationMgPerMilliliter)
        .toDouble();
    return _roundDouble(volumeMl < 1 ? 1 : volumeMl);
  }

  static String _buildWateringLowAction(
    _SensorHistorySummary summary,
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

  static double _concentrationMgPerLiterForKey(
    String sensorKey,
    AiRecommendationAgronomicInput input,
  ) {
    switch (sensorKey) {
      case 'N':
        return input.fertilizerConcentration.nitrogenMgPerLiter;
      case 'P':
        return input.fertilizerConcentration.phosphorusMgPerLiter;
      case 'K':
        return input.fertilizerConcentration.potassiumMgPerLiter;
      default:
        return 1;
    }
  }

  static double _concentrationMgPerMilliliterForCalculation(
    String sensorKey,
    AiRecommendationAgronomicInput input,
  ) {
    return _concentrationMgPerLiterForKey(sensorKey, input) / 1000;
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
          sensorKey: 'N',
          relay: 1,
          pumpIndex: 0,
          pumpName: 'Pompa A',
          nutrient: 'Nitrogen',
          unit: 'mg/kg',
          minimum: activeThresholds['nitrogen_min']!.toDouble(),
        );
      case 2:
        return _PumpMetadata(
          sensorKey: 'P',
          relay: 2,
          pumpIndex: 1,
          pumpName: 'Pompa B',
          nutrient: 'Fosfor',
          unit: 'mg/kg',
          minimum: activeThresholds['phosphorus_min']!.toDouble(),
        );
      case 3:
        return _PumpMetadata(
          sensorKey: 'K',
          relay: 3,
          pumpIndex: 2,
          pumpName: 'Pompa C',
          nutrient: 'Kalium',
          unit: 'mg/kg',
          minimum: activeThresholds['potassium_min']!.toDouble(),
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
    'You are an expert agronomist calculator and an Explainable AI (XAI) narrator. Calculate candidate nutrient and watering doses from sensor history, crop-specific thresholds, the selected plant type, and the selected planting medium. Your explanations and recommendations must be specific to the chosen plant and medium, including how plant tolerance, target thresholds, medium depth, bulk density, drainage/porosity note, and estimated soil mass affect watering and fertilizer decisions. Use the fixed 100 cm2 local sensor coverage area, pump flow rates, and fertilizer solution concentration for dose calculations. The app will validate pump recommendations with local safety rules before any user confirmation. Explain that media depth is estimated from the selected medium because actual depth is not measured. Output your entire response STRICTLY as a single, minified JSON object matching the requested schema.';

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

class _SensorHistorySummary {
  const _SensorHistorySummary({
    required this.rowCount,
    required this.startTime,
    required this.endTime,
    required this.parameters,
  });

  final int rowCount;
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, _ParameterStats> parameters;

  factory _SensorHistorySummary.fromReadings(
    List<_SensorReadingSnapshot> readings,
  ) {
    return _SensorHistorySummary(
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

  bool canActivateNitrogenPump(Map<String, num> activeThresholds) {
    final n = parameters['N']?.current;
    return n != null && n < activeThresholds['nitrogen_min']!;
  }

  bool canActivatePhosphorusPump(Map<String, num> activeThresholds) {
    final p = parameters['P']?.current;
    return p != null && p < activeThresholds['phosphorus_min']!;
  }

  bool canActivatePotassiumPump(Map<String, num> activeThresholds) {
    final k = parameters['K']?.current;
    return k != null && k < activeThresholds['potassium_min']!;
  }

  Map<String, dynamic> toJson(Map<String, num> activeThresholds) {
    return {
      'row_count': rowCount,
      'time_range': {
        'start': startTime.toIso8601String(),
        'end': endTime.toIso8601String(),
      },
      'parameters': parameters.map((key, value) => MapEntry(
            key,
            value.toJson(),
          )),
      'local_threshold_flags': {
        'water_pump_allowed': canActivateWaterPump(activeThresholds),
        'nitrogen_pump_allowed': canActivateNitrogenPump(activeThresholds),
        'phosphorus_pump_allowed': canActivatePhosphorusPump(activeThresholds),
        'potassium_pump_allowed': canActivatePotassiumPump(activeThresholds),
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
