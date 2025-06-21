import SwiftUI

struct ContentView: View {
    @StateObject private var audioCapture = AudioCaptureManager()
    @StateObject private var noteDetector = NoteDetector()
    @State private var permissionCheckCount = 0
    @State private var showRestartInstructions = false
    @State private var hasRequestedPermissions = UserDefaults.standard.bool(forKey: "hasRequestedPermissions")
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🎹 Piano Note Detector")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Divider()
            
            // Permission Status
            PermissionStatusView(audioCapture: audioCapture, 
                               permissionCheckCount: $permissionCheckCount,
                               showRestartInstructions: $showRestartInstructions)
            
            Divider()
            
            // Control Buttons
            HStack(spacing: 20) {
                Button(action: {
                    audioCapture.startCapture()
                }) {
                    Label("Start", systemImage: "play.fill")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!audioCapture.hasPermission || audioCapture.isCapturing)
                
                Button(action: {
                    audioCapture.stopCapture()
                }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                .disabled(!audioCapture.isCapturing)
            }
            
            Divider()
            
            // Raw Audio Visualization
            VStack(alignment: .leading, spacing: 10) {
                Text("🎵 Raw Audio Signal")
                    .font(.headline)
                    .foregroundColor(.purple)
                
                HStack(spacing: 10) {
                    // Waveform display
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Audio Waveform")
                            .font(.caption)
                            .fontWeight(.semibold)
                        WaveformVisualizationView(noteDetector: noteDetector)
                            .frame(width: 280, height: 120)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                    // Spectrum display
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Frequency Spectrum")
                            .font(.caption)
                            .fontWeight(.semibold)
                        SpectrumVisualizationView(noteDetector: noteDetector)
                            .frame(width: 280, height: 120)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
            }
            
            Divider()
            
            // Raw Frequency Analysis Display
            VStack(alignment: .leading, spacing: 10) {
                Text("🔍 Raw Frequency Analysis")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                RawFrequencyAnalysisView(noteDetector: noteDetector)
                    .frame(height: 200)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(10)
            }
            
            Divider()
            
            // Pitch Visualization
            VStack(alignment: .leading, spacing: 10) {
                Text("Pitch Visualization")
                    .font(.headline)
                
                PitchVisualizationView(noteDetector: noteDetector)
                    .frame(height: 150)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10)
            }
            
            Divider()
            
            // Audio Level Meter
            VStack(alignment: .leading, spacing: 10) {
                Text("Audio Level")
                    .font(.headline)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 30)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(levelColor(for: noteDetector.audioLevel))
                            .frame(width: geometry.size.width * CGFloat(noteDetector.audioLevel), height: 30)
                            .animation(.linear(duration: 0.1), value: noteDetector.audioLevel)
                    }
                }
                .frame(height: 30)
                
                Text("Level: \(Int(noteDetector.audioLevel * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Detected Notes
            VStack(alignment: .leading, spacing: 10) {
                Text("Detected Notes")
                    .font(.headline)
                
                if let primaryNote = noteDetector.primaryNote {
                    VStack(alignment: .leading, spacing: 10) {
                        // Primary note
                        HStack {
                            Text(primaryNote.name)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(primaryNote.color)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(primaryNote.frequency)) Hz")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if abs(primaryNote.cents) > 5 {
                                    Text(primaryNote.cents > 0 ? "♯ +\(Int(primaryNote.cents)) cents" : "♭ \(Int(primaryNote.cents)) cents")
                                        .font(.caption2)
                                        .foregroundColor(abs(primaryNote.cents) > 20 ? .red : .orange)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(primaryNote.color.opacity(0.1))
                        .cornerRadius(10)
                        
                        // Secondary notes
                        if !noteDetector.secondaryNotes.isEmpty {
                            HStack(spacing: 10) {
                                Text("Also detected:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ForEach(noteDetector.secondaryNotes, id: \.name) { note in
                                    Text(note.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(note.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(note.color.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                } else {
                    Text("No notes detected")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 700, height: 1000) // Increased width and height to accommodate visualizations
        .onChange(of: audioCapture.hasPermission) { _, newValue in
            if newValue {
                permissionCheckCount = 0
                showRestartInstructions = false
            }
        }
        .onAppear {
            audioCapture.setNoteDetector(noteDetector)
            
            // On first launch, automatically request permissions
            if !hasRequestedPermissions && !audioCapture.hasPermission {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    audioCapture.requestPermissions()
                    UserDefaults.standard.set(true, forKey: "hasRequestedPermissions")
                    hasRequestedPermissions = true
                }
            } else {
                // Otherwise just check current permission status
                audioCapture.checkPermissions()
                
                // If we already have permissions, start capturing immediately
                if audioCapture.hasPermission && !audioCapture.isCapturing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("🚀 Auto-starting audio capture...")
                        audioCapture.startCapture()
                    }
                }
            }
        }
        .onChange(of: audioCapture.hasPermission) { _, newValue in
            if newValue {
                permissionCheckCount = 0
                showRestartInstructions = false
                
                // Auto-start capture when permissions are granted
                if !audioCapture.isCapturing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        print("🚀 Auto-starting audio capture after permission granted...")
                        audioCapture.startCapture()
                    }
                }
            }
        }
    }
    
    func levelColor(for level: Float) -> Color {
        switch level {
        case 0..<0.3:
            return .green
        case 0.3..<0.7:
            return .yellow
        default:
            return .red
        }
    }
}

struct PermissionStatusView: View {
    @ObservedObject var audioCapture: AudioCaptureManager
    @Binding var permissionCheckCount: Int
    @Binding var showRestartInstructions: Bool
    
    var body: some View {
        HStack {
            if audioCapture.isCheckingPermission {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Checking Permissions...")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Image(systemName: audioCapture.hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(audioCapture.hasPermission ? .green : .orange)
                
                Text(audioCapture.hasPermission ? "Screen Recording Permission Granted" : "Screen Recording Permission Required")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if !audioCapture.hasPermission {
                    // Permission required
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Open Settings") {
                                permissionCheckCount = 0
                                audioCapture.requestPermissions()
                            }
                            
                            Button("Refresh") {
                                permissionCheckCount += 1
                                audioCapture.checkPermissions()
                            }
                            
                            if showRestartInstructions {
                                Button("Quit App") {
                                    NSApp.terminate(nil)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        
        if showRestartInstructions || (!audioCapture.hasPermission && !audioCapture.isCheckingPermission) {
            VStack(alignment: .leading, spacing: 10) {
                Text("⚠️ App Restart Required")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("macOS requires a full app restart after granting Screen Recording permission.")
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("1. Click 'Open Settings' and enable Screen Recording for PianoNoteDetector")
                    Text("2. Click 'Quit App' below")
                    Text("3. Launch the app again from Finder or using the build script")
                }
                .font(.caption2)
                .padding(.vertical, 5)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct PitchVisualizationView: View {
    @ObservedObject var noteDetector: NoteDetector
    
    // Piano frequency range: A0 (27.5 Hz) to C8 (4186 Hz)
    // For visualization, we'll use a more practical range
    private let minFreq: Double = 80.0    // Low piano range
    private let maxFreq: Double = 2000.0  // High piano range
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with piano key reference lines
                BackgroundGridView(geometry: geometry)
                
                // Main pitch line
                if let primaryNote = noteDetector.primaryNote {
                    PitchLineView(
                        frequency: primaryNote.frequency,
                        color: primaryNote.color,
                        geometry: geometry,
                        minFreq: minFreq,
                        maxFreq: maxFreq,
                        opacity: 1.0
                    )
                    .animation(.easeInOut(duration: 0.2), value: primaryNote.frequency)
                }
                
                // Secondary pitch lines (fainter)
                ForEach(Array(noteDetector.secondaryNotes.enumerated()), id: \.element.name) { index, note in
                    PitchLineView(
                        frequency: note.frequency,
                        color: note.color,
                        geometry: geometry,
                        minFreq: minFreq,
                        maxFreq: maxFreq,
                        opacity: 0.4
                    )
                    .animation(.easeInOut(duration: 0.2), value: note.frequency)
                }
                
                // Frequency labels
                FrequencyLabelsView(geometry: geometry, minFreq: minFreq, maxFreq: maxFreq)
            }
        }
    }
}

struct BackgroundGridView: View {
    let geometry: GeometryProxy
    
    var body: some View {
        // Horizontal reference lines for major octaves
        ForEach([100, 200, 400, 800, 1600], id: \.self) { freq in
            let normalizedPosition = log(Double(freq) / 80.0) / log(2000.0 / 80.0)
            let yPosition = geometry.size.height * (1.0 - normalizedPosition)
            
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .offset(y: yPosition - geometry.size.height / 2)
        }
    }
}

struct PitchLineView: View {
    let frequency: Double
    let color: Color
    let geometry: GeometryProxy
    let minFreq: Double
    let maxFreq: Double
    let opacity: Double
    
    var body: some View {
        let normalizedPosition = normalizedFrequencyPosition(frequency)
        let yPosition = geometry.size.height * (1.0 - normalizedPosition)
        
        Rectangle()
            .fill(color.opacity(opacity))
            .frame(height: 3)
            .shadow(color: color.opacity(0.5), radius: 2)
            .offset(y: yPosition - geometry.size.height / 2)
            .overlay(
                // Frequency label on the line
                HStack {
                    Spacer()
                    Text("\(Int(frequency)) Hz")
                        .font(.caption2)
                        .foregroundColor(color)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(4)
                        .padding(.trailing, 8)
                }
                .offset(y: yPosition - geometry.size.height / 2)
            )
    }
    
    private func normalizedFrequencyPosition(_ freq: Double) -> Double {
        // Use logarithmic scale for frequency to match human pitch perception
        let clampedFreq = max(minFreq, min(maxFreq, freq))
        return log(clampedFreq / minFreq) / log(maxFreq / minFreq)
    }
}

struct FrequencyLabelsView: View {
    let geometry: GeometryProxy
    let minFreq: Double
    let maxFreq: Double
    
    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach([("2000 Hz", 2000.0), ("800 Hz", 800.0), ("400 Hz", 400.0), ("200 Hz", 200.0), ("100 Hz", 100.0)], id: \.0) { label, freq in
                        let normalizedPosition = log(freq / minFreq) / log(maxFreq / minFreq)
                        let yOffset = geometry.size.height * (1.0 - normalizedPosition)
                        
                        Text(label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .offset(y: yOffset - geometry.size.height / 2)
                    }
                }
                Spacer()
            }
        }
        .padding(.leading, 8)
    }
}

// New view for displaying raw frequency analysis data
struct RawFrequencyAnalysisView: View {
    @ObservedObject var noteDetector: NoteDetector
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Dominant Frequency
                HStack {
                    Text("🎯 Dominant Frequency:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(String(format: "%.1f", noteDetector.dominantFrequency)) Hz")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.bold)
                    Spacer()
                }
                
                // Audio Buffer Status
                HStack {
                    Text("📊 Buffer Status:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(noteDetector.sampleCount) samples")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                }
                
                Divider()
                
                // FFT Spectrum Data
                Text("🌊 FFT Spectrum (first 20 bins):")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                if !noteDetector.spectrumData.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(Array(noteDetector.spectrumData.prefix(20).enumerated()), id: \.offset) { index, magnitude in
                            VStack(spacing: 2) {
                                Text("Bin \(index)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.4f", magnitude))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(magnitude > 0.01 ? .red : .primary)
                            }
                            .padding(4)
                            .background(magnitude > 0.01 ? Color.red.opacity(0.1) : Color.clear)
                            .cornerRadius(4)
                        }
                    }
                } else {
                    Text("No spectrum data available")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                Divider()
                
                // Peak Detection Information
                Text("🔍 Peak Detection Info:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Searching frequency range: 80-4000 Hz")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Dynamic threshold: \(String(format: "%.6f", noteDetector.currentThreshold))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Noise floor: \(String(format: "%.6f", noteDetector.noiseFloor))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("• Total peaks found: \(noteDetector.peakCount)")
                        .font(.caption2)
                        .foregroundColor(noteDetector.peakCount > 0 ? .green : .red)
                        .fontWeight(.medium)
                }
                
                // Maximum FFT Value
                if !noteDetector.spectrumData.isEmpty {
                    let maxValue = noteDetector.spectrumData.max() ?? 0.0
                    let maxIndex = noteDetector.spectrumData.firstIndex(of: maxValue) ?? 0
                    let binFrequency = Double(maxIndex) * (48000.0 / 2048.0) // Assuming 48kHz sample rate, 2048 FFT size
                    
                    HStack {
                        Text("📈 Max FFT Value:")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("\(String(format: "%.6f", maxValue)) at \(String(format: "%.1f", binFrequency)) Hz")
                            .font(.caption)
                            .foregroundColor(maxValue > 0.004 ? .green : .red)
                            .fontWeight(.bold)
                        Spacer()
                    }
                }
                
                // Overall Statistics
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max Magnitude:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.6f", noteDetector.maxMagnitude))")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(noteDetector.maxMagnitude > noteDetector.currentThreshold ? .green : .red)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Total Magnitude:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.2f", noteDetector.totalMagnitude))")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                
                Divider()
                
                // Raw Peaks Display
                if !noteDetector.rawPeaks.isEmpty {
                    Text("🎯 Raw Peaks Detected (\(noteDetector.rawPeaks.count) total):")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    let displayPeaks = Array(noteDetector.rawPeaks.sorted { $0.magnitude > $1.magnitude }.prefix(10))
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2), spacing: 4) {
                        ForEach(Array(displayPeaks.enumerated()), id: \.offset) { index, peak in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(String(format: "%.1f", peak.frequency)) Hz")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(peak.magnitude > noteDetector.currentThreshold ? .green : .red)
                                Text("Mag: \(String(format: "%.4f", peak.magnitude))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Bin: \(peak.binIndex)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(6)
                            .background(peak.magnitude > noteDetector.currentThreshold ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                } else {
                    Text("🔍 No raw peaks detected")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .italic()
                }
            }
            .padding(12)
        }
    }
}

