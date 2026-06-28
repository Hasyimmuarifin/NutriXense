import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/ai_recommendation.dart';
import '../models/pump_flow_rate.dart';

class GeminiRecommendationService {
  GeminiRecommendationService({
    FirebaseFirestore? firestore,
    String? apiKey,
    String? modelName,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _apiKeyOverride = apiKey,
        _modelNameOverride = modelName;

  static const _collection = 'sensor_data';
  static const _historyLimit = 720;
  static const _configAssetPath = 'assets/config/gemini_config.json';
  static const _dartDefineApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _dartDefineModelName = String.fromEnvironment('GEMINI_MODEL');
  static const _busyMessage =
      'AI sedang sibuk karena trafik tinggi. Silakan coba lagi dalam beberapa saat.';
  static const _requestTimeout = Duration(minutes: 1);

  // Threshold target for tea plants.
  static const thresholds = {
    'nitrogen_min': 80,
    'nitrogen_max': 180,
    'phosphorus_min': 100,
    'phosphorus_max': 300,
    'potassium_min': 250,
    'potassium_max': 650,
    'moisture_min': 40,
    'moisture_max': 70,
    'ph_min': 4.5,
    'ph_max': 5.5,
    'temperature_min': 18,
    'temperature_max': 25,
    'ec_min': 1.2,
    'ec_max': 2.5,
  };

  final FirebaseFirestore _firestore;
  final String? _apiKeyOverride;
  final String? _modelNameOverride;

  Future<AiRecommendationResponse> requestRecommendation({
    required double landAreaSquareMeters,
  }) async {
    final config = await _resolveConfig();

    if (config.apiKey.trim().isEmpty) {
      throw StateError(
        'GEMINI_API_KEY belum dikonfigurasi. Isi $_configAssetPath atau '
        'jalankan Flutter dengan --dart-define=GEMINI_API_KEY=YOUR_KEY.',
      );
    }

    final readings = await _fetchRecentReadings();
    if (readings.isEmpty) {
      throw StateError('Belum ada data sensor di koleksi $_collection.');
    }

    final summary = _SensorHistorySummary.fromReadings(readings);
    final model = GenerativeModel(
      model: config.modelName,
      apiKey: config.apiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 3072,
        responseMimeType: 'application/json',
        responseSchema: _responseSchema,
      ),
    );

    final payload = jsonEncode({
      'task':
          'Analyze this condensed IoT sensor history for tea plants and return JSON only.',
      'crop_context':
          'Tanaman teh (Camellia sinensis), media tanam asam, drainase baik, dan koreksi nutrisi bertahap agar akar tidak stres.',
      'language': 'id',
      'control_policy':
          'Do not directly activate pumps. Return decision support only; the user must confirm and may adjust pump duration.',
      'pump_mapping': {
        'activate_nitrogen_pump': 'Pompa A - Nitrogen (N)',
        'activate_phosphorus_pump': 'Pompa B - Fosfor (P)',
        'activate_potassium_pump': 'Pompa C - Kalium (K)',
        'activate_water_pump': 'Pompa D - Air (H2O)',
      },
      'pump_flow_rates_ml_per_second': PumpFlowRates.toPromptJson(),
      'cultivation_area': {
        'square_meters': landAreaSquareMeters,
        'unit': 'm2',
        'irrigation_estimation_note':
            'Use this area for water pump estimation. In irrigation, 1 mm water depth equals 1 liter per m2.',
      },
      'output_rules': [
        'Return one complete JSON object only.',
        'Do not use markdown.',
        'Keep every string concise and close all quotes.',
        'sensor_summary maximum 2 sentences.',
        'Return maximum 7 recommendation items total.',
        'For each item, message maximum 1 sentence, explanation maximum 2 sentences, recommendation maximum 2 sentences.',
        'For each recommendation item, explanation must explain why the condition happened from the sensor data.',
        'For each recommendation item, recommendation must explain specific follow-up actions for tea plants in general cultivation context.',
        'Do not mention or assume any specific cultivation container unless the input data explicitly states it.',
        'Recommendations must be practical, safe, and measurable for tea plants, such as small-dose pump use, careful irrigation, acidic pH correction, fertilizer adjustment, retesting, drainage, shade, or monitoring frequency.',
        'When mentioning pump duration or dosage, consider pump_flow_rates_ml_per_second so slower pumps run longer for comparable target volume.',
        'When recommending N, P, or K nutrient pump dosage, consider cultivation_area.square_meters so smaller areas receive lower volume and larger areas receive higher volume.',
        'When recommending watering, consider cultivation_area.square_meters and explain the estimated water volume in practical terms.',
        'Set an automation trigger to true only when its matching local_threshold_flag is true.',
        'Mention that pump activation requires user confirmation when nutrient or water correction is recommended.',
      ],
      'thresholds': thresholds,
      'history_summary': summary.toJson(),
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
        return _responseWithDecisionPlan(
          _buildAiUnavailableFallbackResponse(
            summary,
            error,
            landAreaSquareMeters,
          ),
          summary,
          landAreaSquareMeters,
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
      landAreaSquareMeters: landAreaSquareMeters,
    );
    return _responseWithDecisionPlan(
      decoded,
      summary,
      landAreaSquareMeters,
    );
  }

  static AiRecommendationResponse _responseWithDecisionPlan(
    Map<String, dynamic> decoded,
    _SensorHistorySummary summary,
    double landAreaSquareMeters,
  ) {
    final guardedResponse =
        AiRecommendationResponse.fromJson(decoded).withAutomationGuard(
      canActivateWaterPump: summary.canActivateWaterPump,
      canActivateNitrogenPump: summary.canActivateNitrogenPump,
      canActivatePhosphorusPump: summary.canActivatePhosphorusPump,
      canActivatePotassiumPump: summary.canActivatePotassiumPump,
    );
    final pumpRecommendations = _buildPumpRecommendations(
      summary,
      landAreaSquareMeters,
    );

    return guardedResponse.copyWith(
      pumpRecommendations: pumpRecommendations,
      dailyScheduleRecommendation: pumpRecommendations.isEmpty
          ? null
          : DailyFertilizationScheduleRecommendation.fromPlan(
              recommendations: pumpRecommendations,
              reason:
                  'Jadwal harian direkomendasikan dari selisih parameter terbaru terhadap ambang minimum setelah analisis maksimal $_historyLimit data sensor dan luas tanah ${_formatNumber(landAreaSquareMeters)} m2.',
            ),
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
      ], fallback: 'gemini-2.5-flash'),
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

  Future<List<_SensorReadingSnapshot>> _fetchRecentReadings() async {
    final query = _firestore
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(_historyLimit);

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => _SensorReadingSnapshot.fromFirestore(doc.data()))
        .where((item) => item.hasAnySensorValue)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
    required double landAreaSquareMeters,
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
          landAreaSquareMeters,
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
    return _buildLocalFallbackResponse(summary, landAreaSquareMeters);
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
    double landAreaSquareMeters,
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
      min: thresholds['nitrogen_min']!,
      max: thresholds['nitrogen_max']!,
      lowTitle: 'Nitrogen Rendah',
      highTitle: 'Nitrogen Berlebih',
      lowAction:
          'Aktifkan Pompa A dalam dosis kecil sesuai DSS untuk tanaman teh, lalu pantau ulang NPK setelah larutan merata. Hindari penambahan besar sekaligus karena teh sensitif terhadap lonjakan EC.',
      highAction:
          'Tunda penambahan nitrogen dan lakukan pengenceran bertahap bila EC ikut tinggi. Pantau pucuk daun teh dan ulangi pembacaan N serta EC sebelum koreksi berikutnya.',
      normalAction:
          'Pertahankan dosis nitrogen saat ini dan lanjutkan pemantauan berkala untuk menjaga pertumbuhan pucuk teh tetap stabil.',
    );
    evaluateRange(
      key: 'P',
      label: 'Fosfor',
      unit: 'mg/kg',
      min: thresholds['phosphorus_min']!,
      max: thresholds['phosphorus_max']!,
      lowTitle: 'Fosfor Rendah',
      highTitle: 'Fosfor Berlebih',
      lowAction:
          'Aktifkan Pump B secara bertahap dan pastikan larutan tercampur sebelum evaluasi ulang. Jaga pH media teh tetap asam karena pH yang tidak sesuai dapat menghambat ketersediaan fosfor.',
      highAction:
          'Hentikan sementara suplai fosfor dan pantau EC serta pH media tanam. Lakukan pengenceran ringan jika konsentrasi nutrisi keseluruhan meningkat.',
      normalAction:
          'Pertahankan suplai fosfor dan pantau tren harian untuk mencegah penurunan.',
    );
    evaluateRange(
      key: 'K',
      label: 'Kalium',
      unit: 'mg/kg',
      min: thresholds['potassium_min']!,
      max: thresholds['potassium_max']!,
      lowTitle: 'Kalium Rendah',
      highTitle: 'Kalium Berlebih',
      lowAction:
          'Aktifkan Pump C sesuai durasi DSS, lalu ulangi pembacaan setelah nutrisi tersebar merata. Kalium penting untuk ketahanan teh, tetapi tetap jaga keseimbangan NPK agar EC tidak melonjak.',
      highAction:
          'Tunda penambahan kalium dan pantau EC. Jika nilai tetap tinggi, kurangi konsentrasi larutan secara bertahap.',
      normalAction:
          'Kadar kalium sudah memadai untuk tanaman teh, lanjutkan pemantauan bersama N dan P.',
    );
    evaluateRange(
      key: 'pH',
      label: 'pH',
      unit: 'pH',
      min: thresholds['ph_min']!,
      max: thresholds['ph_max']!,
      lowTitle: 'pH Terlalu Asam',
      highTitle: 'pH Terlalu Basa',
      lowAction:
          'Naikkan pH secara sangat bertahap menggunakan korektor pH up dosis kecil. Teh menyukai media asam, jadi hindari koreksi berlebihan melewati rentang 4.5-5.5.',
      highAction:
          'Turunkan pH secara bertahap menggunakan korektor pH down agar media kembali asam. Hindari koreksi besar sekaligus karena akar teh rentan stres terhadap perubahan pH mendadak.',
      normalAction:
          'pH berada pada zona asam yang sesuai untuk serapan hara tanaman teh, pertahankan prosedur pemantauan.',
    );
    evaluateRange(
      key: 'Moisture',
      label: 'Kelembapan',
      unit: '%',
      min: thresholds['moisture_min']!,
      max: thresholds['moisture_max']!,
      lowTitle: 'Kelembapan Media Rendah',
      highTitle: 'Kelembapan Media Tinggi',
      lowAction: _buildWateringLowAction(summary, landAreaSquareMeters),
      highAction:
          'Tunda penyiraman dan periksa drainase media tanam. Jika kelembapan tetap tinggi, kurangi frekuensi irigasi untuk mencegah akar teh kekurangan oksigen.',
      normalAction:
          'Kelembapan media cukup, pertahankan jadwal penyiraman saat ini.',
    );
    evaluateRange(
      key: 'Temp',
      label: 'Suhu',
      unit: '°C',
      min: thresholds['temperature_min']!,
      max: thresholds['temperature_max']!,
      lowTitle: 'Suhu Terlalu Rendah',
      highTitle: 'Suhu Terlalu Tinggi',
      lowAction:
          'Kurangi paparan dingin dan jaga lingkungan tumbuh teh tetap stabil. Pantau suhu bersama kelembapan karena perubahan suhu memengaruhi penguapan media.',
      highAction:
          'Berikan naungan dan tingkatkan ventilasi untuk menurunkan stres panas pada teh. Gunakan Pump D Water seperlunya dengan durasi pendek agar media tidak terlalu basah.',
      normalAction:
          'Suhu berada dalam rentang aman, lanjutkan pemantauan normal.',
    );
    evaluateRange(
      key: 'EC',
      label: 'Electrical Conductivity',
      unit: 'mS/cm',
      min: thresholds['ec_min']!,
      max: thresholds['ec_max']!,
      lowTitle: 'EC Rendah',
      highTitle: 'EC Tinggi',
      lowAction:
          'Tambahkan nutrisi secara bertahap melalui pompa NPK yang sesuai dengan unsur rendah. Ukur ulang EC setelah pencampuran karena tanaman teh lebih aman dengan koreksi kecil dan stabil.',
      highAction:
          'Encerkan larutan dengan air bersih secara bertahap dan tunda penambahan pupuk. Pantau ulang EC serta pH asam setelah larutan stabil.',
      normalAction:
          'EC stabil untuk tanaman teh, pertahankan konsentrasi larutan dan pantau perubahan setelah irigasi.',
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
          'Ringkasan menggunakan ${summary.rowCount} data sensor terbaru dan luas tanah ${_formatNumber(landAreaSquareMeters)} m2 untuk menilai NPK, pH, suhu, kelembapan, dan EC berdasarkan standar tanaman teh.',
      'recommendations': {
        'all': items,
        'kritis': kritis,
        'awas': awas,
        'baik': baik,
      },
      'automation_triggers': {
        'activate_nitrogen_pump': summary.canActivateNitrogenPump,
        'activate_phosphorus_pump': summary.canActivatePhosphorusPump,
        'activate_potassium_pump': summary.canActivatePotassiumPump,
        'activate_water_pump': summary.canActivateWaterPump,
        'reason':
            'Trigger mengikuti flag ambang lokal dari data sensor terbaru.',
      },
    };
  }

  static Map<String, dynamic> _buildAiUnavailableFallbackResponse(
    _SensorHistorySummary summary,
    Object error,
    double landAreaSquareMeters,
  ) {
    final fallback = _buildLocalFallbackResponse(
      summary,
      landAreaSquareMeters,
    );
    final prefix = _isQuotaOrRateLimitError(error)
        ? 'Kuota atau rate limit Gemini API sedang tercapai, sehingga rekomendasi sementara dibuat memakai analisis DSS/XAI lokal.'
        : 'Gemini sedang tidak tersedia sementara, sehingga rekomendasi dibuat memakai analisis DSS/XAI lokal.';

    return {
      ...fallback,
      'sensor_summary': '$prefix ${fallback['sensor_summary']}',
    };
  }

  static List<PumpFertilizationRecommendation> _buildPumpRecommendations(
    _SensorHistorySummary summary,
    double landAreaSquareMeters,
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
      final baseSeconds = _secondsFromDeficit(deficitPercent);
      final targetVolumeMl = key == 'Moisture'
          ? _estimatedWaterVolumeMl(
              deficitPercent: deficitPercent,
              landAreaSquareMeters: landAreaSquareMeters,
            )
          : _estimatedNutrientVolumeMl(
              baseSeconds: baseSeconds,
              landAreaSquareMeters: landAreaSquareMeters,
            );
      final recommendedSeconds = PumpFlowRates.secondsForVolume(
        pumpIndex: pumpIndex,
        volumeMl: targetVolumeMl,
      );
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
              ? '$nutrient saat ini ${_formatNumber(current)} $unit, kurang ${_formatNumber(deficit)} $unit dari ambang minimum ${_formatNumber(minimum)} $unit. Estimasi penyiraman memakai luas tanah ${_formatNumber(landAreaSquareMeters)} m2 dengan kebutuhan sekitar ${PumpFlowRates.formatMl(targetVolumeMl)} ml; durasi pompa dihitung dari debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk keluaran sekitar ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.'
              : '$nutrient saat ini ${_formatNumber(current)} $unit, kurang ${_formatNumber(deficit)} $unit dari ambang minimum ${_formatNumber(minimum)} $unit. Estimasi nutrisi memakai luas tanah ${_formatNumber(landAreaSquareMeters)} m2 dengan kebutuhan sekitar ${PumpFlowRates.formatMl(targetVolumeMl)} ml; durasi pompa dihitung dari debit rata-rata ${PumpFlowRates.formatRate(flowRate)} ml/detik untuk keluaran sekitar ${PumpFlowRates.formatMl(estimatedVolumeMl)} ml.',
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
      minimum: thresholds['nitrogen_min']!.toDouble(),
    );
    addIfLow(
      key: 'P',
      relay: 2,
      pumpIndex: 1,
      pumpName: 'Pompa B',
      nutrient: 'Fosfor',
      unit: 'mg/kg',
      minimum: thresholds['phosphorus_min']!.toDouble(),
    );
    addIfLow(
      key: 'K',
      relay: 3,
      pumpIndex: 2,
      pumpName: 'Pompa C',
      nutrient: 'Kalium',
      unit: 'mg/kg',
      minimum: thresholds['potassium_min']!.toDouble(),
    );
    addIfLow(
      key: 'Moisture',
      relay: 4,
      pumpIndex: 3,
      pumpName: 'Pompa D',
      nutrient: 'Air',
      unit: '%',
      minimum: thresholds['moisture_min']!.toDouble(),
    );

    return recommendations;
  }

