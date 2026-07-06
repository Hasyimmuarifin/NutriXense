import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const Duration appSnackBarDuration = Duration(seconds: 1);
const Duration appErrorSnackBarDuration = Duration(seconds: 3);

void showAppSnackBar(
  BuildContext context, {
  required Widget content,
  required Color backgroundColor,
  Duration? duration,
  EdgeInsetsGeometry? margin,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: content,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      duration: duration ?? _durationForColor(backgroundColor),
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

void showAppTextSnackBar(
  BuildContext context,
  String message,
  Color backgroundColor, {
  Duration? duration,
  EdgeInsetsGeometry? margin,
}) {
  showAppSnackBar(
    context,
    content: Text(message),
    backgroundColor: backgroundColor,
    duration: duration,
    margin: margin,
  );
}

Duration _durationForColor(Color backgroundColor) {
  if (backgroundColor.value == AppTheme.statusLow.value ||
      backgroundColor.value == AppTheme.statusHigh.value) {
    return appErrorSnackBarDuration;
  }

  return appSnackBarDuration;
}