// Waveform visualization showing raw audio signal
struct WaveformVisualizationView: View {
    @ObservedObject var noteDetector: NoteDetector
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Draw background grid
                let gridColor = Color.gray.opacity(0.3)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    },
                    with: .color(gridColor),
                    lineWidth: 1
                )
                
                // Draw waveform
                guard !noteDetector.rawAudioWaveform.isEmpty else { return }
                
                let samples = noteDetector.rawAudioWaveform
                let waveformPath = Path { path in
                    let stepX = size.width / CGFloat(samples.count)
                    let centerY = size.height / 2
                    let maxAmplitude = size.height / 2 * 0.8 // Use 80% of available height
                    
                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = centerY - CGFloat(sample) * maxAmplitude
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                
                context.stroke(waveformPath, with: .color(.green), lineWidth: 1.5)
                
                // Draw RMS level indicator
                let rmsLevel = noteDetector.audioLevel
                let rmsY = geometry.size.height / 2 - CGFloat(rmsLevel) * geometry.size.height / 2 * 0.8
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: rmsY))
                        path.addLine(to: CGPoint(x: size.width, y: rmsY))
                    },
                    with: .color(.red.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
            }
            .overlay(
                VStack {
                    HStack {
                        Text("RMS: \(String(format: "%.3f", noteDetector.audioLevel))")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(4)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(4)
                        Spacer()
                        Text("\(noteDetector.rawAudioWaveform.count) samples")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(4)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(4)
                    }
                    Spacer()
                },
                alignment: .topLeading
            )
        }
    }
}

