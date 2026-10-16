FROM ubuntu:24.04

LABEL maintainer="edmingle@gmail.com"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    wget \
    unzip \
    zip \
    xz-utils \
    ca-certificates \
    build-essential \
    libglu1-mesa \
    libstdc++6 \
    openjdk-17-jdk \
    python3 \
    ruby-full \
    && rm -rf /var/lib/apt/lists/*

# Android SDK
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

ARG CMDLINE_TOOLS=13114758

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
    cd /tmp && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip && \
    unzip -q commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip && \
    mkdir -p ${ANDROID_HOME}/cmdline-tools/latest && \
    mv cmdline-tools/* ${ANDROID_HOME}/cmdline-tools/latest/ && \
    rm -rf /tmp/cmdline-tools /tmp/*.zip

RUN yes | ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --licenses

RUN ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager \
    "platform-tools" \
    "platforms;android-36" \
    "build-tools;36.0.0" \
    "cmake;3.22.1" \
    "ndk;29.0.14206865" && \
    rm -rf ${ANDROID_HOME}/cmdline-tools/latest/temp

# Verify SDK packages are present in the image before runtime builds.
RUN ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager --list_installed && \
    ls -la ${ANDROID_HOME}/platforms && \
    ls -la ${ANDROID_HOME}/build-tools && \
    ls -la ${ANDROID_HOME}/ndk

# Flutter
ENV FLUTTER_HOME=/opt/flutter
ENV PATH=$PATH:$FLUTTER_HOME/bin

ARG FLUTTER_VERSION=3.44.1

RUN cd /opt && \
    wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz && \
    tar -xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz && \
    rm -f flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
    
RUN git config --system --add safe.directory /opt/flutter

# Install OnePub CLI
RUN dart pub global activate onepub
ENV PATH="${PATH}:/root/.pub-cache/bin"

# Fastlane
RUN gem install bundler fastlane

# ---- Pre-warm Gradle/Maven/Pub dependency caches (bakes into image) ----
# All portals share the same dependency graph (only branding differs,
# applied later at build time by replace_config.py), so one warm cache
# here serves every portal build without re-downloading dependencies.
#
# IMPORTANT: this repo does not contain the Flutter app source itself.
# The reference app is supplied via a separate named build context,
# passed at `docker build` time like:
#   docker build --build-context reference-app=/path/to/some/portal/app -t flutter-builder .
# This requires Docker 23+ with BuildKit. Do NOT change this to a plain
# `COPY app/ ...` — there is no app/ directory in this repo's own
# build context, and that would break every image build.
COPY --from=reference-app . /tmp/warm/app/

RUN echo "[prewarm] Checking declared ndkVersion in reference app:" && \
    grep -r "ndkVersion" /tmp/warm/app/android || \
    echo "[prewarm] No explicit ndkVersion declaration found (may use AGP default)."

# The appbundle build is expected to fail because image build time has no
# portal signing key, matching google-services.json, or branded assets.
# It still warms Gradle/Maven, the wrapper, Kotlin, AAPT2, and R8/D8 caches.
# android/.gradle is only the project-local incremental cache; removing it
# keeps the shared downloaded dependency cache under /root/.gradle intact.
# If a portal later adds unique dependencies, only those new artifacts must
# be downloaded; all common dependencies remain available from this layer.
# NOTE: both `flutter pub get` and `flutter build appbundle` below are
# individually wrapped in `(... || echo "...")` rather than relying on a
# single trailing `|| true` for the whole chain. This is deliberate:
# `flutter pub get` can fail if the reference app depends on privately-hosted
# OnePub packages, since OnePub authentication normally happens at CONTAINER
# RUNTIME (via prepare.sh using $ONEPUB_TOKEN), not at `docker build` time.
# Without individual wrapping, a pub-get failure here would fail the ENTIRE
# image build. With individual wrapping, public dependencies (the majority of
# the download weight: Firebase, ExoPlayer, Compose, Play Services, etc.)
# still get cached even if a private package can't resolve at build time.
RUN cd /tmp/warm/app && \
    (flutter pub get || \
      echo "[prewarm] flutter pub get failed or partially failed — continuing, public deps may still be cached") && \
    { \
      echo "org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=768m -XX:+UseSerialGC"; \
      echo "org.gradle.parallel=false"; \
      echo "org.gradle.workers.max=1"; \
      echo "org.gradle.daemon=false"; \
      echo "org.gradle.configuration-cache=false"; \
      echo "kotlin.compiler.execution.strategy=in-process"; \
    } >> android/gradle.properties && \
    (flutter build appbundle --release --dart-define=ENV=DEMO || \
      echo "[prewarm] flutter build appbundle failed as expected" \
        "(no real signing/branding at image-build time) — dependency cache should still be warmed") && \
    rm -rf build .dart_tool/flutter_build android/app/build android/.gradle && \
    cd / && rm -rf /tmp/warm

RUN find /root/.gradle/wrapper/dists -name "*.zip" -delete

# Sanity check: fail the image build loudly if the pre-warm produced an
# essentially empty cache, since that likely means the reference-app build
# context was wrong/empty or `flutter pub get` failed entirely (not just
# partially). A non-trivial Flutter/Android project should resolve at least
# a few dozen dependency artifacts.
RUN CACHE_COUNT=$(find /root/.gradle/caches/modules-2 -type f 2>/dev/null | wc -l) && \
    echo "[prewarm] Cached dependency file count: ${CACHE_COUNT}" && \
    if [ "${CACHE_COUNT}" -lt 20 ]; then \
      echo \
        "[prewarm] ERROR: dependency cache looks empty or nearly empty (${CACHE_COUNT} files)."; \
      echo "[prewarm] This likely means the --build-context reference-app path was wrong,"; \
      echo "[prewarm] empty, or 'flutter pub get' failed entirely rather than partially."; \
      echo "[prewarm] Check the log output above this step for the actual failure."; \
      exit 1; \
    fi

COPY fastlane/ /opt/fastlane/


# Builder Scripts
COPY scripts/ /opt/builder/scripts/

RUN chmod +x /opt/builder/scripts/*.sh

RUN ln -s /opt/builder/scripts/build.sh /usr/local/bin/build.sh

WORKDIR /app

CMD ["bash"]