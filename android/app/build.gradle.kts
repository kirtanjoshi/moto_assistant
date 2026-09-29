import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Sherpa-ONNX (Apache-2.0) is not on Maven Central: the AAR and keyword-spotting models are downloaded
// once from its GitHub releases into android/.sherpa (gitignored), pinned by SHA-256.
val sherpaCache = rootProject.file(".sherpa")
val sherpaAssets = layout.buildDirectory.dir("generated/sherpa-assets").get().asFile

fun sha256(f: File) = MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }

fun fetch(url: String, sha: String): File {
    val f = File(sherpaCache, url.substringAfterLast('/'))
    if (f.exists() && sha256(f) == sha) return f
    f.parentFile.mkdirs()
    logger.lifecycle("Downloading $url")
    URI(url).toURL().openStream().use { input -> f.outputStream().use { input.copyTo(it) } }
    check(sha256(f) == sha) { "SHA-256 mismatch for $url" }
    return f
}

// Copies only the int8 model files the app loads, renamed to stable names under assets/kws/<key>/.
fun extractKwsModel(key: String, dir: String, sha: String, files: Map<String, String>) {
    val out = File(sherpaAssets, "kws/$key")
    if (files.values.all { File(out, it).exists() }) return
    val tar = fetch("https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/$dir.tar.bz2", sha)
    copy {
        from(tarTree(resources.bzip2(tar)))
        include(files.keys.map { "$dir/$it" })
        eachFile { path = files.getValue(name) }
        includeEmptyDirs = false
        into(out)
    }
}

extractKwsModel(
    "giga", "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01",
    "f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a",
    mapOf(
        "encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx" to "encoder.onnx",
        "decoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx" to "decoder.onnx",
        "joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx" to "joiner.onnx",
        "tokens.txt" to "tokens.txt",
    ),
)
extractKwsModel(
    "phone", "sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20",
    "68447f4fbc67e70eee3a93961f36e81e98f47aef73ce7e7ca00885c6cd3616a6",
    mapOf(
        "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx" to "encoder.onnx",
        "decoder-epoch-13-avg-2-chunk-16-left-64.onnx" to "decoder.onnx", // no int8 decoder published
        "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx" to "joiner.onnx",
        "tokens.txt" to "tokens.txt",
    ),
)
val sherpaAar = fetch(
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-static-link-onnxruntime-1.13.8.aar",
    "b22c3fc1b6a45666d28892bb2f7694beeb77a8362d7ebd77c1a5431ec9435471",
)

android {
    namespace = "com.motovoice.moto_assistant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.motovoice.moto_assistant"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ARM phones only: the static Sherpa AAR ships a separate libonnxruntime.so for x86 that would
        // clash with openWakeWord's runtime.
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }

    sourceSets.getByName("main").assets.srcDir(sherpaAssets)
    // Native-lib merging runs before abiFilters; the x86 copies are never packaged, so either one will do.
    packaging { jniLibs { pickFirsts += listOf("lib/x86/libonnxruntime.so", "lib/x86_64/libonnxruntime.so") } }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.github.msnilsen:openwakeword-android:0.1.2")
    implementation(files(sherpaAar))
}
