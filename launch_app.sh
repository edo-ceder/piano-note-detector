#!/bin/bash

echo "🚀 Launching PianoNoteDetector..."

# Kill any existing instances
pkill -9 PianoNoteDetector 2>/dev/null

# Find the app bundle in Build/Products/Debug
APP_PATH=$(find /Users/test/Library/Developer/Xcode/DerivedData/PianoNoteDetector-*/Build/Products/Debug -name "PianoNoteDetector.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Error: PianoNoteDetector.app not found. Please build the app first."
    exit 1
fi

echo "📦 Found app at: $APP_PATH"

# Launch the app properly using 'open'
open "$APP_PATH"

echo "✅ App launched! Look for the PianoNoteDetector window."
echo ""
echo "📋 To see logs, run:"
echo "   log stream --predicate 'process == \"PianoNoteDetector\"' --level info" 