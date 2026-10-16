#!/usr/bin/env bash

set -e

WORKSPACE=${WORKSPACE:-/workspace}

ASSETS="$WORKSPACE/assets"

echo "========== Validating Build Workspace =========="

required_vars=(
    APP_NAME
    APP_BUNDLE_ID
    PORTAL_NAME
    WEB_DOMAIN
    APP_VERSION
    ONEPUB_TOKEN
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Missing environment variable: $var"
        exit 1
    fi
done

required_files=(
    "$ASSETS/key.properties"
    "$ASSETS/EdmingleKey.jks"
    "$ASSETS/google-services.json"
    "$ASSETS/logo.png"
    "$ASSETS/mobilertc"
)

for file in "${required_files[@]}"; do
    if [[ ! -e "$file" ]]; then
        echo "Missing required asset: $file"
        exit 1
    fi
done

echo "ONEPUB_TOKEN length: ${#ONEPUB_TOKEN}"
echo ""
echo "========== Build Configuration =========="
echo "APP_NAME       : $APP_NAME"
echo "APP_BUNDLE_ID  : $APP_BUNDLE_ID"
echo "PORTAL_NAME    : $PORTAL_NAME"
echo "WEB_DOMAIN     : $WEB_DOMAIN"
echo "APP_VERSION    : $APP_VERSION"
echo "WORKSPACE      : $WORKSPACE"
echo "========================================="
echo ""

echo "✓ Validation completed."