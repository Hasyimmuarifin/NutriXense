import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/ai_recommendation.dart';

class GeminiRecommendationService {
  GeminiRecommendationService({
    FirebaseFirestore? firestore,
    String? apiKey,
    String? modelName,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _apiKeyOverride = apiKey,
        _modelNameOverride = modelName;

  static const _collection = 'sensor_data';
  static const _historyLimit = 360;
  static const _configAssetPath = 'assets/config/gemini_config.json';
  static const _dartDefineApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _dartDefineModelName = String.fromEnvironment('GEMINI_MODEL');

  // Tune these to match the crop and calibration used in your TA experiment.
  static const thresholds = {
    'nitrogen_min': 40,
    'phosphorus_min': 20,
    'potassium_min': 40,
    'moisture_min': 35,
    'ph_min': 5.8,
    'ph_max': 7.2,
    'temperature_min': 18,
    'temperature_max': 35,
    'ec_min': 0.8,
    'ec_max': 2.5,
  };

  final FirebaseFirestore _firestore;
  final String? _apiKeyOverride;
  final String? _modelNameOverride;

  Future<AiRecommendationResponse> requestRecommendation() async {
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
          'Analyze this condensed IoT plant sensor history and return JSON only.',
      'language': 'id',
      'control_policy':
          'automation_triggers must be based on numeric thresholds only.',
      'pump_mapping': {
        'activate_nitrogen_pump': 'Pump A - Nitrogen (N)',
        'activate_phosphorus_pump': 'Pump B - Phosphorus (P)',
        'activate_potassium_pump': 'Pump C - Potassium (K)',
        'activate_water_pump': 'Pump D - Water (H2O)',
      },
      'output_rules': [
        'Return one complete JSON object only.',
        'Do not use markdown.',
        'Keep every string concise and close all quotes.',
        'sensor_summary maximum 2 sentences.',
        'Return maximum 7 recommendation items total.',
        'For each item, message maximum 1 sentence, explanation maximum 2 sentences, recommendation maximum 2 sentences.',
        'For each recommendation item, explanation must explain why the condition happened from the sensor data.',
        'For each recommendation item, recommendation must explain specific follow-up actions a farmer/user can take.',
        'Recommendations must be practical, safe, and measurable when possible, such as pump use, irrigation, pH correction, fertilizer adjustment, retesting, or monitoring frequency.',
        'Set an automation trigger to true only when its matching local_threshold_flag is true.',
      ],
      'thresholds': thresholds,
      'history_summary': summary.toJson(),
    });

    final response = await model.generateContent([Content.text(payload)]);

    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw StateError('Gemini tidak mengembalikan teks JSON.');
    }

