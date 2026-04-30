/**
 * This file is a part of media_kit (https://github.com/media-kit/media-kit).
 * <p>
 * Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
 * All rights reserved.
 * Use of this source code is governed by MIT license that can be found in the LICENSE file.
 */
package com.alexmercerind.media_kit_video;

import android.app.Activity;
import android.app.Application;
import android.app.PictureInPictureParams;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.Rational;

import androidx.activity.ComponentActivity;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Bridges {@link android.app.Activity#enterPictureInPictureMode} with
 * {@code com.alexmercerind/media_kit_video/pip} Flutter channels.
 * <p>
 * PiP is available from API 26 (Android 8.0); on older devices every method
 * either returns {@code false}/{@code null} or silently no-ops. The
 * {@link Activity#addOnPictureInPictureModeChangedListener} callback is only
 * available from API 31; on API 26-30 lifecycle events are limited to
 * {@code willStart}.
 */
final class MediaKitPictureInPictureManager {
    private static final String TAG = "MediaKitVideoPiP";
    private static final String METHOD_CHANNEL = "com.alexmercerind/media_kit_video/pip";
    private static final String EVENT_CHANNEL = "com.alexmercerind/media_kit_video/pip/events";

    private final MethodChannel methodChannel;
    private final EventChannel eventChannel;

    @Nullable
    private Activity activity;
    @Nullable
    private EventChannel.EventSink eventSink;

    private boolean autoEnter = false;
    private int preferredWidth = 16;
    private int preferredHeight = 9;

    // Lifecycle-based detection for PiP exit cause. Android's
    // OnPictureInPictureModeChangedListener fires when PiP ends, but it
    // does not tell us *why* (X-button vs tap-to-expand). Activity.isFinishing()
    // is also unreliable: the X button just moves the activity to the stopped
    // state, it does not finish it. So when PiP exits we defer the dispatch and
    // let the next Activity lifecycle callback decide:
    //   - onActivityResumed → user tapped to expand → dispatch "didStop"
    //   - onActivityStopped → user closed PiP via X → dispatch "closed"
    @Nullable
    private Application.ActivityLifecycleCallbacks pipLifecycleCallbacks;
    private boolean pendingPipExitDecision = false;
    @Nullable
    private Runnable pendingPipExitTimeout;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    MediaKitPictureInPictureManager(@NonNull BinaryMessenger messenger) {
        methodChannel = new MethodChannel(messenger, METHOD_CHANNEL);
        eventChannel = new EventChannel(messenger, EVENT_CHANNEL);

        methodChannel.setMethodCallHandler((call, result) -> handleMethodCall(call, result));
        eventChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                eventSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                eventSink = null;
            }
        });
    }

    void attachActivity(@NonNull Activity activity) {
        this.activity = activity;
        registerModeChangedListener();
    }

    void detachActivity() {
        unregisterModeChangedListener();
        this.activity = null;
    }

    void dispose() {
        unregisterModeChangedListener();
        methodChannel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
        eventSink = null;
        activity = null;
    }

    private void handleMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "isSupported": {
                result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activityHasPipFeature());
                break;
            }
            case "isActive": {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity != null) {
                    result.success(activity.isInPictureInPictureMode());
                } else {
                    result.success(false);
                }
                break;
            }
            case "start": {
                handleStart(call, result);
                break;
            }
            case "stop": {
                // Android has no programmatic way to leave PiP; the system
                // handles it when the user restores the app. We clear local
                // state so subsequent start() re-arms listeners.
                autoEnter = false;
                applyAutoEnter();
                result.success(null);
                break;
            }
            case "setAutoEnter": {
                final Boolean enabled = call.argument("enabled");
                autoEnter = Boolean.TRUE.equals(enabled);
                applyAutoEnter();
                result.success(null);
                break;
            }
            default: {
                result.notImplemented();
                break;
            }
        }
    }

    private void handleStart(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(null);
            return;
        }
        if (activity == null) {
            result.error("NO_ACTIVITY", "No host Activity available", null);
            return;
        }

        final Double width = call.argument("width");
        final Double height = call.argument("height");
        final Boolean autoEnterArg = call.argument("autoEnter");
        final Boolean startImmediately = call.argument("startImmediately");

        if (width != null && width > 0 && height != null && height > 0) {
            preferredWidth = clampAspect((int) Math.round(width));
            preferredHeight = clampAspect((int) Math.round(height));
        }
        autoEnter = Boolean.TRUE.equals(autoEnterArg);

        applyAutoEnter();

        if (Boolean.TRUE.equals(startImmediately)) {
            enterPictureInPictureNow();
        }
        result.success(null);
    }

    private void applyAutoEnter() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity == null) {
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                final PictureInPictureParams params = new PictureInPictureParams.Builder()
                        .setAspectRatio(new Rational(preferredWidth, preferredHeight))
                        .setAutoEnterEnabled(autoEnter)
                        .build();
                activity.setPictureInPictureParams(params);
            } catch (Throwable t) {
                Log.w(TAG, "Failed to set PictureInPictureParams: " + t.getMessage());
            }
        }
    }

    private void enterPictureInPictureNow() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity == null) {
            return;
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                final PictureInPictureParams params = new PictureInPictureParams.Builder()
                        .setAspectRatio(new Rational(preferredWidth, preferredHeight))
                        .build();
                dispatchEvent("willStart", null);
                final boolean ok = activity.enterPictureInPictureMode(params);
                if (!ok) {
                    dispatchEvent("failed", "enter_pip_rejected");
                }
            }
        } catch (Throwable t) {
            dispatchEvent("failed", t.getMessage() != null ? t.getMessage() : "enter_pip_threw");
        }
    }

    private boolean activityHasPipFeature() {
        if (activity == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return false;
        }
        return activity.getPackageManager().hasSystemFeature(
                android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE);
    }

    private void registerModeChangedListener() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || activity == null) {
            return;
        }
        // addOnPictureInPictureModeChangedListener is on
        // androidx.activity.ComponentActivity (not on android.app.Activity).
        // Hosts using `FlutterFragmentActivity` (which extends
        // FragmentActivity → ComponentActivity) get this for free; hosts
        // using bare `FlutterActivity` (which extends android.app.Activity
        // directly) need to migrate or the PiP mode listener won't work.
        if (!(activity instanceof ComponentActivity)) {
            Log.w(TAG, "Activity is not a ComponentActivity — extend "
                    + "FlutterFragmentActivity instead of FlutterActivity "
                    + "to enable PiP exit detection. Activity is: "
                    + activity.getClass().getName());
            return;
        }
        ((ComponentActivity) activity).addOnPictureInPictureModeChangedListener(info -> {
            if (info.isInPictureInPictureMode()) {
                clearPendingPipExitDecision();
                dispatchEvent("didStart", null);
            } else {
                pendingPipExitDecision = true;
                dispatchEvent("willStop", null);
                schedulePendingExitTimeout();
            }
        });
        registerLifecycleCallbacks();
    }

    private void unregisterModeChangedListener() {
        unregisterLifecycleCallbacks();
        clearPendingPipExitDecision();
        // The Activity cleans up its own PiP-mode listeners on destroy;
        // detaching our reference is sufficient for those.
    }

    private void registerLifecycleCallbacks() {
        if (activity == null || pipLifecycleCallbacks != null) {
            return;
        }
        pipLifecycleCallbacks = new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityResumed(@NonNull Activity a) {
                if (a == activity && pendingPipExitDecision) {
                    clearPendingPipExitDecision();
                    // Activity returned to the foreground → user tapped the
                    // PiP window to expand the app back.
                    dispatchEvent("didStop", null);
                }
            }

            @Override
            public void onActivityStopped(@NonNull Activity a) {
                if (a == activity && pendingPipExitDecision) {
                    clearPendingPipExitDecision();
                    // Activity went to the stopped state without resuming →
                    // user dismissed the PiP window via the X button.
                    dispatchEvent("closed", null);
                }
            }

            @Override public void onActivityCreated(@NonNull Activity a, @Nullable Bundle s) {}
            @Override public void onActivityStarted(@NonNull Activity a) {}
            @Override public void onActivityPaused(@NonNull Activity a) {}
            @Override public void onActivitySaveInstanceState(@NonNull Activity a, @NonNull Bundle s) {}
            @Override public void onActivityDestroyed(@NonNull Activity a) {}
        };
        try {
            activity.getApplication().registerActivityLifecycleCallbacks(pipLifecycleCallbacks);
        } catch (Throwable t) {
            Log.w(TAG, "Failed to register lifecycle callbacks: " + t.getMessage());
            pipLifecycleCallbacks = null;
        }
    }

    private void unregisterLifecycleCallbacks() {
        if (activity == null || pipLifecycleCallbacks == null) {
            return;
        }
        try {
            activity.getApplication().unregisterActivityLifecycleCallbacks(pipLifecycleCallbacks);
        } catch (Throwable t) {
            Log.w(TAG, "Failed to unregister lifecycle callbacks: " + t.getMessage());
        }
        pipLifecycleCallbacks = null;
    }

    /**
     * Defensive fallback: if neither onActivityResumed nor onActivityStopped
     * fires within a short window after PiP exits (e.g. unusual OEM behaviour),
     * default to "closed" so the consumer pauses. Erring on the side of pausing
     * is safer than leaving audio playing without a visible PiP window.
     */
    private void schedulePendingExitTimeout() {
        if (pendingPipExitTimeout != null) {
            mainHandler.removeCallbacks(pendingPipExitTimeout);
        }
        pendingPipExitTimeout = () -> {
            if (pendingPipExitDecision) {
                pendingPipExitDecision = false;
                dispatchEvent("closed", null);
            }
            pendingPipExitTimeout = null;
        };
        mainHandler.postDelayed(pendingPipExitTimeout, 1000);
    }

    private void clearPendingPipExitDecision() {
        pendingPipExitDecision = false;
        if (pendingPipExitTimeout != null) {
            mainHandler.removeCallbacks(pendingPipExitTimeout);
            pendingPipExitTimeout = null;
        }
    }

    private void dispatchEvent(@NonNull String name, @Nullable String reason) {
        final EventChannel.EventSink sink = eventSink;
        if (sink == null) return;
        final Map<String, Object> payload = new HashMap<>();
        payload.put("event", name);
        if (reason != null) payload.put("reason", reason);
        sink.success(payload);
    }

    private static int clampAspect(int value) {
        if (value < 1) return 1;
        if (value > 1000) return 1000;
        return value;
    }
}
