enum IntentType {
  playMusic,
  playArtist,
  pauseMusic,
  resumeMusic,
  nextTrack,
  previousTrack,
  volumeUp,
  volumeDown,
  volumeMute,
  volumeUnmute,
  volumeMax,
  setVolume,
  makeCall,
  openApp,
  batteryStatus,
  timeStatus,
  dateStatus,
  greeting,
  help,
  cancel,
  unknown,
}

class ParsedIntent {
  final IntentType type;
  final Map<String, String> slots;
  final String rawQuery;

  ParsedIntent({
    required this.type,
    this.slots = const {},
    required this.rawQuery,
  });

  String? get songOrArtist => slots['query'];
  String? get targetApp => slots['app'];
  String? get phoneNumber => slots['phone'];
  int? get volumePercent =>
      slots.containsKey('value') ? int.tryParse(slots['value']!) : null;
}
