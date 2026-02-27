#!/bin/bash
# Run pod install with UTF-8 encoding to avoid CocoaPods errors on macOS
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
cd "$(dirname "$0")"
pod install --repo-update
