#!/usr/bin/env python3

import math
import wave
import struct
import os
import subprocess

def generate_sine_wave(frequency, duration, sample_rate=44100, amplitude=0.3):
    """Generate a sine wave and save it as a WAV file."""
    
    # Calculate number of samples
    num_samples = int(sample_rate * duration)
    
    # Generate sine wave samples
    samples = []
    for i in range(num_samples):
        # Calculate the sine wave value
        t = i / sample_rate
        sample = amplitude * math.sin(2 * math.pi * frequency * t)
        # Convert to 16-bit integer
        sample_int = int(sample * 32767)
        samples.append(sample_int)
    
    # Save as WAV file
    filename = f"tone_{frequency}hz.wav"
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(sample_rate)
        
        # Write samples
        for sample in samples:
            wav_file.writeframes(struct.pack('<h', sample))
    
    return filename

def play_tone(frequency, duration=3):
    """Generate and play a tone."""
    print(f"🎵 Generating {frequency}Hz tone for {duration} seconds...")
    
    # Generate the WAV file
    filename = generate_sine_wave(frequency, duration)
    
    print(f"🔊 Playing {filename}...")
    
    # Play the file using afplay (macOS built-in)
    try:
        subprocess.run(['afplay', filename], check=True)
        print(f"✅ Finished playing {frequency}Hz tone")
    except subprocess.CalledProcessError as e:
        print(f"❌ Error playing file: {e}")
    finally:
        # Clean up the temporary file
        if os.path.exists(filename):
            os.remove(filename)

if __name__ == "__main__":
    print("🎹 Piano Note Tone Generator")
    print("Generating musical tones for testing...")
    
    # Generate some common piano notes
    notes = [
        (440, "A4"),      # A above middle C
        (261.63, "C4"),   # Middle C
        (329.63, "E4"),   # E above middle C
        (523.25, "C5"),   # C one octave above middle C
    ]
    
    for freq, note_name in notes:
        print(f"\n🎼 Playing {note_name} ({freq}Hz)")
        play_tone(freq, 2)  # 2 seconds each
        
    print("\n🎉 All tones generated and played!") 