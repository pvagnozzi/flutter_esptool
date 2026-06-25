#!/bin/sh
set -e

flutter test --coverage

genhtml coverage/lcov.info \
  --output-directory coverage/html \
  --title "flutter_esptool coverage"

echo "Report: coverage/html/index.html"
