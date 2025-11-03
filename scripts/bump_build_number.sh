#!/bin/bash
# Auto-increment build number on each build
# Add this as a "Run Script" build phase in Xcode

# Increment build number
buildNumber=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${INFOPLIST_FILE}")
buildNumber=$((buildNumber + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "${INFOPLIST_FILE}"

echo "Build number incremented to: $buildNumber"
