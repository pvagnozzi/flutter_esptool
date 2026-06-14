// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
enum TerminalEntryType {
  incoming,
  outgoing,
  system,
  error,
}

class TerminalEntry {
  const TerminalEntry({
    required this.type,
    required this.message,
    required this.timestamp,
  });

  final TerminalEntryType type;
  final String message;
  final DateTime timestamp;
}
