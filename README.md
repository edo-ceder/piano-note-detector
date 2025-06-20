# 🎹 Piano Note Detector

A macOS app that listens to system audio and displays detected musical notes in real-time using ScreenCaptureKit and advanced FFT analysis.

![App Screenshot](screenshot.png)

## Features

- **Real-time Note Detection**: Detects musical notes from system audio output
- **Visual Display**: Shows detected notes with color coding and frequency information
- **System Audio Capture**: Uses ScreenCaptureKit for high-quality audio capture
- **Tuning Indicator**: Shows how close notes are to perfect pitch (in cents)
- **Sensitivity Control**: Adjustable threshold for note detection
- **Multiple Note Support**: Displays primary and secondary notes simultaneously

## Requirements

- macOS 12.3 or later (required for ScreenCaptureKit)
- Xcode 15.0 or later
- Screen Recording permission (will be requested on first run)

## Setup Instructions

1. **Open the Project**:
   ```bash
   open PianoNoteDetector.xcodeproj
   ```

2. **Build and Run**:
   - Select "PianoNoteDetector" scheme
   - Press ⌘+R to build and run
   - Grant Screen Recording permission when prompted

3. **System Settings**:
   - If permission is denied, go to System Settings > Privacy & Security > Screen Recording
   - Enable permission for "Piano Note Detector"

## How It Works

### Audio Capture
- Uses **ScreenCaptureKit** to capture system audio output
- Processes audio at 44.1kHz sample rate with stereo channels
- Excludes the app's own audio to prevent feedback

### Signal Processing
- Performs **4096-point FFT** analysis with Hann windowing
- Uses Apple's **Accelerate** framework for optimized DSP operations
- Detects frequency peaks in the musical range (80Hz - 2000Hz)

### Note Detection
- Converts frequencies to MIDI note numbers using 12-tone equal temperament
- Calculates pitch accuracy in cents (+/- 50 cents tolerance)
- Provides stability filtering to reduce noise and flickering

### User Interface
- **Dark themed** SwiftUI interface optimized for visibility
- **Color-coded notes** for easy visual identification
- **Real-time updates** with smooth animations
- **Tuning feedback** with sharp/flat indicators

## Technical Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ ScreenCaptureKit│ -> │  AudioProcessor │ -> │  NoteDetector   │
│   (Audio Input) │    │   (FFT Analysis)│    │ (Note Filtering)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       v
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ContentView   │ <- │AudioCaptureManager│ <- │  Note Display   │
│   (SwiftUI UI)  │    │  (Permissions)  │    │  (Visual Output)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Key Components

### AudioCaptureManager
- Handles ScreenCaptureKit integration
- Manages permissions and system audio capture
- Coordinates between audio processing and UI

### AudioProcessor
- Performs real-time FFT analysis using Accelerate framework
- Implements peak detection algorithms
- Converts frequencies to musical notes

### NoteDetector
- Provides note stability filtering
- Manages primary/secondary note display
- Handles sensitivity adjustments

### ContentView
- SwiftUI-based user interface
- Real-time note visualization
- Control interface for app settings

## Customization

### Sensitivity Adjustment
The sensitivity slider controls the minimum magnitude threshold for note detection:
- **Lower values**: More sensitive, detects quieter notes
- **Higher values**: Less sensitive, only strong notes shown

### Note Colors
Notes are color-coded by pitch class:
- C: Red, C#: Orange, D: Yellow, D#: Green
- E: Mint, F: Cyan, F#: Blue, G: Indigo
- G#: Purple, A: Pink, A#: Brown, B: Gray

## Troubleshooting

### No Permission
- Check System Settings > Privacy & Security > Screen Recording
- Restart the app after granting permission

### No Notes Detected
- Ensure audio is playing through system speakers
- Try adjusting the sensitivity slider
- Check that system volume is audible

### Performance Issues
- Close other audio-intensive applications
- Check Activity Monitor for CPU usage
- Ensure you're running on macOS 12.3+

## Building from Source

1. Clone the repository
2. Open `PianoNoteDetector.xcodeproj` in Xcode
3. Ensure deployment target is set to macOS 12.3+
4. Build with ⌘+B or run with ⌘+R

## Frameworks Used

- **ScreenCaptureKit**: System audio capture
- **AVFoundation**: Audio format handling
- **Accelerate**: Optimized FFT processing
- **SwiftUI**: Modern user interface
- **Combine**: Reactive programming

## License

This project is provided as example code for educational purposes.

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

---

*Built with ♪ for music lovers and developers* 