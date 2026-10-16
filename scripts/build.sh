#!/usr/bin/env bash

set -e

ORIGINAL_WORKSPACE=${WORKSPACE:-/workspace}
TEMP_WORKSPACE=/tmp/build
OUTPUT_DIR="${ORIGINAL_WORKSPACE}/output"
APP="$TEMP_WORKSPACE/app"
ANDROID="$APP/android"

BUILD_START=$(date +%s)
STAGE_START=$BUILD_START

log_duration() {
  local label="$1"
  local now
  now=$(date +%s)
  local elapsed=$((now - STAGE_START))
  printf '⏱  %s: %ds\n' "$label" "$elapsed"
  STAGE_START=$now
}

verify_android_project() {
  echo "========== Verifying Android Project Structure =========="

  local missing=0

  for path in "$ANDROID/app" "$ANDROID/mobilertc"; do
    if [[ ! -d "$path" ]]; then
      echo "ERROR: Missing required directory: $path"
      missing=1
    fi
  done

  if [[ ! -f "$ANDROID/settings.gradle" && ! -f "$ANDROID/settings.gradle.kts" ]]; then
    echo "ERROR: Missing settings.gradle or settings.gradle.kts in $ANDROID"
    missing=1
  fi

  if [[ ! -f "$ANDROID/build.gradle" && ! -f "$ANDROID/build.gradle.kts" ]]; then
    echo "ERROR: Missing build.gradle or build.gradle.kts in $ANDROID"
    missing=1
  fi

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi

  echo "✓ Android project structure verified."
}

print_toolchain_info() {
  echo "========== Toolchain Versions =========="
  java -version
  flutter --version
  dart --version
  echo ""
  echo "========== Installed Android SDK Packages =========="
  sdkmanager --list_installed
  echo ""
  echo "========== Required NDK Version =========="
  grep -R "ndkVersion" "$ANDROID" || echo "No ndkVersion declaration found."
  echo "========================================="
}

echo "Starting Flutter Builder..."
echo "Original Workspace : ${ORIGINAL_WORKSPACE}"
echo "Temporary Workspace: ${TEMP_WORKSPACE}"

echo "PWD=$(pwd)"
echo "ORIGINAL_WORKSPACE=$ORIGINAL_WORKSPACE"
echo "TEMP_WORKSPACE=$TEMP_WORKSPACE"

echo "Before copy:"
ls -la "$ORIGINAL_WORKSPACE"
find "$ORIGINAL_WORKSPACE" -maxdepth 2

echo "Copying workspace..."
rm -rf "$TEMP_WORKSPACE"
echo "DEBUG: after rm -rf TEMP_WORKSPACE"
ls -la "$TEMP_WORKSPACE" 2>&1 || true
mkdir -p "$TEMP_WORKSPACE"
echo "DEBUG: after mkdir TEMP_WORKSPACE"
ls -la "$TEMP_WORKSPACE"
cp -a "${ORIGINAL_WORKSPACE}/." "$TEMP_WORKSPACE/"
echo "DEBUG: cp exit code=$?"
echo "Workspace copied successfully."

echo "After copy:"
ls -la "$TEMP_WORKSPACE"
find "$TEMP_WORKSPACE" -maxdepth 2

if [[ ! -d "$TEMP_WORKSPACE/app" ]]; then
  echo "Workspace copy verification failed: ${TEMP_WORKSPACE}/app not found."
  echo "Contents of ${TEMP_WORKSPACE}:"
  ls -la "$TEMP_WORKSPACE" || true
  exit 1
fi

export WORKSPACE="$TEMP_WORKSPACE"
echo "DEBUG: after export WORKSPACE=$WORKSPACE"
echo "DEBUG: TEMP_WORKSPACE still=$TEMP_WORKSPACE"
ls -la "$TEMP_WORKSPACE"
log_duration "Workspace Copy"

echo "Building from ${WORKSPACE}/app"

/opt/builder/scripts/validate.sh
log_duration "Validate"

/opt/builder/scripts/prepare.sh
log_duration "Prepare"

verify_android_project

