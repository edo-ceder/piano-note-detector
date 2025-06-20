#!/usr/bin/env python3
import numpy as np
import wave
import struct

# Generate test tones for common notes
notes = {
    'A4': 440.0,
    'C4': 261.63,
    'E4': 329.63,
    'G4': 392.00,
    'C5': 523.25
}

for note_name, freq in notes.items():
    duration = 3.0  # 3 seconds
    sample_rate = 44100
    t = np.linspace(0, duration, int(sample_rate * duration), False)
    # Generate sine wave
    audio = np.sin(2 * np.pi * freq * t) * 0.5
    
    # Save as WAV file
    with wave.open(f'{note_name}_test.wav', 'w') as wav_file:
        wav_file.setnchannels(1)  # mono
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(sample_rate)
        # Convert to 16-bit integers
        audio_int = (audio * 32767).astype(np.int16)
        wav_file.writeframes(audio_int.tobytes())

print('Generated test audio files:')
for note in notes.keys():
    print(f'  {note}_test.wav ({notes[note]} Hz)') 