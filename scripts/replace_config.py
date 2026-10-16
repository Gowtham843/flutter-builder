from pathlib import Path
import re
import os
import json

workspace = Path(os.environ.get("WORKSPACE", "/workspace"))


def load_config():
    """
    Resolve build config values with the following priority:
      1. Environment variables (APP_BUNDLE_ID, APP_NAME, PORTAL_NAME,
         WEB_DOMAIN, APP_VERSION) — these are what validate.sh already
         requires and prints, so they're treated as the primary source
         of truth passed in via `docker run -e ...`.
      2. workspace/config/build_config.json — used as a fallback ONLY
         for any keys not supplied via environment variables. This keeps
         backward compatibility for workspaces that still rely on the
         JSON file, without requiring it to exist when env vars are
         already provided (which is now the common case).

    Raises a clear, actionable error if a required value is missing from
    BOTH sources, instead of an unhandled FileNotFoundError/KeyError.
    """
    json_config = {}
    config_path = workspace / "config" / "build_config.json"
    if config_path.exists():
        json_config = json.loads(config_path.read_text())
        print(f"[replace_config] Loaded fallback config from {config_path}")
    else:
        print(f"[replace_config] No {config_path} found — relying entirely on environment variables")

    def resolve(env_key, json_key):
        value = os.environ.get(env_key)
        if value:
            return value
        value = json_config.get(json_key)
        if value:
            return value
        raise SystemExit(
            f"[replace_config] ERROR: '{env_key}' is not set as an environment "
            f"variable, and '{json_key}' is not present in {config_path}. "
            f"Provide one of the two before running this script."
        )

    return {
        "app_bundle_id": resolve("APP_BUNDLE_ID", "app_bundle_id"),
        "app_name": resolve("APP_NAME", "app_name"),
        "portal_name": resolve("PORTAL_NAME", "portal_name"),
        "web_domain": resolve("WEB_DOMAIN", "web_domain"),
        "app_version": resolve("APP_VERSION", "app_version"),
    }


config = load_config()

APP_BUNDLE_ID = config["app_bundle_id"]
APP_NAME = config["app_name"]
PORTAL_NAME = config["portal_name"]
WEB_DOMAIN = config["web_domain"]
APP_VERSION = config["app_version"]

root = workspace / "app"

print(f"[replace_config] APP_BUNDLE_ID={APP_BUNDLE_ID}")
print(f"[replace_config] APP_NAME={APP_NAME}")
print(f"[replace_config] PORTAL_NAME={PORTAL_NAME}")
print(f"[replace_config] WEB_DOMAIN={WEB_DOMAIN}")
print(f"[replace_config] APP_VERSION={APP_VERSION}")
print(f"[replace_config] root={root}")


def apply_replacements(txt: str) -> str:
    txt = txt.replace("com.edmingle.app", APP_BUNDLE_ID)
    txt = txt.replace("Edmingle Demo", APP_NAME)
    txt = txt.replace("enterpriseplanportal.edmingle.com", WEB_DOMAIN)
    txt = txt.replace("__BUILD_PORTAL_NAME__", PORTAL_NAME)
    return txt


TEXT_SUFFIXES = {
    ".kt",
    ".java",
    ".xml",
    ".gradle",
    ".kts",
    ".dart",
    ".properties",
    ".json",
    ".plist",
    ".swift",
    ".pbxproj",
    ".entitlements",
    ".xcconfig",
    ".m",
    ".mm",
    ".yaml",
    ".yml",
}


def should_skip(path):
    # IMPORTANT: check the path RELATIVE TO `root`, not the full absolute
    # path. The container's temp workspace is hardcoded to /tmp/build in
    # build.sh (TEMP_WORKSPACE=/tmp/build), so the ABSOLUTE path of every
    # single file contains a literal "build" segment
    # (e.g. /tmp/build/app/android/app/build.gradle.kts) — which previously
    # matched this skip-list unconditionally and silently skipped EVERY
    # file in the project, regardless of whether it was an actual Flutter/
    # Gradle build-output directory or not. Using the path relative to
    # `root` (workspace/app) ensures only genuine output dirs like
    # app/build/... or app/.dart_tool/... are skipped.
    try:
        rel_parts = path.relative_to(root).parts
    except ValueError:
        rel_parts = path.parts
    return any(
        part in {"build", ".dart_tool", "Pods"}
        for part in rel_parts
    )


pubspec = root / "pubspec.yaml"

content = pubspec.read_text()

content = re.sub(
    r"^version:.*$",
    f"version: {APP_VERSION}",
    content,
    flags=re.MULTILINE,
)

content = apply_replacements(content)

pubspec.write_text(content)

for folder in ("android", "lib", "ios", "test"):

    directory = root / folder

    if not directory.exists():
        continue

    for file in directory.rglob("*"):

        if not file.is_file():
            continue

        if should_skip(file):
            continue

        if file.suffix.lower() not in TEXT_SUFFIXES:
            continue

        text = file.read_text(errors="ignore")

        updated = apply_replacements(text)

        if updated != text:
            file.write_text(updated)
            print(f"[replace_config] Updated: {file.relative_to(root)}")

print("Replacement completed.")