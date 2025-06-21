#!/bin/bash

echo "🎵 Generating test tones for Piano Note Detector..."
echo "Make sure your PianoNoteDetector app is running and has started audio capture!"
echo ""

# Generate some spoken audio first (lower frequency content)
echo "🗣️  Generating speech (1 second)..."
say "Testing piano note detection" &
sleep 2

# Generate pure tone using sox if available, otherwise use system beep
if command -v sox &> /dev/null; then
    echo "🎼 Generating A4 (440 Hz) tone with sox..."
    sox -n -t coreaudio -d synth 3 sine 440 vol 0.5 &
    sleep 4
    
    echo "🎼 Generating C4 (261.63 Hz) tone with sox..."
    sox -n -t coreaudio -d synth 3 sine 261.63 vol 0.5 &
    sleep 4
else
    echo "🔔 Sox not available, using system beeps..."
    # Generate different frequency beeps
    for i in {1..5}; do
        afplay /System/Library/Sounds/Ping.aiff &
        sleep 1
    done
fi

echo "✅ Test tone generation complete!" 