mkdir -p "$WORKSPACE/app/android/fastlane"
cp -R /opt/fastlane/* "$WORKSPACE/app/android/fastlane/"

print_toolchain_info

cd "$WORKSPACE/app/android"

# Temporarily disable set -e so we can capture Fastlane's exit code.
# DEBUG_ON_FAILURE=true (default) keeps the container alive on failure for
# docker exec debugging. Set DEBUG_ON_FAILURE=false to exit with the build
# status (for non-interactive CI).
DEBUG_ON_FAILURE=${DEBUG_ON_FAILURE:-true}

set +e
FASTLANE_START=$(date +%s)
fastlane build
BUILD_STATUS=$?
FASTLANE_END=$(date +%s)
set -e

printf '⏱  Fastlane Build (flutter clean, pub get, intl, appbundle): %ds\n' "$((FASTLANE_END - FASTLANE_START))"
STAGE_START=$FASTLANE_END

if [[ $BUILD_STATUS -ne 0 ]]; then
  echo ""
  echo "======================================"
  echo "Flutter build failed (exit code: ${BUILD_STATUS})."
  echo "DEBUG_ON_FAILURE=${DEBUG_ON_FAILURE}"
  echo "======================================"

  mkdir -p "$OUTPUT_DIR"

  # Collect useful diagnostics for inspection on the host mount.
  if [[ -d "$WORKSPACE/app/build/reports" ]]; then
    cp -R "$WORKSPACE/app/build/reports" "$OUTPUT_DIR/" || true
    echo "Copied: build/reports"
  fi

  if [[ -d "$WORKSPACE/app/android/.gradle" ]]; then
    cp -R "$WORKSPACE/app/android/.gradle" "$OUTPUT_DIR/gradle-debug" || true
    echo "Copied: android/.gradle -> gradle-debug"
  fi

  REPORT="$WORKSPACE/app/android/fastlane/report.xml"
  if [[ -f "$REPORT" ]]; then
    cp -f "$REPORT" "$OUTPUT_DIR/" || true
    echo "Copied: fastlane/report.xml"
  fi

  LOGCAT_DIR="$WORKSPACE/app/build"
  if [[ -d "$LOGCAT_DIR" ]]; then
    find "$LOGCAT_DIR" -name "*.log" -type f 2>/dev/null | head -50 | while read -r logfile; do
      rel="${logfile#$WORKSPACE/app/}"
      mkdir -p "$OUTPUT_DIR/logs/$(dirname "$rel")"
      cp -f "$logfile" "$OUTPUT_DIR/logs/$rel" || true
    done
  fi

  if [[ "$DEBUG_ON_FAILURE" == "true" ]]; then
    echo ""
    echo "======================================"
    echo "Container will remain running for debugging."
    echo "Use:"
    echo "  docker exec -it <container_name> bash"
    echo ""
    echo "Useful paths:"
    echo "  $WORKSPACE"
    echo "  /root/.gradle"
    echo "  /root/.pub-cache"
    echo "  $WORKSPACE/app/build"
    echo "  $WORKSPACE/app/android/.gradle"
    echo "======================================"
    # Keep container alive for interactive debugging (CI / local).
    # Disable later with DEBUG_ON_FAILURE=false.
    sleep infinity
  fi

  # Debugging disabled: preserve the original Fastlane exit code.
  exit "$BUILD_STATUS"
fi

echo "Copying artifacts back to ${OUTPUT_DIR}"
mkdir -p "$OUTPUT_DIR"

AAB_SRC="$WORKSPACE/app/build/app/outputs/bundle/demoRelease/app-demo-release.aab"
if [[ -f "$AAB_SRC" ]]; then
  cp -f "$AAB_SRC" "$OUTPUT_DIR/"
  echo "Copied: app-demo-release.aab"
else
  echo "WARNING: AAB not found at $AAB_SRC"
fi

BUNDLE_DIR="$WORKSPACE/app/build/app/outputs/bundle/demoRelease"
if [[ -d "$BUNDLE_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR/bundle"
  cp -a "$BUNDLE_DIR/." "$OUTPUT_DIR/bundle/"
fi

MAPPING="$WORKSPACE/app/build/app/outputs/mapping/demoRelease/mapping.txt"
if [[ -f "$MAPPING" ]]; then
  cp -f "$MAPPING" "$OUTPUT_DIR/mapping.txt"
  echo "Copied: mapping.txt"
fi

REPORT="$WORKSPACE/app/android/fastlane/report.xml"
if [[ -f "$REPORT" ]]; then
  cp -f "$REPORT" "$OUTPUT_DIR/"
  echo "Copied: fastlane/report.xml"
fi

log_duration "Artifact Copy"

# --- Cleanup (success path only) ---
# We only reach this point when BUILD_STATUS was 0 (see the early-exit
# block above for failures, which intentionally preserves the workspace
# for docker exec debugging when DEBUG_ON_FAILURE=true).
#
# Remove per-build output directories but KEEP /root/.gradle, since that
# is the shared Maven/Gradle dependency cache (pre-warmed into the Docker
# image) — deleting it would force re-downloading dependencies on the
# next build. Only $TEMP_WORKSPACE (source + build outputs, which are
# portal-specific and already copied to $OUTPUT_DIR) is safe to remove.
echo "Cleaning up temporary workspace..."
rm -rf "$TEMP_WORKSPACE"
echo "✓ Cleaned: $TEMP_WORKSPACE"

BUILD_END=$(date +%s)
printf '⏱  Total Build Time: %ds\n' "$((BUILD_END - BUILD_START))"
echo "Build completed."
exit 0