// Spectrum visualization showing frequency magnitudes
struct SpectrumVisualizationView: View {
    @ObservedObject var noteDetector: NoteDetector
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Debug: Print spectrum data to see if it's being received
                if noteDetector.spectrumDisplay.isEmpty {
                    // Draw "No Data" message
                    let text = Text("No spectrum data")
                        .font(.caption)
                        .foregroundColor(.red)
                    context.draw(text, at: CGPoint(x: size.width/2, y: size.height/2))
                    return
                }
                
                let spectrum = noteDetector.spectrumDisplay
                let binWidth = size.width / CGFloat(spectrum.count)
                let maxMagnitude = max(spectrum.max() ?? 1.0, 0.001) // Prevent division by zero
                
                // Draw spectrum bars
                for (index, magnitude) in spectrum.enumerated() {
                    let x = CGFloat(index) * binWidth
                    let normalizedMagnitude = magnitude / maxMagnitude
                    let barHeight = CGFloat(normalizedMagnitude) * size.height * 0.9
                    
                    let barRect = CGRect(
                        x: x,
                        y: size.height - barHeight,
                        width: max(1, binWidth - 1),
                        height: barHeight
                    )
                    
                    // Color code by magnitude
                    let color: Color
                    if magnitude > noteDetector.currentThreshold {
                        color = .green
                    } else if magnitude > noteDetector.noiseFloor {
                        color = .yellow
                    } else {
                        color = .blue.opacity(0.6)
                    }
                    
                    context.fill(Path(barRect), with: .color(color))
                }
                
