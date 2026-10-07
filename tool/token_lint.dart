// Design token drift lint (2026-08-31) — the design review's own root-cause finding was
// that hand-syncing tokens.css and pavio_colors.dart is how the ink-500 WCAG fix went
// missing on mobile for weeks (see project memory / the design review doc). Nothing
// caught that at review time. This script is the closest thing this repo can have to
// owner-dashboard's html-token-validator.py without a shared token toolchain: it doesn't
// verify the two files agree (that would need a real cross-language schema), but it does
// stop the more common, more silent failure mode — a screen reaching for a raw literal
// instead of a token at all, which `flutter analyze` has no opinion on.
//
// Checks every lib/**.dart file outside lib/theme/ (which legitimately defines the raw
// values) for:
//   1. BorderRadius.circular(<number>) / Radius.circular(<number>) — should reference
//      PavioRadius.*
//   2. .copyWith(... fontSize: <number> ...) — should reach for a sized PavioText.*
//      style (body/bodySmall/badge/caption/label/...) instead of hand-tuning one
//   3. Color(0x........) — should reference PavioColors.*
//
// Run: dart run tool/token_lint.dart
// Wired into .github/workflows/ci.yml, right after `flutter analyze`.

import 'dart:io';

final _radiusLiteral = RegExp(r'(?:BorderRadius|Radius)\.circular\(\s*[0-9]');
final _fontSizeLiteral = RegExp(r'\.copyWith\([^)]*fontSize:\s*[0-9]');
final _colorLiteral = RegExp(r'\bColor\(0x[0-9A-Fa-f]{6,8}\)');

class Violation {
  Violation(this.file, this.line, this.lineNumber, this.reason);
  final String file;
  final String line;
  final int lineNumber;
  final String reason;
}

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('token_lint: no lib/ directory found — run from the tenant-app package root.');
    exitCode = 2;
    return;
  }

  final violations = <Violation>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Forward slashes even on Windows CI runners, since these are literal path prefixes.
    final relativePath = entity.path.replaceAll('\\', '/');
    if (relativePath.startsWith('lib/theme/')) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_radiusLiteral.hasMatch(line)) {
        violations.add(Violation(relativePath, line, i + 1, 'hardcoded radius — use PavioRadius.*'));
      }
      if (_fontSizeLiteral.hasMatch(line)) {
        violations.add(Violation(relativePath, line, i + 1, 'hardcoded fontSize — use a sized PavioText.* style'));
      }
      if (_colorLiteral.hasMatch(line)) {
        violations.add(Violation(relativePath, line, i + 1, 'hardcoded color literal — use PavioColors.*'));
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('token_lint: no hardcoded radius/fontSize/color literals found outside lib/theme/.');
    return;
  }

  stdout.writeln('token_lint: ${violations.length} token drift violation(s) found:\n');
  for (final v in violations) {
    stdout.writeln('  ${v.file}:${v.lineNumber} — ${v.reason}');
    stdout.writeln('    ${v.line.trim()}');
  }
  exitCode = 1;
}
