#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/tally-xcode.sh"

print_usage() {
    cat <<'USAGE'
Usage:
  scripts/build-run.sh [debug|prod|release] [--clean] [--restart] [--no-run]

Builds Tally for macOS and opens the built app.

Options:
  --clean      Clean before building.
  --restart    Quit a currently running Tally instance before opening the build.
  --no-run     Build only.
  -h, --help   Show this help.

USAGE
    usage_mode
}

mode="debug"
clean=0
restart=0
run_app=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        debug|prod|production|release|Debug|Release)
            mode="$1"
            ;;
        --clean)
            clean=1
            ;;
        --restart)
            restart=1
            ;;
        --no-run)
            run_app=0
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

mkdir -p "$(configuration_build_dir "${configuration}")"

if [[ "${clean}" -eq 1 ]]; then
    run_xcodebuild clean "${configuration}"
fi

run_xcodebuild build "${configuration}"

if [[ ! -d "${app_path}" ]]; then
    printf 'Build succeeded, but app was not found at: %s\n' "${app_path}" >&2
    exit 1
fi

printf 'Built %s app: %s\n' "${configuration}" "${app_path}"

if [[ "${run_app}" -eq 1 ]]; then
    if [[ "${restart}" -eq 1 ]]; then
        osascript -e 'tell application id "com.tommyliu.Tally" to quit' >/dev/null 2>&1 || true
        sleep 0.5
    fi

    open "${app_path}"
    printf 'Opened %s\n' "${app_path}"
fi

