# Règles R8 (minification des builds release).
#
# shared_preferences_android ≥ 2.5 est généré par jnigen : le code Dart appelle les méthodes Kotlin
# PAR LEUR NOM via JNI (ex. SharedPreferencesApiRegistrar.getAll), et ces méthodes s'appuient sur les
# coroutines Kotlin (fonctions suspend). R8 ne voit pas ces appels : il supprimait ou renommait les
# classes du plugin puis des classes internes de Kotlin (NoSuchMethodError, ClassNotFoundException
# CoroutineSingletons) → plantage au démarrage en release, splash figé.
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Bibliothèque standard Kotlin et coroutines : conservées entières (les signatures et classes internes
# utilisées via JNI ne sont pas visibles par R8).
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Pont JNI de Dart (déjà protégé par ses propres règles, rappelé par sécurité).
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
