# Правила R8 для release-сборки SyncM.
# Flutter Gradle plugin подхватывает этот файл автоматически, если он существует,
# и добавляет его после proguard-android-optimize.txt и flutter_proguard_rules.pro.

# spotify-app-remote AAR подключён голым файлом, без транзитивных зависимостей
# (см. android/spotify-app-remote/build.gradle). Его опциональный Jackson-маппер
# ссылается на jackson-databind, которого в release-classpath нет: SDK работает
# через GsonMapper, а jackson добавлен только в debugImplementation, чтобы ART
# не сыпал "Unable to resolve ... annotation class" при десериализации PlayerState.
# Классы com.spotify.protocol.mappers.jackson.* в runtime не загружаются,
# поэтому R8 достаточно перестать предупреждать о них.
-dontwarn com.fasterxml.jackson.databind.deser.std.StdDeserializer
-dontwarn com.fasterxml.jackson.databind.ser.std.StdSerializer

# Аннотация уровня compile-time, в runtime не нужна.
-dontwarn com.spotify.base.annotations.NotNull
