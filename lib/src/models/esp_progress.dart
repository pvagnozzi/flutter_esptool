// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// High-level flashing progress stages.
enum EspProgressStage {
  connecting,
  syncing,
  detectingChip,
  loadingStub,
  erasing,
  writing,
  reading,
  verifying,
  done,
}

/// Reports progress for a long-running ESP operation.
class EspProgress {
  /// Creates an [EspProgress].
  const EspProgress({
    required this.stage,
    required this.current,
    required this.total,
    required this.message,
  });

  /// The current operation stage.
  final EspProgressStage stage;

  /// The number of completed bytes.
  final int current;

  /// The total byte count.
  final int total;

  /// The progress message.
  final String message;

  /// The normalized completion fraction.
  double get fraction => total > 0 ? current / total : 0.0;
}
