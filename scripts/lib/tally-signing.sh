#!/usr/bin/env bash

require_signing_identity() {
    local identity="$1"
    if security find-identity -v -p codesigning 2>/dev/null \
        | grep -Fq -- "\"${identity}\""
    then
        return
    fi

    cat >&2 <<ERROR
error: code signing identity '${identity}' was not found.
Create a self-signed Code Signing certificate with that name in Keychain Access.
ERROR
    exit 1
}
