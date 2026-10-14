#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen from its official release or Homebrew, then rerun.' >&2; exit 1; }
xcodegen generate --spec project.yml