    final decoded = await _decodeJsonResponse(
      model: model,
      rawText: text,
      originalPayload: payload,
      summary: summary,
    );
    return AiRecommendationResponse.fromJson(decoded).withAutomationGuard(
      canActivateWaterPump: summary.canActivateWaterPump,
      canActivateNitrogenPump: summary.canActivateNitrogenPump,
      canActivatePhosphorusPump: summary.canActivatePhosphorusPump,
      canActivatePotassiumPump: summary.canActivatePotassiumPump,
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
  }) async {
    final cleaned = _stripCodeFence(rawText);
    final decoded = _tryDecodeJsonObject(cleaned);
    if (decoded != null) return decoded;

    final repairResponse = await model.generateContent([
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
    ]);

    final repairedText = repairResponse.text;
    final repaired = _tryDecodeJsonObject(_stripCodeFence(repairedText ?? ''));
    if (repaired != null) return repaired;

    debugPrint(
      'Gemini returned malformed JSON after repair. Using local fallback. '
      'Preview: ${_shortPreview(cleaned)}',
    );
    return _buildLocalFallbackResponse(summary);
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

  static Map<String, dynamic> _buildLocalFallbackResponse(
    _SensorHistorySummary summary,
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
          status: 'critical',
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
          status: 'warning',
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
          status: 'good',
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
      max: 80,
      lowTitle: 'Nitrogen Rendah',
      highTitle: 'Nitrogen Berlebih',
      lowAction:
          'Aktifkan Pump A sesuai durasi DSS, lalu pantau ulang NPK setelah pencampuran merata. Hindari penambahan berlebihan agar pH dan EC tidak ikut melonjak.',
      highAction:
          'Tunda penambahan nitrogen dan lakukan pengenceran bertahap bila EC ikut tinggi. Pantau ulang N dan EC pada pembacaan berikutnya.',
      normalAction:
          'Pertahankan dosis nitrogen saat ini dan lanjutkan pemantauan berkala.',
    );
    evaluateRange(
      key: 'P',
      label: 'Phosphorus',
      unit: 'mg/kg',
      min: thresholds['phosphorus_min']!,
      max: 60,
      lowTitle: 'Phosphorus Rendah',
      highTitle: 'Phosphorus Berlebih',
      lowAction:
          'Aktifkan Pump B sesuai aturan DSS dan pastikan larutan tercampur sebelum evaluasi ulang. Periksa juga pH karena pH ekstrem dapat menghambat ketersediaan fosfor.',
      highAction:
          'Hentikan sementara suplai fosfor dan pantau EC serta pH. Lakukan pengenceran ringan jika konsentrasi nutrisi keseluruhan meningkat.',
      normalAction:
          'Pertahankan suplai fosfor dan pantau tren harian untuk mencegah penurunan.',
    );
    evaluateRange(
      key: 'K',
      label: 'Potassium',
      unit: 'mg/kg',
      min: thresholds['potassium_min']!,
      max: 100,
      lowTitle: 'Potassium Rendah',
      highTitle: 'Potassium Berlebih',
      lowAction:
          'Aktifkan Pump C sesuai durasi DSS, lalu ulangi pembacaan setelah nutrisi tersebar merata. Perhatikan keseimbangan NPK agar satu unsur tidak mendominasi.',
      highAction:
          'Tunda penambahan kalium dan pantau EC. Jika nilai tetap tinggi, kurangi konsentrasi larutan secara bertahap.',
      normalAction:
          'Kadar kalium sudah memadai, lanjutkan pemantauan bersama N dan P.',
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
          'Naikkan pH secara bertahap menggunakan korektor pH up dalam dosis kecil. Aduk larutan dan tunggu sebelum pengukuran ulang agar perubahan tidak berlebihan.',
      highAction:
          'Turunkan pH secara bertahap menggunakan korektor pH down. Hindari koreksi besar sekaligus karena dapat menyebabkan fluktuasi dan stres akar.',
      normalAction:
          'pH berada pada zona serapan hara yang baik, pertahankan prosedur pemantauan.',
    );
    evaluateRange(
      key: 'Moisture',
      label: 'Soil Moisture',
      unit: '%',
      min: thresholds['moisture_min']!,
      max: 80,
      lowTitle: 'Kelembapan Media Rendah',
      highTitle: 'Kelembapan Media Tinggi',
      lowAction:
          'Aktifkan Pump D Water atau gunakan jadwal penyiraman otomatis dengan durasi pendek. Pastikan drainase baik dan ulangi pembacaan setelah air meresap.',
      highAction:
          'Tunda penyiraman dan periksa drainase media. Jika kelembapan tetap tinggi, kurangi frekuensi irigasi untuk mencegah akar kekurangan oksigen.',
      normalAction:
          'Kelembapan media cukup, pertahankan jadwal penyiraman saat ini.',
    );
    evaluateRange(
      key: 'Temp',
      label: 'Temperature',
      unit: '°C',
      min: thresholds['temperature_min']!,
      max: thresholds['temperature_max']!,
      lowTitle: 'Suhu Terlalu Rendah',
      highTitle: 'Suhu Terlalu Tinggi',
      lowAction:
          'Kurangi paparan dingin dan pastikan lingkungan tumbuh stabil. Pantau suhu bersama kelembapan karena perubahan suhu dapat memengaruhi penguapan.',
      highAction:
          'Aktifkan Pump D Water sesuai DSS bila diperlukan untuk membantu menurunkan stres panas, lalu tingkatkan ventilasi atau naungan. Pantau ulang suhu dan kelembapan setiap beberapa menit.',
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
          'Tambahkan nutrisi secara bertahap melalui pompa NPK yang sesuai dengan unsur yang rendah. Ukur ulang EC setelah pencampuran agar konsentrasi tidak melewati target.',
      highAction:
          'Encerkan larutan dengan air bersih secara bertahap dan tunda penambahan pupuk. Pantau ulang EC serta pH setelah larutan stabil.',
      normalAction:
          'EC stabil, pertahankan konsentrasi larutan dan pantau perubahan setelah irigasi.',
    );

    final critical = items
        .where((item) => item['status'] == 'critical')
        .toList(growable: false);
    final warning = items
        .where((item) => item['status'] == 'warning')
        .toList(growable: false);
    final good =
        items.where((item) => item['status'] == 'good').toList(growable: false);
    final scorePenalty = (critical.length * 15) + (warning.length * 8);

    return {
      'plant_health_percentage': (100 - scorePenalty).clamp(0, 100),
      'sensor_summary':
          'Analisis lokal menggunakan ${summary.rowCount} data sensor terbaru karena respons JSON Gemini tidak valid. Ringkasan tetap menilai NPK, pH, suhu, kelembapan, dan EC berdasarkan ambang batas DSS yang tersimpan.',
      'recommendations': {
        'all': items,
        'critical': critical,
        'warning': warning,
        'good': good,
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

const _systemPrompt =
    'You are an expert AI Agronomist, Decision Support System, and Explainable AI (XAI) engine. Analyze the provided historical sensor data summaries (N, P, K, pH, Temp, Moisture, EC). Output your entire analysis STRICTLY as a single, minified JSON object matching the requested schema. All text must be in Indonesian. The explanation field must provide scientific reasons (XAI) for the plant health status. The recommendation field must provide concrete follow-up actions that a farmer or user can apply safely and practically.';

final _recommendationItemSchema = Schema.object(
  properties: {
    'id': Schema.string(),
    'title': Schema.string(),
    'status': Schema.enumString(enumValues: ['critical', 'warning', 'good']),
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
        'critical': Schema.array(items: _recommendationItemSchema),
        'warning': Schema.array(items: _recommendationItemSchema),
        'good': Schema.array(items: _recommendationItemSchema),
      },
      requiredProperties: ['all', 'critical', 'warning', 'good'],
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
