# ============================================================
# Stage 1 — base: Dart SDK + Flutter + analysis tools
# ============================================================
FROM dart:3.4-sdk AS base

# System packages: git, curl, python3, pip, lcov
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      curl \
      unzip \
      xz-utils \
      python3 \
      python3-pip \
      lcov \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter (stable channel) via git
RUN git clone --depth 1 \
      --branch stable \
      https://github.com/flutter/flutter.git \
      /flutter

# Set PATH for Flutter and Dart pub-cache binaries
ENV PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:\
/root/.pub-cache/bin:${PATH}"

# Pre-warm Flutter and accept SDK licences
RUN flutter precache --no-android --no-ios --no-web \
    && flutter --version

# Install global Dart/Flutter tools
RUN dart pub global activate pana \
    && dart pub global activate dart_code_metrics \
    && dart pub global activate coverage

# Install semgrep via pip
RUN pip3 install --no-cache-dir semgrep --break-system-packages \
    || pip3 install --no-cache-dir semgrep

WORKDIR /app

# ============================================================
# Stage 2 — analysis: copy project and pre-fetch dependencies
# ============================================================
FROM base AS analysis

# Copy dependency manifests first (layer-cache friendly)
COPY pubspec.yaml pubspec.lock* ./

RUN flutter pub get

# Copy the rest of the project
COPY . .

# Default command: run the full analysis suite
CMD ["sh", "docker/scripts/full-analysis.sh"]