  static double _estimatedNutrientVolumeMl({
    required int baseSeconds,
    required double landAreaSquareMeters,
  }) {
    final safeArea = landAreaSquareMeters <= 0 ? 0.0044 : landAreaSquareMeters;
    final baseVolumePerSquareMeterMl =
        PumpFlowRates.highestRate.averageMlPerSecond * baseSeconds;
    final volumeMl = safeArea * baseVolumePerSquareMeterMl;
    return _roundDouble(volumeMl < 1 ? 1 : volumeMl);
  }

  static String _buildWateringLowAction(
    _SensorHistorySummary summary,
    double landAreaSquareMeters,
  ) {
    final current = summary.parameters['Moisture']?.current;
    final minimum = thresholds['moisture_min']!.toDouble();
    if (current == null || current >= minimum) {
      return 'Pertahankan penyiraman bertahap dan pastikan media teh lembap merata tetapi tidak tergenang.';
    }

    final deficitPercent = _roundDouble(((minimum - current) / minimum) * 100);
    final waterVolumeMl = _estimatedWaterVolumeMl(
      deficitPercent: deficitPercent,
      landAreaSquareMeters: landAreaSquareMeters,
    );
    final seconds = PumpFlowRates.secondsForVolume(
      pumpIndex: 3,
      volumeMl: waterVolumeMl,
    );

    return 'Aktifkan Pump D Water sekitar $seconds detik sebagai penyiraman bertahap awal untuk luas ${_formatNumber(landAreaSquareMeters)} m2 dengan estimasi kebutuhan ${PumpFlowRates.formatMl(waterVolumeMl)} ml. Pastikan media tanam teh lembap merata tetapi tidak tergenang, lalu ukur ulang kelembapan.';
  }

