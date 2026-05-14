#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/tally-xcode.sh"

print_usage() {
    cat <<'USAGE'
Usage:
  scripts/artifact.sh [debug|prod|release] [--clean]

Builds Tally for macOS and creates a zipped .app artifact.
Artifacts are written to build/artifacts/.

Options:
  --clean      Clean before building.
  -h, --help   Show this help.

USAGE
    usage_mode
}

mode="prod"
clean=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        debug|prod|production|release|Debug|Release)
            mode="$1"
            ;;
        --clean)
            clean=1
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n\n' "$1" >&2
            print_usage >&2
            exit 64
            ;;
    esac
    shift
done

configuration="$(resolve_configuration "${mode}")"
app_path="$(app_path_for_configuration "${configuration}")"
artifact_dir="${BUILD_ROOT}/artifacts"
timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
artifact_path="${artifact_dir}/${APP_NAME}-${configuration}-${timestamp}.zip"

mkdir -p "$(configuration_build_dir "${configuration}")" "${artifact_dir}"

if [[ "${clean}" -eq 1 ]]; then
    run_xcodebuild clean "${configuration}"
fi

run_xcodebuild build "${configuration}"

if [[ ! -d "${app_path}" ]]; then
    printf 'Build succeeded, but app was not found at: %s\n' "${app_path}" >&2
    exit 1
fi

rm -f "${artifact_path}"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${artifact_path}"

printf 'Created artifact: %s\n' "${artifact_path}"