                // Draw threshold line
                let thresholdY = size.height - (CGFloat(noteDetector.currentThreshold / maxMagnitude) * size.height * 0.9)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: thresholdY))
                        path.addLine(to: CGPoint(x: size.width, y: thresholdY))
                    },
                    with: .color(.red),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                
                // Draw noise floor line
                let noiseFloorY = size.height - (CGFloat(noteDetector.noiseFloor / maxMagnitude) * size.height * 0.9)
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: noiseFloorY))
                        path.addLine(to: CGPoint(x: size.width, y: noiseFloorY))
                    },
                    with: .color(.orange),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }
            .overlay(
                VStack {
                    HStack {
                        Text("Max: \(String(format: "%.4f", noteDetector.maxMagnitude))")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(2)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(3)
                        
                        Text("Threshold")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(2)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(3)
                        
                        Text("Noise Floor")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(2)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(3)
                        
                        Spacer()
                        
                        Text("\(noteDetector.peakCount) peaks")
                            .font(.caption2)
                            .foregroundColor(noteDetector.peakCount > 0 ? .green : .red)
                            .fontWeight(.medium)
                            .padding(2)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(3)
                    }
                    Spacer()
                },
                alignment: .topLeading
            )
        }
    }
}

#Preview {
    ContentView()
} 