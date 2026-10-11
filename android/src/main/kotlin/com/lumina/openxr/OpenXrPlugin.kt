package com.lumina.openxr

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Hands the Activity to the native OpenXR bridge: xrInitializeLoaderKHR and
 * XR_KHR_android_create_instance need the JavaVM and the activity. Loading the
 * bridge here (the native-assets hook bundles it as libopenxr_bridge.so) runs its
 * JNI_OnLoad; Dart then opens the same library.
 */
class OpenXrPlugin : FlutterPlugin, ActivityAware {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        loaded = try {
            System.loadLibrary("openxr_bridge")
            true
        } catch (e: UnsatisfiedLinkError) {
            false
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding.activity)

    override fun onDetachedFromActivityForConfigChanges() = attach(null)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding.activity)

    override fun onDetachedFromActivity() = attach(null)

    private fun attach(activity: Activity?) {
        if (loaded) nativeSetActivity(activity)
    }

    companion object {
        private var loaded = false

        @JvmStatic
        private external fun nativeSetActivity(activity: Activity?)
    }
}
