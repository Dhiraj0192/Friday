package com.privateagent.private_agent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Brings Friday back after the phone restarts or the app is updated. */
class FridayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> FridayKeepAliveService.start(context)
        }
    }
}
