#!/usr/bin/env bash
# Bootstrap a reproducible native iOS Runner for the existing Flutter app.
# Flutter/Xcode are required. No signing certificates or private keys here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../flutter_example" && pwd)"
cd "$APP_DIR"

IOS_BUNDLE_ID="$(printenv IOS_BUNDLE_ID || true)"
IOS_MIN_VERSION="$(printenv IOS_MIN_VERSION || true)"
if [[ -z "$IOS_BUNDLE_ID" ]]; then IOS_BUNDLE_ID="com.som13x.pidtunerpro"; fi
if [[ -z "$IOS_MIN_VERSION" ]]; then IOS_MIN_VERSION="14.0"; fi

if ! [[ "$IOS_BUNDLE_ID" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*){2,}$ ]]; then
  echo "Invalid IOS_BUNDLE_ID. Use a reverse-DNS identifier." >&2
  exit 2
fi
if ! [[ "$IOS_MIN_VERSION" =~ ^[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
  echo "Invalid IOS_MIN_VERSION (expected e.g. 14.0)" >&2
  exit 2
fi

if [[ ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo "Generating iOS native project using installed Flutter SDK..."
  flutter create --platforms=ios --org com.som13x \
    --project-name pid_tuner_pro_demo --no-pub .
fi

export IOS_BUNDLE_ID IOS_MIN_VERSION
python3 - <<'PY'
from pathlib import Path
import os
import plistlib
import re

app_dir = Path.cwd()
project = app_dir / "ios/Runner.xcodeproj/project.pbxproj"
info = app_dir / "ios/Runner/Info.plist"
if not (project.is_file() and info.is_file()):
    raise RuntimeError("Flutter iOS Runner generation failed")

raw = project.read_text()
ids = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);", raw)
if not ids:
    raise RuntimeError("Missing Xcode PRODUCT_BUNDLE_IDENTIFIER settings")

bundle_id = os.environ["IOS_BUNDLE_ID"]
minimum = os.environ["IOS_MIN_VERSION"]

def replace_id(match):
    original = match.group(1).strip()
    suffix = ".RunnerTests" if original.endswith(".RunnerTests") else ""
    return f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}{suffix};"

raw = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);",
             replace_id, raw)
raw, changed = re.subn(
    r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[^;]+;",
    f"IPHONEOS_DEPLOYMENT_TARGET = {minimum};", raw)
if changed == 0:
    raise RuntimeError("No deployment targets found in Xcode project")
project.write_text(raw)

with info.open("rb") as fp:
    plist = plistlib.load(fp)
plist["CFBundleDisplayName"] = "PID Tuner Pro"
plist["CFBundleName"] = "PID Tuner Pro"
with info.open("wb") as fp:
    plistlib.dump(plist, fp, sort_keys=False)

print(f"iOS ready: bundle ID {bundle_id}, minimum iOS {minimum}")
PY
