#!/bin/bash

echo "🔨 Building PianoNoteDetector..."
xcodebuild -project PianoNoteDetector.xcodeproj -scheme PianoNoteDetector -configuration Debug build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Launching app..."
    # Use 'open' to properly launch the app bundle, not the executable directly
    open /Users/test/Library/Developer/Xcode/DerivedData/PianoNoteDetector-*/Build/Products/Debug/PianoNoteDetector.app
    echo "📱 App launched! Check the app window for audio capture."
    echo "📋 To see live logs, run: log stream --predicate 'processImagePath contains \"PianoNoteDetector\"'"
else
    echo "❌ Build failed!"
    exit 1
fi 