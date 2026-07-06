import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThresholdNotificationCooldownService {
  ThresholdNotificationCooldownService._();

  static final ThresholdNotificationCooldownService instance =
      ThresholdNotificationCooldownService._();

  static const Duration cooldown = Duration(minutes: 5);
  static const String _lastShownAtStorageKey =
      'nutrixense_threshold_notification_last_shown_at_ms';

  Future<void> _queue = Future<void>.value();

  Future<bool> tryAcquireNotificationSlot() {
    final operation = _queue.catchError((_) {}).then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final nowMillis = DateTime.now().millisecondsSinceEpoch;
        final lastShownAtMillis = prefs.getInt(_lastShownAtStorageKey);

        if (lastShownAtMillis != null &&
            nowMillis - lastShownAtMillis < cooldown.inMilliseconds) {
          return false;
        }

        await prefs.setInt(_lastShownAtStorageKey, nowMillis);
        return true;
      } catch (error) {
        debugPrint('Threshold notification cooldown skipped: $error');
        return true;
      }
    });

    _queue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }
}
