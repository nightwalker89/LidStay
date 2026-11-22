#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
TARGET_ARCH="$(uname -m)"
EXPECT_UNIVERSAL=0
ZIP_PATH=""
DMG_PATH=""
REQUIRE_LIVE_LAUNCH=0
SELF_TEST_TIMEOUT=30

usage() {
    cat <<'EOF'
Usage: scripts/verify_runtime.sh [options] [path/to/LidStay.app]

Options:
  --app <path>              Path to LidStay.app bundle
  --arch <x86_64|arm64>     Target architecture to verify (default: host uname -m)
  --expect-universal        Assert binary contains both x86_64 and arm64 slices
  --zip <path>              Also verify unzipping and codesign of a release .zip archive
  --dmg <path>              Also verify mounting and codesign of a release .dmg image
  --require-live-launch     Fail instead of skipping live launch if another LidStay instance is running
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP_PATH="${2:?Missing value for --app}"
            shift 2
            ;;
        --arch)
            TARGET_ARCH="${2:?Missing value for --arch}"
            shift 2
            ;;
        --expect-universal)
            EXPECT_UNIVERSAL=1
            shift
            ;;
        --zip)
            ZIP_PATH="${2:?Missing value for --zip}"
            shift 2
            ;;
        --dmg)
            DMG_PATH="${2:?Missing value for --dmg}"
            shift 2
            ;;
        --require-live-launch)
            REQUIRE_LIVE_LAUNCH=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$APP_PATH" ]]; then
                APP_PATH="$1"
                shift
            else
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 1
            fi
            ;;
    esac
done

if [[ "$TARGET_ARCH" != "x86_64" && "$TARGET_ARCH" != "arm64" ]]; then
    echo "Unsupported --arch: ${TARGET_ARCH} (expected x86_64 or arm64)" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d)"
MOUNT_POINT=""
LIVE_PID=""

