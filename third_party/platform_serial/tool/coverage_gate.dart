import 'dart:io';

/// Fails when an LCOV file is missing or below the configured line coverage.
///
/// Usage:
///   dart run tool/coverage_gate.dart --lcov coverage/lcov.info --min-lines 100
void main(List<String> args) {
  final lcovPath = _value(args, '--lcov') ?? 'coverage/lcov.info';
  final minLines = double.parse(_value(args, '--min-lines') ?? '100');
  final file = File(lcovPath);

  if (!file.existsSync()) {
    stderr.writeln('❌ Coverage file not found: $lcovPath');
    exitCode = 2;
    return;
  }

  var foundLines = 0;
  var hitLines = 0;

  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      foundLines += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hitLines += int.parse(line.substring(3));
    }
  }

  final coverage = foundLines == 0 ? 100.0 : hitLines * 100 / foundLines;
  stdout.writeln(
    '📊 Line coverage: ${coverage.toStringAsFixed(2)}% ($hitLines/$foundLines)',
  );

  if (coverage + 0.000001 < minLines) {
    stderr.writeln(
      '❌ Coverage is below required threshold: ${minLines.toStringAsFixed(2)}%',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln('✅ Coverage gate passed');
}

String? _value(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return args[index + 1];
}