  static double _estimatedWaterVolumeMl({
    required double deficitPercent,
    required double landAreaSquareMeters,
  }) {
    const waterMlPerSquareMeterPerMoisturePercent = 50.0;
    final safeArea = landAreaSquareMeters <= 0 ? 0.0044 : landAreaSquareMeters;
    final volumeMl =
        safeArea * deficitPercent * waterMlPerSquareMeterPerMoisturePercent;
    return _roundDouble(volumeMl < 1 ? 1 : volumeMl);
  }

  static int _secondsFromDeficit(double deficitPercent) {
    final seconds = (10 + (deficitPercent * 2.4)).round();
    return seconds < 5 ? 5 : seconds;
  }

  static double _roundDouble(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static String _formatNullable(double? value) {
    if (value == null) return 'tidak tersedia';
    return _formatNumber(value);
  }

  static String _formatNumber(num value) {
    final rounded = value.toDouble().toStringAsFixed(2);
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

const _systemPrompt =
    'You are an expert AI Agronomist for tea plants (Camellia sinensis), Decision Support System, and Explainable AI (XAI) engine. Analyze the provided historical sensor data summaries (N, P, K, pH, Temp, Moisture, EC) using target ranges for tea plants in general cultivation context. Tea prefers acidic media, stable moisture with good drainage, moderate temperature, and gradual nutrient correction to avoid root stress and EC shock. Output your entire analysis STRICTLY as a single, minified JSON object matching the requested schema. All text must be in Indonesian. The explanation field must provide scientific reasons (XAI) for tea plant health status without assuming a specific cultivation container. The recommendation field must provide concrete follow-up actions that a farmer or user can apply safely and practically for tea plants.';

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
  },
  requiredProperties: [
    'plant_health_percentage',
    'sensor_summary',
    'recommendations',
    'automation_triggers',
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

  bool get canActivateWaterPump {
    final moisture = parameters['Moisture']?.current;
    return moisture != null &&
        moisture < GeminiRecommendationService.thresholds['moisture_min']!;
  }

  bool get canActivateNitrogenPump {
    final n = parameters['N']?.current;
    return n != null &&
        n < GeminiRecommendationService.thresholds['nitrogen_min']!;
  }

  bool get canActivatePhosphorusPump {
    final p = parameters['P']?.current;
    return p != null &&
        p < GeminiRecommendationService.thresholds['phosphorus_min']!;
  }

  bool get canActivatePotassiumPump {
    final k = parameters['K']?.current;
    return k != null &&
        k < GeminiRecommendationService.thresholds['potassium_min']!;
  }

  Map<String, dynamic> toJson() {
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
        'water_pump_allowed': canActivateWaterPump,
        'nitrogen_pump_allowed': canActivateNitrogenPump,
        'phosphorus_pump_allowed': canActivatePhosphorusPump,
        'potassium_pump_allowed': canActivatePotassiumPump,
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
