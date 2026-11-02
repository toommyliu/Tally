#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/tally-xcode.sh"
source "${SCRIPT_DIR}/lib/tally-signing.sh"

# TCC reuses the installed app's Reminders grant only with the same stable signature.
require_signing_identity "Local Code Signing"

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/tally-native.XXXXXX")"
output_name="tally-native-self-test-$(uuidgen).json"
output_path="${HOME}/Library/Containers/com.app.tally/Data/tmp/${output_name}"

# The self-signed app cannot load Xcode's debug dylib because their Team IDs differ.
if ! xcodebuild build \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -derivedDataPath "${run_dir}/DerivedData" \
    CODE_SIGN_IDENTITY="Local Code Signing" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    ENABLE_DEBUG_DYLIB=NO > "${run_dir}/build.log" 2>&1
then
    cat "${run_dir}/build.log" >&2
    exit 1
fi

open -n -W "${run_dir}/DerivedData/Build/Products/Debug/Tally.app" \
    --args --native-self-test "${output_name}"

if [[ ! -f "${output_path}" ]]; then
    printf 'error: native self-test produced no result at %s\nBuild log: %s\n' \
        "${output_path}" "${run_dir}/build.log" >&2
    exit 1
fi

cat "${output_path}"
printf '\n'
printf 'Result: %s\n' "${output_path}" >&2
[[ "$(plutil -extract pass raw -o - "${output_path}")" == true ]]
