#!/bin/sh
set -e

REPORT_DIR="/app/reports"
mkdir -p "$REPORT_DIR"

echo "========================================"
echo " flutter_esptool — Full Analysis Suite"
echo "========================================"

echo ""
echo ">>> 1/5 flutter analyze"
flutter analyze --no-pub 2>&1 | tee "$REPORT_DIR/analyze.txt"

echo ""
echo ">>> 2/5 flutter test --coverage"
flutter test --coverage 2>&1 | tee "$REPORT_DIR/test.txt"

echo ""
echo ">>> 3/5 coverage report"
if command -v genhtml >/dev/null 2>&1; then
  genhtml coverage/lcov.info \
    --output-directory "$REPORT_DIR/coverage" \
    --quiet
  echo "Coverage HTML → $REPORT_DIR/coverage/index.html"
fi

echo ""
echo ">>> 4/5 pana score"
dart run pana --no-warning --json . 2>/dev/null \
  | tee "$REPORT_DIR/pana.json" || true

echo ""
echo ">>> 5/5 semgrep"
semgrep scan --config=auto lib/ test/ \
  --json --output "$REPORT_DIR/semgrep.json" \
  --quiet 2>&1 || true

echo ""
echo "✅ Analysis complete. Reports in $REPORT_DIR/"
