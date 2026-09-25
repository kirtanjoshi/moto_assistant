# MotoVoice (moto_assistant) 🏍️🎙️

**MotoVoice** is an offline, hands-free motorcycle voice assistant built with Flutter and Android native services. Designed specifically for riders wearing full-face helmets with Bluetooth intercoms (Sena, Cardo, FreedConn, etc.), it delivers reliable voice navigation, local audio playback, phone calls, and media controls without taking hands off the handlebars.

---

## 🌟 Key Features

### 1. 🎙️ Android On-Device Speech Recognition
- Powered by Android's high-accuracy, on-device neural speech services (`speech_to_text`).
- Accurate transcription across diverse accents and noisy environments.
- **Zero-loop architecture**: Gentle standby mode that eliminates battery drain and microphone loop timeouts.

### 2. 🎵 Dynamic Music Playback & Exact Local Song Matching
- **Local Audio Storage Match**: Uses native Android `MediaStore.Audio.Media` query with Levenshtein fuzzy distance matching to find local MP3/audio files on the device.
- **Direct Playback**: Dispatches `Intent.ACTION_VIEW` with `audio/*` content URIs to trigger exact song playback.
- **Dynamic 3rd-Party Player Integration**: Configurable via the in-app Settings screen:
  - **InShot MP3 Music Player** (`musicplayer.musicapps.music.mp3player`)
  - **Spotify** (`com.spotify.music`)
  - **YouTube Music** (`com.google.android.apps.youtube.music`)
  - **VLC Media Player** (`org.videolan.vlc`)
  - **Samsung Music** (`com.sec.android.app.music`)

### 3. 🏍️ High-Contrast OLED Rider Dashboard HUD
- Pure black (`#0B0E14`) OLED theme optimized for direct sunlight visibility and battery savings.
- Central glowing voice wave visualizer with live speech feedback.
- Glove-friendly 2x2 quick action cards:
  - ⏭️ **Next Track**
  - ⏸️ **Pause / Play**
  - 🔊 **Volume Up**
  - 🕒 **Time & Battery Status**

### 4. 📞 Hands-Free Calling & Intercom Audio Routing
- Dispatches hands-free telephony intents (`android.intent.action.CALL`).
- Manages Bluetooth SCO routing (`AudioManager.startBluetoothSco`) for crystal-clear helmet microphone audio.

---

## 🗣️ Voice Commands Reference

| Category | Example Utterance | Action |
| :--- | :--- | :--- |
| **Music Playback** | *"play people in music player"* / *"people in music player"* | Fuzzy searches local storage for "People" and launches InShot MP3 Player |
| **Streaming** | *"play believer on spotify"* | Launches Spotify search for "believer" |
| **Track Control** | *"next"* / *"skip"* | Sends next media key event |
| **Track Control** | *"previous"* / *"back"* | Sends previous media key event |
| **Playback State** | *"pause"* / *"stop music"* | Pauses audio |
| **Playback State** | *"resume"* / *"continue"* | Resumes audio |
| **Volume Control** | *"volume up"* / *"increase volume"* | Increments system media volume |
| **Volume Control** | *"volume down"* / *"quieter"* | Decrements system media volume |
| **Volume Control** | *"max volume"* / *"full volume"* | Sets system volume to 100% |
| **Phone Calls** | *"call daddy"* / *"call 98XXXXXXXX"* | Dispatches direct phone call |
| **System Info** | *"what time is it"* / *"battery"* | Speaks current time and battery level |

---

## 🛠️ Architecture

```
moto_assistant/
├── android/app/src/main/kotlin/.../MainActivity.kt  # Native MediaStore query, fuzzy matching, intent dispatch, SCO
├── android/app/src/main/AndroidManifest.xml         # Audio, storage, phone call, BT, and speech queries
├── lib/
│   ├── core/constants/                              # Design system tokens (OLED black, neon cyan, high-contrast)
│   ├── models/                                      # ParsedIntent, IntentType
│   ├── services/
│   │   ├── speech_service.dart                      # Android Speech-To-Text wrapper with standby & wake management
│   │   ├── intent_parser_service.dart               # Regex & phonetic normalization command parser
│   │   ├── media_intent_service.dart                # MethodChannel bridge for music & phone commands
│   │   ├── intercom_audio_service.dart              # Bluetooth SCO and volume management
│   │   ├── tts_feedback_service.dart                # Spoken audio confirmation
│   │   └── settings_service.dart                    # Persistent music player preferences
│   ├── ui/
│   │   ├── dashboard_screen.dart                    # Main rider HUD screen
│   │   ├── settings_screen.dart                     # Dynamic music player selector
│   │   └── widgets/                                 # VoiceWaveVisualizer, QuickActionCard, RiderGlanceCard
│   └── main.dart
└── test/
    ├── intent_parser_test.dart                      # Parser unit tests
    └── widget_test.dart                             # Widget & intent test suite
```

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK**: 3.x+
- **Android SDK**: API 31+ (Target SDK: 34)
- **Permissions**: Microphone, Audio/Media Storage, Phone, Bluetooth

### Installation & Run
```bash
# Clone the repository
git clone https://github.com/kirtanjoshi/moto_assistant.git
cd moto_assistant

# Fetch dependencies
flutter pub get

# Run tests
flutter test

# Run on connected Android device
flutter run
```

---

## 📄 License
MIT License. Built for riders everywhere. 🏍️💨
