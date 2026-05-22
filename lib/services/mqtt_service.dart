import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';


class MQTTService {
  late MqttServerClient client;
  final _sensorStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sensorStream => _sensorStreamController.stream;
  Function(bool)? onConnectionChanged;

  Map<String, dynamic> parseMessage(String message) {
    try {
      return Map<String, dynamic>.from(jsonDecode(message));
    } catch (e) {
      return {};
    }
  }

  Future<void> init() async {
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

    await connect();
  }

  Future<void> connect() async {
    try {
      print('MQTT Connecting...');
      await client.connect('hasyim', 'hasyimHiveMQTT@22');
    } catch (e) {
      print('MQTT Error: $e');
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('MQTT Connected');
    } else {
      print('MQTT Failed');
      client.disconnect();
    }
  }

  void subscribe(String topic) {
    client.subscribe(topic, MqttQos.atMostOnce);

    client.updates!.listen((event) {
      final recMess = event[0].payload as MqttPublishMessage;
      final msg = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );

      print('MQTT Message: $msg');
      try {
        final data = jsonDecode(msg);

        if (data is Map<String, dynamic>) {
          _sensorStreamController.add(data);
        }
      } catch (e) {
        print("JSON ERROR: $e");
      }
    });
  }

  void publish(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    client.publishMessage(topic, MqttQos.exactlyOnce, builder.payload!);
  }

  void setRelay(int relay, bool isOn) {
    publishRelay(relay, !isOn);
  }

  void publishRelay(int relay, bool state) {

    final payload = jsonEncode({
      "relay$relay": state ? 1 : 0
    });

    publish("nutrixense/control", payload);

    print("Relay Command Sent: $payload");
  }

  void onConnected() {
    onConnectionChanged?.call(true);
    print('MQTT Connected Callback');
  }

  void onDisconnected() {
    onConnectionChanged?.call(false);
    print('MQTT Disconnected');
  }

  void onSubscribed(String topic) {
    print('Subscribed to $topic');
  }
}
