# ── mobile_scanner Flutter plugin ─────────────────────────────
-keep class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**

# ── Google ML Kit & Barcode Scanning ──────────────────────────
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.android.gms.vision.**

-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**

-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode_bundled.**

# ── Barhopper (Native barcode detector backbone used by ML Kit) ──
-keep class com.google.android.libraries.barhopper.** { *; }
-dontwarn com.google.android.libraries.barhopper.**

# ── CameraX (Used internally by mobile_scanner) ────────────────
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.camera2.** { *; }

# ── Flutter & Platform plugins ────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
