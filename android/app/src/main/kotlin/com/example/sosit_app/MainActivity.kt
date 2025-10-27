package com.example.sosit_app

import android.content.Context
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sosit/sim")
			.setMethodCallHandler { call, result ->
				if (call.method == "hasSim") {
					try {
						val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
						val simState = tm.simState
						val hasSim = simState != TelephonyManager.SIM_STATE_ABSENT && simState != TelephonyManager.SIM_STATE_UNKNOWN
						result.success(hasSim)
					} catch (e: Exception) {
						result.error("UNAVAILABLE", e.message, null)
					}
				} else {
					result.notImplemented()
				}
			}
	}
}
