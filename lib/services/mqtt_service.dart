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
  Stream<Map<String, dynamic>> get sensorStream =>
      _sensorStreamController.stream;
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

      debugPrint('MQTT Message: $msg');
      try {
        final data = jsonDecode(msg);

        if (data is Map<String, dynamic>) {
          _sensorStreamController.add(data);
        }
      } catch (e) {
        debugPrint("JSON ERROR: $e");
      }
    });
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

  void setRelay(int relay, bool isOn) {
    publishRelay(relay, isOn);
  }

  void publishRelay(int relay, bool state) {
    final payload = jsonEncode({"relay$relay": state ? 1 : 0});

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
