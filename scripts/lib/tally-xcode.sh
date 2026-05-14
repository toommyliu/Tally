#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROJECT_PATH="${REPO_ROOT}/Tally.xcodeproj"
SCHEME="Tally"
APP_NAME="Tally"
DESTINATION="platform=macOS"
BUILD_ROOT="${REPO_ROOT}/build"

usage_mode() {
    cat <<'USAGE'
Mode:
  debug               Build with the Debug configuration.
  prod | production   Build with the Release configuration.
  release             Build with the Release configuration.
USAGE
}

resolve_configuration() {
    local mode="${1:-debug}"

    case "${mode}" in
        debug|Debug)
            printf '%s\n' "Debug"
            ;;
        prod|production|release|Release)
            printf '%s\n' "Release"
            ;;
        *)
            printf 'Unknown mode: %s\n\n' "${mode}" >&2
            usage_mode >&2
            return 64
            ;;
    esac
}

configuration_build_dir() {
    local configuration="$1"
    printf '%s\n' "${BUILD_ROOT}/${configuration}"
}

app_path_for_configuration() {
    local configuration="$1"
    printf '%s/%s.app\n' "$(configuration_build_dir "${configuration}")" "${APP_NAME}"
}

run_xcodebuild() {
    local action="$1"
    local configuration="$2"
    shift 2

    xcodebuild "${action}" \
        -project "${PROJECT_PATH}" \
        -scheme "${SCHEME}" \
        -configuration "${configuration}" \
        -destination "${DESTINATION}" \
        -derivedDataPath "${BUILD_ROOT}/DerivedData" \
        CONFIGURATION_BUILD_DIR="$(configuration_build_dir "${configuration}")" \
        "$@"
}

