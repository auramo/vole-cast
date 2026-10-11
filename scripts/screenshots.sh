#!/bin/bash
#
# Captures the App Store screenshots, in English and Finnish, at the size App
# Store Connect has a slot for. Images land in
# screenshots/<language>/<pixel size>/ — the folder name is the slot.
#
# The library comes from iCloud rather than from sample data, so each simulator
# used here has to be signed into the Apple Account whose shows should appear.
# Settings > Sign in to your iPhone, inside the simulator.
#
# The taps are in VoleCastUITests/ScreenshotTests.swift.

set -euo pipefail
cd "$(dirname "$0")/.."

# App Store Connect asks for exactly one iPhone size, and it is the 6.3" one:
# the slot is called "iPhone with Dynamic Island (medium display)" and takes
# 1206x2622. That is a plain Pro. A Pro Max renders 1320x2868 and is rejected
# as invalid dimensions, so the device here is not interchangeable.
DEVICES=("${@:-}")
if [ -z "${DEVICES[*]}" ]; then
	DEVICES=("iPhone 18 Pro")
fi
OUT="$PWD/screenshots"

rm -rf "$OUT"
mkdir -p "$OUT"

destinations=()
for name in "${DEVICES[@]}"; do
	udid=$(xcrun simctl list devices available | grep -F "    $name (" | head -1 |
		sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
	if [ -z "$udid" ]; then
		echo "No available simulator named \"$name\"." >&2
		echo "Add one in Xcode > Window > Devices and Simulators, or pass names as arguments." >&2
		exit 1
	fi
	xcrun simctl boot "$udid" 2>/dev/null || true
	xcrun simctl bootstatus "$udid" >/dev/null
	# Apple's own marketing status bar: 9:41, full everything.
	xcrun simctl status_bar "$udid" override --time 9:41 \
		--dataNetwork wifi --wifiMode active --wifiBars 3 \
		--cellularMode active --cellularBars 4 \
		--batteryState charged --batteryLevel 100
	destinations+=(-destination "id=$udid")
done

# A TEST_RUNNER_-prefixed variable reaches the test process without the prefix.
TEST_RUNNER_VOLECAST_SCREENSHOT_DIR="$OUT" xcodebuild test \
	-project VoleCast.xcodeproj -scheme VoleCastUITests \
	"${destinations[@]}" -quiet

echo
echo "Screenshots, by the slot they belong in:"
find "$OUT" -name '*.png' | sort | while read -r png; do
	size=$(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixel/ { printf "%s%s", sep, $2; sep="x" }')
	echo "  ${png#"$OUT"/}  ($size)"
done
