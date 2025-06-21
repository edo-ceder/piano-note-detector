#!/usr/bin/env python3

import subprocess
import time
import signal
import sys

def signal_handler(sig, frame):
    print('\n🛑 Stopping tone generator...')
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)

def play_tone_loop(frequency, note_name):
    print(f"🎵 Playing {note_name} ({frequency}Hz) in continuous loop...")
    print("Press Ctrl+C to stop")
    
    while True:
        try:
            # Play the tone file
            subprocess.run(['afplay', f'{note_name}_test.wav'], check=True)
            time.sleep(0.1)  # Small gap between loops
        except subprocess.CalledProcessError as e:
            print(f"❌ Error playing file: {e}")
            break
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    print("🎹 Continuous Tone Generator for Pitch Detection Testing")
    
    # Play A4 (440 Hz) in a loop
    play_tone_loop(440, "A4") 