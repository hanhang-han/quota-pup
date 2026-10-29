#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
mkdir -p "$project_dir/.build/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir/Sources/QuotaClient.swift" "$project_dir/Tests/QuotaClientTests.swift" \
  -o "$project_dir/.build/QuotaClientTests"
"$project_dir/.build/QuotaClientTests" "$@"
