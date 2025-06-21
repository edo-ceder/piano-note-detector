#!/usr/bin/env python3

import subprocess
import sys
import time

def play_continuous_tone(frequency=440, duration=30):
    """Play a continuous tone using sox (if available) or afplay in a loop"""
    
    print(f"🎵 Playing continuous {frequency}Hz tone for {duration} seconds...")
    print("📢 Make sure your system volume is up and PianoNoteDetector is running!")
    
    try:
        # Try using sox to generate a continuous tone
        cmd = [
            'sox', '-n', '-t', 'coreaudio', 'default',
            'synth', str(duration), 'sine', str(frequency),
            'vol', '0.3'
        ]
        print(f"🔊 Running: {' '.join(cmd)}")
        subprocess.run(cmd, check=True)
        
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("⚠️ Sox not found, trying afplay loop...")
        # Fallback to afplay in a loop
        try:
            # Generate a longer tone file
            import numpy as np
            import wave
            
            sample_rate = 44100
            samples = int(sample_rate * 5)  # 5 second loop
            t = np.linspace(0, 5, samples, False)
            audio = np.sin(2 * np.pi * frequency * t) * 0.3
            
            filename = f"continuous_{frequency}hz.wav"
            with wave.open(filename, 'w') as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(sample_rate)
                audio_int = (audio * 32767).astype(np.int16)
                wav_file.writeframes(audio_int.tobytes())
            
            # Play in a loop
            loops = duration // 5
            for i in range(loops):
                print(f"🔄 Loop {i+1}/{loops}")
                subprocess.run(['afplay', filename], check=True)
                
        except Exception as e:
            print(f"❌ Error: {e}")
            print("💡 Try installing sox: brew install sox")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        freq = float(sys.argv[1])
    else:
        freq = 440  # Default A4
        
    print("🎹 Continuous Tone Generator")
    print(f"🎼 Frequency: {freq} Hz")
    print("⏹️  Press Ctrl+C to stop")
    
    try:
        play_continuous_tone(freq, 60)  # 60 seconds
    except KeyboardInterrupt:
        print("\n⏹️ Stopped by user") 