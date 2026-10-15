#!/usr/bin/env bash
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT="${SWIFT:-swift}"
SWIFTC="${SWIFTC:-swiftc}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bible-app-state.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export CLANG_MODULE_CACHE_PATH="$WORK/clang-modules"
export SWIFT_MODULE_CACHE_PATH="$WORK/swift-modules"
"$SWIFT" build --package-path "$IOS" --scratch-path "$WORK/build" --jobs 2 --cache-path "$WORK/cache" --config-path "$WORK/config" --security-path "$WORK/security"
BIN="$("$SWIFT" build --package-path "$IOS" --show-bin-path --scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config" --security-path "$WORK/security")"
# Only replace observation imports. The three app-model implementations are unchanged.
python3 - "$IOS/Sources/App/AppStore.swift" "$WORK/AppStore.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
assert source.count('import SwiftUI') == 1
pathlib.Path(sys.argv[2]).write_text(source.replace('import SwiftUI', 'import Foundation', 1))
for name in ['QuestionModel.swift', 'ComparisonModel.swift']:
    source = pathlib.Path(sys.argv[1]).with_name(name).read_text()
    assert source.count('import SwiftUI') == 1
    pathlib.Path(sys.argv[2]).with_name(name).write_text(source.replace('import SwiftUI', 'import Foundation', 1))
PY
"$SWIFTC" -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -I "$BIN/Modules" -module-cache-path "$WORK/swift-modules" -clang-scanner-module-cache-path "$WORK/clang-modules" \
  "$BIN"/CompanionCore.build/*.swift.o \
  "$WORK/AppStore.swift" "$WORK/QuestionModel.swift" "$WORK/ComparisonModel.swift" "$IOS/Scripts/StateHarness/Boundaries.swift" "$IOS/Scripts/StateHarness/Run.swift" "$IOS/Scripts/StateHarness/DailyUse.swift" \
  -o "$WORK/check-app-state"
PACKAGE_RESOURCE_BUNDLE_PATH="$BIN" "$WORK/check-app-state" "$IOS/Tests/Fixtures"
