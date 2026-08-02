import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService {
  late MqttServerClient client;
  bool _initialized = false;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  final Set<String> _subscribedTopics = {};
  final _sensorStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _deviceStatusStreamController = StreamController<bool>.broadcast();
  Stream<Map<String, dynamic>> get sensorStream =>
      _sensorStreamController.stream;
  Stream<bool> get deviceStatusStream => _deviceStatusStreamController.stream;
  Function(bool)? onConnectionChanged;

  bool get isConnected =>
      _initialized &&
      client.connectionStatus?.state == MqttConnectionState.connected;

  Map<String, dynamic> parseMessage(String message) {
    try {
      return Map<String, dynamic>.from(jsonDecode(message));
    } catch (e) {
      return {};
    }
  }

  Future<void> init() async {
    if (_initialized && isConnected) return;

    if (!_initialized) {
      client = MqttServerClient.withPort(
        'a8805b4f45744c3f9ac83882e423e0c0.s1.eu.hivemq.cloud',
        'flutter_client_${DateTime.now().millisecondsSinceEpoch}',
        8883,
      );

      client.secure = true;
      client.securityContext = SecurityContext.defaultContext;

      client.keepAlivePeriod = 20;

      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;

      client.onConnected = onConnected;
      client.onDisconnected = onDisconnected;
      client.onSubscribed = onSubscribed;
      _initialized = true;
    }

    await connect();
  }

  Future<void> connect() async {
    try {
      debugPrint('MQTT Connecting...');
      await client.connect('hasyim', 'hasyimHiveMQTT@22');
    } catch (e) {
      debugPrint('MQTT Error: $e');
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      debugPrint('MQTT Connected');
    } else {
      debugPrint('MQTT Failed');
      client.disconnect();
    }
  }

  void subscribe(String topic) {
    if (!isConnected) return;

    if (_subscribedTopics.add(topic)) {
      client.subscribe(topic, MqttQos.atMostOnce);
    }

    _updatesSub ??= client.updates!.listen((event) {
      final recMess = event[0].payload as MqttPublishMessage;
      final msg = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      final topic = event[0].topic;

      debugPrint('MQTT Message [$topic]: $msg');
      try {
        final data = jsonDecode(msg);

        if (topic == 'nutrixense/sensor' && data is Map<String, dynamic>) {
          _sensorStreamController.add(data);
        } else if (topic == 'nutrixense/status') {
          final status = _parseDeviceOnlineStatus(data);
          if (status != null) {
            _deviceStatusStreamController.add(status);
          }
        }
      } catch (e) {
        if (topic == 'nutrixense/status') {
          final status = _parseDeviceOnlineStatus(msg);
          if (status != null) {
            _deviceStatusStreamController.add(status);
          }
        } else {
          debugPrint("JSON ERROR: $e");
        }
      }
    });
  }

  bool? _parseDeviceOnlineStatus(dynamic payload) {
    if (payload is bool) return payload;
    if (payload is num) return payload != 0;

    if (payload is String) {
      final normalized = payload.trim().toLowerCase();
      if (['online', 'connected', 'on', 'true', '1', 'aktif'].contains(
        normalized,
      )) {
        return true;
      }
      if (['offline', 'disconnected', 'off', 'false', '0', 'mati'].contains(
        normalized,
      )) {
        return false;
      }
    }

    if (payload is Map<String, dynamic>) {
      for (final key in [
        'online',
        'connected',
        'device_online',
        'iot_online',
        'status',
        'state',
      ]) {
        if (payload.containsKey(key)) {
          final status = _parseDeviceOnlineStatus(payload[key]);
          if (status != null) return status;
        }
      }
    }

    return null;
  }

  void publish(String topic, String message, {bool retain = false}) {
    if (!isConnected) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    client.publishMessage(
      topic,
      MqttQos.exactlyOnce,
      builder.payload!,
      retain: retain,
    );
  }

  void setRelay(
    int relay,
    bool isOn, {
    String source = 'manual_control',
  }) {
    publishRelay(relay, isOn, source: source);
  }

  void setExclusiveRelay(
    int activeRelay, {
    String source = 'manual_control',
  }) {
    final commandSource = source.trim().isEmpty ? 'manual_control' : source;
    final payload = jsonEncode({
      "source": "manual_control",
      if (commandSource != 'manual_control') "command_source": commandSource,
      "manual_override": 1,
      "relay1": activeRelay == 1 ? 1 : 0,
      "relay2": activeRelay == 2 ? 1 : 0,
      "relay3": activeRelay == 3 ? 1 : 0,
      "relay4": activeRelay == 4 ? 1 : 0,
    });

    publish("nutrixense/control", payload);
    debugPrint("Exclusive Relay Command Sent: $payload");
  }

  void turnAllRelaysOff({
    String source = 'manual_control',
  }) {
    final commandSource = source.trim().isEmpty ? 'manual_control' : source;
    final payload = jsonEncode({
      "source": "manual_control",
      if (commandSource != 'manual_control') "command_source": commandSource,
      "manual_override": 0,
      "relay1": 0,
      "relay2": 0,
      "relay3": 0,
      "relay4": 0,
    });

    publish("nutrixense/control", payload);
    debugPrint("All Relays OFF Command Sent: $payload");
  }

  void publishRelay(
    int relay,
    bool state, {
    String source = 'manual_control',
  }) {
    final commandSource = source.trim().isEmpty ? 'manual_control' : source;
    final payload = jsonEncode({
      "source": "manual_control",
      if (commandSource != 'manual_control') "command_source": commandSource,
      "manual_override": state ? 1 : 0,
      "relay1": relay == 1 && state ? 1 : 0,
      "relay2": relay == 2 && state ? 1 : 0,
      "relay3": relay == 3 && state ? 1 : 0,
      "relay4": relay == 4 && state ? 1 : 0,
    });

    publish("nutrixense/control", payload);

    debugPrint("Relay Command Sent: $payload");
  }

  void onConnected() {
    onConnectionChanged?.call(true);
    debugPrint('MQTT Connected Callback');
  }

  void onDisconnected() {
    onConnectionChanged?.call(false);
    debugPrint('MQTT Disconnected');
  }

  void onSubscribed(String topic) {
    debugPrint('Subscribed to $topic');
  }
}
