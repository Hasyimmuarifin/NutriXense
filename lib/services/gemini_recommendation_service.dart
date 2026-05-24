import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/ai_recommendation.dart';

class GeminiRecommendationService {
  GeminiRecommendationService({
    FirebaseFirestore? firestore,
    String? apiKey,
    String? modelName,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _apiKey = apiKey ?? const String.fromEnvironment('GEMINI_API_KEY'),
        _modelName = modelName ??
            const String.fromEnvironment(
              'GEMINI_MODEL',
              defaultValue: 'gemini-2.5-flash',
            );

  static const _collection = 'sensor_data';
  static const _historyLimit = 360;

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
  final String _apiKey;
  final String _modelName;

  Future<AiRecommendationResponse> requestRecommendation() async {
    if (_apiKey.trim().isEmpty) {
      throw StateError(
        'GEMINI_API_KEY belum dikonfigurasi. Jalankan Flutter dengan '
        '--dart-define=GEMINI_API_KEY=YOUR_KEY.',
      );
    }

    final readings = await _fetchRecentReadings();
    if (readings.isEmpty) {
      throw StateError('Belum ada data sensor di koleksi $_collection.');
    }

    final summary = _SensorHistorySummary.fromReadings(readings);
    final model = GenerativeModel(
      model: _modelName,
      apiKey: _apiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 4096,
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
      'output_rules': [
        'Return one complete JSON object only.',
        'Do not use markdown.',
        'Keep every string concise and close all quotes.',
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
    );
    return AiRecommendationResponse.fromJson(decoded).withAutomationGuard(
      canActivateWaterPump: summary.canActivateWaterPump,
      canActivateFertilizerPump: summary.canActivateFertilizerPump,
    );
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
        'original_input': originalPayload,
        'malformed_output': cleaned,
      })),
    ]);

    final repairedText = repairResponse.text;
    final repaired = _tryDecodeJsonObject(_stripCodeFence(repairedText ?? ''));
    if (repaired != null) return repaired;

    throw FormatException(
      'Gemini mengembalikan JSON tidak valid. Coba gunakan model lain '
      'dengan --dart-define=GEMINI_MODEL=gemini-2.5-flash atau kurangi '
      'panjang penjelasan.',
      _shortPreview(cleaned),
    );
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

  static String _shortPreview(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 220) return normalized;
    return '${normalized.substring(0, 220)}...';
  }
}

const _systemPrompt =
    'You are an expert AI Agronomist, Decision Support System, and Explainable AI (XAI) engine. Analyze the provided historical sensor data summaries (N, P, K, pH, Temp, Moisture, EC). Output your entire analysis STRICTLY as a single, minified JSON object matching the requested schema. All text explanations must be in Indonesian, providing scientific reasons (XAI) for the plant health status.';

final _recommendationItemSchema = Schema.object(
  properties: {
    'id': Schema.string(),
    'title': Schema.string(),
    'status': Schema.enumString(enumValues: ['critical', 'warning', 'good']),
    'message': Schema.string(),
    'explanation': Schema.string(),
  },
  requiredProperties: ['id', 'title', 'status', 'message', 'explanation'],
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
        'activate_water_pump': Schema.boolean(),
        'activate_fertilizer_pump': Schema.boolean(),
        'reason': Schema.string(),
      },
      requiredProperties: [
        'activate_water_pump',
        'activate_fertilizer_pump',
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

  bool get canActivateFertilizerPump {
    final n = parameters['N']?.current;
    final p = parameters['P']?.current;
    final k = parameters['K']?.current;
    return (n != null &&
            n < GeminiRecommendationService.thresholds['nitrogen_min']!) ||
        (p != null &&
            p < GeminiRecommendationService.thresholds['phosphorus_min']!) ||
        (k != null &&
            k < GeminiRecommendationService.thresholds['potassium_min']!);
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
        'fertilizer_pump_allowed': canActivateFertilizerPump,
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
