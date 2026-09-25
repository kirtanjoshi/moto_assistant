enum AssistantStatus {
  idle,
  listeningWakeWord,
  listeningCommand,
  processing,
  speaking,
  error,
}

class AssistantState {
  final AssistantStatus status;
  final String statusText;
  final String lastRecognizedText;
  final String activeCommand;
  final bool isBluetoothScoConnected;

  const AssistantState({
    this.status = AssistantStatus.idle,
    this.statusText = 'Ready',
    this.lastRecognizedText = '',
    this.activeCommand = '',
    this.isBluetoothScoConnected = false,
  });

  AssistantState copyWith({
    AssistantStatus? status,
    String? statusText,
    String? lastRecognizedText,
    String? activeCommand,
    bool? isBluetoothScoConnected,
  }) {
    return AssistantState(
      status: status ?? this.status,
      statusText: statusText ?? this.statusText,
      lastRecognizedText: lastRecognizedText ?? this.lastRecognizedText,
      activeCommand: activeCommand ?? this.activeCommand,
      isBluetoothScoConnected: isBluetoothScoConnected ?? this.isBluetoothScoConnected,
    );
  }
}