cleanup() {
    if [[ -n "$LIVE_PID" ]] && kill -0 "$LIVE_PID" 2>/dev/null; then
        kill -TERM "$LIVE_PID" 2>/dev/null || true
        sleep 1
        kill -KILL "$LIVE_PID" 2>/dev/null || true
    fi
    if [[ -n "$MOUNT_POINT" ]] && [[ -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() {
    echo "[verify-runtime] $*"
}

fail() {
    echo "[verify-runtime] ERROR: $*" >&2
    exit 1
}

run_with_timeout() {
    local timeout_sec="$1"
    shift

    "$@" &
    local cmd_pid=$!
    local elapsed=0

    while kill -0 "$cmd_pid" 2>/dev/null; do
        if (( elapsed >= timeout_sec * 10 )); then
            kill -TERM "$cmd_pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$cmd_pid" 2>/dev/null || true
            wait "$cmd_pid" 2>/dev/null || true
            return 124
        fi
        sleep 0.1
        elapsed=$((elapsed + 1))
    done

    wait "$cmd_pid"
}

check_new_crash_reports() {
    local marker_file="$1"
    local found_crashes=()
    local dir
    for dir in "$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r report; do
                [[ -n "$report" ]] && found_crashes+=("$report")
            done < <(find "$dir" -maxdepth 2 -type f \( -name "*LidStay*.ips" -o -name "*LidStay*.crash" \) -newer "$marker_file" 2>/dev/null || true)
        fi
    done

    if (( ${#found_crashes[@]} > 0 )); then
        for report in "${found_crashes[@]}"; do
            echo "=== CRASH REPORT: ${report} ===" >&2
            head -n 120 "$report" >&2 || true
        done
        fail "Detected ${#found_crashes[@]} LidStay crash report(s)!"
    fi
}

log "Host arch: $(uname -m), Target arch: ${TARGET_ARCH}"
log "macOS version: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"

if [[ -n "$ZIP_PATH" ]]; then
    [[ -f "$ZIP_PATH" ]] || fail "Zip file not found: $ZIP_PATH"
    ZIP_EXTRACT_DIR="${WORK_DIR}/zip-extract"
    mkdir -p "$ZIP_EXTRACT_DIR"
    log "Unpacking zip archive: ${ZIP_PATH}"
    ditto -x -k "$ZIP_PATH" "$ZIP_EXTRACT_DIR"
    [[ -d "${ZIP_EXTRACT_DIR}/LidStay.app" ]] || fail "LidStay.app missing inside ${ZIP_PATH}"
    codesign --verify --deep --strict --verbose=2 "${ZIP_EXTRACT_DIR}/LidStay.app"
    if [[ -z "$APP_PATH" ]]; then
        APP_PATH="${ZIP_EXTRACT_DIR}/LidStay.app"
    fi
fi

if [[ -n "$DMG_PATH" ]]; then
    [[ -f "$DMG_PATH" ]] || fail "DMG file not found: $DMG_PATH"
    MOUNT_POINT="${WORK_DIR}/dmg-mount"
    mkdir -p "$MOUNT_POINT"
    log "Mounting DMG image: ${DMG_PATH}"
    hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" >/dev/null
    [[ -d "${MOUNT_POINT}/LidStay.app" ]] || fail "LidStay.app missing inside ${DMG_PATH}"
    [[ -L "${MOUNT_POINT}/Applications" ]] || fail "Applications symlink missing inside ${DMG_PATH}"
    codesign --verify --deep --strict --verbose=2 "${MOUNT_POINT}/LidStay.app"
    if [[ -z "$APP_PATH" ]]; then
        cp -R "${MOUNT_POINT}/LidStay.app" "${WORK_DIR}/LidStay-from-dmg.app"
        APP_PATH="${WORK_DIR}/LidStay-from-dmg.app"
    fi
    hdiutil detach "$MOUNT_POINT" >/dev/null
    MOUNT_POINT=""
fi

[[ -n "$APP_PATH" ]] || fail "No app bundle provided (pass LidStay.app, --zip, or --dmg)"
[[ -d "$APP_PATH" ]] || fail "App bundle does not exist: ${APP_PATH}"

BIN_PATH="${APP_PATH}/Contents/MacOS/LidStay"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"
[[ -x "$BIN_PATH" ]] || fail "Executable not found or not executable: ${BIN_PATH}"
[[ -f "$PLIST_PATH" ]] || fail "Info.plist not found: ${PLIST_PATH}"

# 1. Architecture & Mach-O checks
ARCHS="$(lipo -archs "$BIN_PATH")"
log "Binary architectures: ${ARCHS}"
[[ "$ARCHS" == *"$TARGET_ARCH"* ]] || fail "Target arch ${TARGET_ARCH} missing from ${BIN_PATH} (found: ${ARCHS})"
if [[ "$EXPECT_UNIVERSAL" = "1" ]]; then
    [[ "$ARCHS" == *"arm64"* && "$ARCHS" == *"x86_64"* ]] || fail "Expected universal binary (arm64 + x86_64), got: ${ARCHS}"
fi

# 2. Code signature verification
log "Verifying code signature for ${TARGET_ARCH}..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=2 --arch="$TARGET_ARCH" "$APP_PATH" 2>&1

# 3. Minimum macOS deployment target check
EXPECTED_MINOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST_PATH")"
ACTUAL_MINOS="$(otool -arch "$TARGET_ARCH" -l "$BIN_PATH" | awk '/LC_BUILD_VERSION/{flag=1} flag && /minos/{print $2; exit}')"
log "Deployment target (${TARGET_ARCH}): minos=${ACTUAL_MINOS}, Info.plist LSMinimumSystemVersion=${EXPECTED_MINOS}"
[[ "$ACTUAL_MINOS" == "$EXPECTED_MINOS" ]] || fail "minos (${ACTUAL_MINOS}) does not match LSMinimumSystemVersion (${EXPECTED_MINOS})"

# 4. Linked libraries check (ensure only system libraries/frameworks are linked)
log "Checking dynamic library dependencies (${TARGET_ARCH})..."
BAD_DEPS="$(otool -arch "$TARGET_ARCH" -L "$BIN_PATH" | awk 'NR>1 && /^\t/ {print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' || true)"
if [[ -n "$BAD_DEPS" ]]; then
    fail "Found non-system dynamic library dependencies for ${TARGET_ARCH}:\n${BAD_DEPS}"
fi

# Marker file to detect any crash reports generated during runtime checks
CRASH_MARKER="${WORK_DIR}/crash-marker"
touch "$CRASH_MARKER"

# 5. In-app self-test execution under target architecture
SELF_TEST_LOG="${WORK_DIR}/selftest.log"

log "Running --self-test under arch -${TARGET_ARCH}..."
set +e
run_with_timeout "$SELF_TEST_TIMEOUT" arch -"$TARGET_ARCH" "$BIN_PATH" --self-test >"$SELF_TEST_LOG" 2>&1
SELF_TEST_RC=$?
set -e

cat "$SELF_TEST_LOG"
check_new_crash_reports "$CRASH_MARKER"

if [[ "$SELF_TEST_RC" -eq 124 ]]; then
    fail "--self-test timed out after ${SELF_TEST_TIMEOUT}s on ${TARGET_ARCH}"
elif [[ "$SELF_TEST_RC" -ne 0 ]]; then
    fail "--self-test exited with status ${SELF_TEST_RC} on ${TARGET_ARCH}"
fi

grep -q "\[SELF-TEST\] PASS arch=${TARGET_ARCH}" "$SELF_TEST_LOG" || fail "--self-test did not report PASS for arch=${TARGET_ARCH}"
log "--self-test PASSED on ${TARGET_ARCH}"

# 6. Normal live app launch, polling stability, single-instance lock, and clean shutdown
EXISTING_PIDS="$(pgrep -x LidStay 2>/dev/null || true)"
if [[ -n "$EXISTING_PIDS" ]]; then
    if [[ "$REQUIRE_LIVE_LAUNCH" = "1" ]]; then
        fail "Another LidStay process is already running (PIDs: ${EXISTING_PIDS}); cannot perform clean live launch check"
    else
        log "Skipping live launch check because another LidStay instance is already running locally (PIDs: ${EXISTING_PIDS})."
        log "All static + --self-test checks PASSED for ${TARGET_ARCH}!"
        exit 0
    fi
fi

LIVE_LOG="${WORK_DIR}/live.log"

log "Launching normal LidStay app under arch -${TARGET_ARCH}..."
arch -"$TARGET_ARCH" "$BIN_PATH" >"$LIVE_LOG" 2>&1 &
LIVE_PID=$!

sleep 4

if ! kill -0 "$LIVE_PID" 2>/dev/null; then
    set +e
    wait "$LIVE_PID"
    LIVE_RC=$?
    set -e
    LIVE_PID=""
    cat "$LIVE_LOG" >&2 || true
    check_new_crash_reports "$CRASH_MARKER"
    fail "LidStay exited prematurely during live launch (exit code: ${LIVE_RC})"
fi

LOCK_FILE="${HOME}/Library/Application Support/LidStay/instance.lock"
[[ -f "$LOCK_FILE" ]] || fail "Expected single-instance lock file was not created at ${LOCK_FILE}"
log "Live LidStay process is healthy (PID ${LIVE_PID}) and created instance.lock"

# Verify single-instance enforcement: second launch must exit 0 quickly without killing first instance
SECOND_LOG="${WORK_DIR}/second-instance.log"
log "Verifying single-instance guard with second launch under arch -${TARGET_ARCH}..."
set +e
run_with_timeout 10 arch -"$TARGET_ARCH" "$BIN_PATH" >"$SECOND_LOG" 2>&1
SECOND_RC=$?
set -e
if [[ "$SECOND_RC" -ne 0 ]]; then
    cat "$SECOND_LOG" >&2 || true
    fail "Second LidStay instance failed single-instance check (exit code: ${SECOND_RC})"
fi

kill -0 "$LIVE_PID" 2>/dev/null || fail "Primary LidStay instance died after second-instance launch!"
log "Single-instance guard PASSED"

# Clean shutdown via SIGTERM
log "Sending SIGTERM to PID ${LIVE_PID}..."
kill -TERM "$LIVE_PID"
STOP_ELAPSED=0
while kill -0 "$LIVE_PID" 2>/dev/null; do
    if (( STOP_ELAPSED >= 100 )); then
        fail "Primary LidStay instance did not exit within 10s after SIGTERM"
    fi
    sleep 0.1
    STOP_ELAPSED=$((STOP_ELAPSED + 1))
done
set +e
wait "$LIVE_PID"
TERM_RC=$?
set -e
LIVE_PID=""
log "Primary LidStay exited cleanly after SIGTERM (status: ${TERM_RC})"

if [[ -s "$LIVE_LOG" ]]; then
    log "Live app output:"
    cat "$LIVE_LOG"
fi

check_new_crash_reports "$CRASH_MARKER"
log "ALL RUNTIME VERIFICATION CHECKS PASSED for ${TARGET_ARCH}!"

