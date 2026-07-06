import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';
import 'threshold_notification_cooldown_service.dart';

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
        'NutriXense notification';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        'A new NutriXense update is available.';

    debugPrint('FCM foreground message received: ${message.messageId}');

    try {
      if (_isThresholdAlert(message, title)) {
        final canShowNotification = await ThresholdNotificationCooldownService
            .instance
            .tryAcquireNotificationSlot();

        if (!canShowNotification) {
          debugPrint(
            'FCM threshold notification suppressed by shared 5-minute cooldown.',
          );
          return;
        }
      }

      await _alertsChannel.invokeMethod<void>('showNutrientAlert', {
        'title': title,
        'message': body,
      });
    } on PlatformException catch (error) {
      debugPrint('FCM foreground notification failed: ${error.message}');
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    debugPrint('FCM notification opened: ${message.messageId}');
  }

  bool _isThresholdAlert(RemoteMessage message, String title) {
    return message.data['type']?.toString() == 'threshold_alert' ||
        title == 'Peringatan Nutrisi Tanaman';
  }
}
