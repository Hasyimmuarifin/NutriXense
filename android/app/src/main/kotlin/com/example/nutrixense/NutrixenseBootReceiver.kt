package com.example.nutrixense

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class NutrixenseBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!NutrixenseBackgroundService.isEnabled(context) &&
            !NutrixenseBackgroundService.isAlertMonitorEnabled(context) &&
            !NutrixenseBackgroundService.hasEnabledSchedules(context)
        ) {
            return
        }

        val serviceIntent = Intent(context, NutrixenseBackgroundService::class.java).apply {
            action = if (NutrixenseBackgroundService.isEnabled(context)) {
                NutrixenseBackgroundService.ACTION_START
            } else if (NutrixenseBackgroundService.isAlertMonitorEnabled(context)) {
                NutrixenseBackgroundService.ACTION_START_ALERT_MONITOR
            } else {
                NutrixenseBackgroundService.ACTION_SYNC_SCHEDULES
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
