#!/bin/bash
# Screen-records the scripted feature walkthrough (integration_test/demo_test.dart)
# on an iOS simulator.  Usage: tool/record_demo.sh [simulator-udid] [out.mp4]
set -u
cd "$(dirname "$0")/.."

DEVICE="${1:-B53EC8D2-4CB9-4A31-B0A4-99DFB8F81AD9}"
OUT="${2:-build/demo/clear_roads_demo.mp4}"
mkdir -p "$(dirname "$OUT")"
RAW="${OUT%.mp4}.raw.mp4"
rm -f "$RAW" "$OUT"

xcrun simctl boot "$DEVICE" 2>/dev/null
open -a Simulator 2>/dev/null || open "$(xcode-select -p)/Applications/Simulator.app"
xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork 5g \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

PIDFILE="$(mktemp)"
stop_recording() {
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null)"
  [ -n "$pid" ] || return 0
  kill -INT "$pid" 2>/dev/null
  # Wait for simctl to finish writing the file.
  while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
  : > "$PIDFILE"
}
# Stop the recorder even if the walkthrough fails part-way.
trap 'stop_recording; rm -f "$PIDFILE"' EXIT
flutter test integration_test/demo_test.dart -d "$DEVICE" 2>&1 | while IFS= read -r line; do
  echo "$line"
  case "$line" in
    *DEMO_START*)
      # Background jobs in scripts ignore SIGINT, which simctl needs to
      # finish the file, so restore it before exec.
      python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
        xcrun simctl io "$DEVICE" recordVideo --codec=h264 --force "$RAW" >/dev/null 2>&1 &
      echo $! > "$PIDFILE"
      ;;
    *DEMO_END*)
      stop_recording
      ;;
  esac
done
# Walkthrough failed before DEMO_END: still save what was recorded.
stop_recording

xcrun simctl status_bar "$DEVICE" clear
[ -f "$RAW" ] || { echo "No recording was made." >&2; exit 1; }
# Re-encode for broad compatibility (QuickTime, Slack, email, WhatsApp).
if ffmpeg -y -loglevel error -i "$RAW" -vf "scale=-2:1920,fps=30" -c:v h264_videotoolbox \
  -b:v 3M -pix_fmt yuv420p -movflags +faststart "$OUT"; then
  rm -f "$RAW"
else
  mv "$RAW" "$OUT"
fi
echo "Saved $OUT"
