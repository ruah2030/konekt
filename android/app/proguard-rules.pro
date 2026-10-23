# Règles R8 (minification des builds release).
#
# shared_preferences_android ≥ 2.5 est généré par jnigen : le code Dart appelle les méthodes Kotlin
# PAR LEUR NOM via JNI (ex. SharedPreferencesApiRegistrar.getAll). Sans ces règles, R8 les supprime
# ou les renomme et l'app plante au démarrage en release (NoSuchMethodError), splash figé.
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Les signatures appelées par JNI contiennent des types Kotlin (fonctions suspend) : ne pas les renommer.
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.jvm.functions.** { *; }

# Pont JNI de Dart (déjà protégé par ses propres règles, rappelé par sécurité).
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
