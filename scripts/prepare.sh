#!/usr/bin/env bash

set -e

WORKSPACE=${WORKSPACE:-/workspace}

APP="$WORKSPACE/app"
ASSETS="$WORKSPACE/assets"

set_gradle_property() {
  local key="$1"
  local value="$2"
  local file="$APP/android/gradle.properties"

  mkdir -p "$APP/android"
  touch "$file"

  # Replace existing key if present, otherwise append.
  # (Does not touch any other keys; avoids duplicate keys by editing in-place.)
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

verify_mobilertc() {
  local rtc_dir="$APP/android/mobilertc"

  echo "Verifying mobilertc module..."
  echo "Destination: $rtc_dir"

  if [[ ! -d "$rtc_dir" ]]; then
    echo "ERROR: mobilertc directory not found at $rtc_dir"
    exit 1
  fi
  echo "✓ mobilertc directory found"

  if [[ -f "$rtc_dir/build.gradle" ]]; then
    echo "✓ build.gradle found"
  elif [[ -f "$rtc_dir/build.gradle.kts" ]]; then
    echo "✓ build.gradle.kts found"
  else
    echo "ERROR: mobilertc is missing build.gradle or build.gradle.kts"
    exit 1
  fi

  if [[ ! -f "$rtc_dir/mobilertc.aar" ]]; then
    echo "ERROR: mobilertc is missing mobilertc.aar"
    exit 1
  fi
  echo "✓ mobilertc.aar found"
}

echo "========== Preparing Flutter Project =========="

cd "$APP"

echo "Authenticating with OnePub..."
onepub import
onepub pub add hugeicons

mkdir -p "$APP/assets/logos"

echo "Adding Portal Logo..."
cp "$ASSETS/logo.png" \
   "$APP/assets/logos/${PORTAL_NAME}-logo.png"

echo "Adding App Icon..."
cp "$ASSETS/logo.png" \
   "$APP/assets/logos/app-icon.png"

echo "Adding EdmingleKey.jks..."
cp "$ASSETS/EdmingleKey.jks" \
   "$APP/android/EdmingleKey.jks"

echo "Adding key.properties..."
cp "$ASSETS/key.properties" \
   "$APP/android/key.properties"
# Point storeFile at the JKS we just copied into android/
sed -i "s|^storeFile=.*|storeFile=${APP}/android/EdmingleKey.jks|" \
  "$APP/android/key.properties"

if [[ ! -d "$APP/android/mobilertc" ]]; then
  echo "Copying mobilertc..."
  echo "Destination: $APP/android/mobilertc"
  cp -R "$ASSETS/mobilertc" "$APP/android/mobilertc"
else
  echo "mobilertc already exists. Skipping copy."
  echo "Destination: $APP/android/mobilertc"
fi

verify_mobilertc

echo "========== Applying CI Gradle Configuration =========="
echo "Updating org.gradle.daemon"
set_gradle_property "org.gradle.daemon" "false"
# Memory tuning: cap Gradle's JVM heap explicitly and disable parallel
# workers so the build stays within the memory budget of smaller CI/dev
# machines (tested to work on a 16GB Mac via Docker Desktop). Using the
# serial GC (-XX:+UseSerialGC) trades some speed for a much smaller
# memory overhead than the default G1GC, which matters in constrained
# containers. kotlin.compiler.execution.strategy=in-process avoids
# spawning a second JVM for the Kotlin compiler daemon.
echo "Updating org.gradle.jvmargs"
set_gradle_property "org.gradle.jvmargs" "-Xmx3g -XX:MaxMetaspaceSize=768m -XX:+UseSerialGC"
echo "Updating org.gradle.parallel"
set_gradle_property "org.gradle.parallel" "false"
echo "Updating org.gradle.workers.max"
set_gradle_property "org.gradle.workers.max" "1"
echo "Updating kotlin.compiler.execution.strategy"
set_gradle_property "kotlin.compiler.execution.strategy" "in-process"
echo "Updating org.gradle.caching"
set_gradle_property "org.gradle.caching" "true"
# Flutter's Gradle plugin still calls Task.project at execution time, which
# breaks Gradle configuration cache. Keep it off until Flutter supports it.
echo "Updating org.gradle.configuration-cache"
set_gradle_property "org.gradle.configuration-cache" "false"
echo "Updating org.gradle.vfs.watch"
set_gradle_property "org.gradle.vfs.watch" "false"
echo "✓ Gradle configuration updated."

echo "Replacing google-services.json..."
cp -f "$ASSETS/google-services.json" \
      "$APP/android/app/google-services.json"

echo "Applying build configuration replacements..."
python3 /opt/builder/scripts/replace_config.py

echo "✓ Assets prepared successfully."
