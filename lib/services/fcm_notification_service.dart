import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('FCM background message received: ${message.messageId}');
}

class FcmNotificationService {
  FcmNotificationService._();

  static final FcmNotificationService instance = FcmNotificationService._();

  static const MethodChannel _alertsChannel =
      MethodChannel('com.example.nutrixense/alerts');
  static const String _topic = 'nutrixense_alerts';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    await _requestPermission();
    await _subscribeToTopic();
    await _logRegistrationToken();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }

    _messaging.onTokenRefresh.listen((token) {
      debugPrint('FCM registration token refreshed: $token');
      unawaited(_subscribeToTopic());
    });
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint(
      'FCM notification permission: ${settings.authorizationStatus.name}',
    );
  }

  Future<void> _subscribeToTopic() async {
    try {
      await _messaging.subscribeToTopic(_topic);
      debugPrint('Subscribed to FCM topic: $_topic');
    } catch (error) {
      debugPrint('FCM topic subscription failed: $error');
    }
  }

  Future<void> _logRegistrationToken() async {
    try {
      final token = await _messaging.getToken();
      debugPrint('FCM registration token: $token');
    } catch (error) {
      debugPrint('FCM token retrieval failed: $error');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        (message.data['type']?.toString() == 'threshold_alert'
            ? 'Peringatan Nutrisi Tanaman'
            : 'NutriXense notification');
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        (message.data['type']?.toString() == 'threshold_alert'
            ? 'Pembacaan sensor berada di luar ambang batas normal.'
            : 'A new NutriXense update is available.');
    final detailBody = message.data['detailBody']?.toString();
    final recentAlertCount =
        int.tryParse(message.data['recentAlertCount']?.toString() ?? '');
    final notificationKey = message.data['notificationKey']?.toString() ??
        message.data['logId']?.toString();

    debugPrint('FCM foreground message received: ${message.messageId}');

    try {
      await _alertsChannel.invokeMethod<void>('showNutrientAlert', {
        'title': title,
        'message': detailBody?.trim().isNotEmpty == true ? detailBody : body,
        if (recentAlertCount != null) 'recentAlertCount': recentAlertCount,
        if (notificationKey?.isNotEmpty == true)
          'notificationKey': notificationKey,
      });
    } on PlatformException catch (error) {
      debugPrint('FCM foreground notification failed: ${error.message}');
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    debugPrint('FCM notification opened: ${message.messageId}');
  }
}
