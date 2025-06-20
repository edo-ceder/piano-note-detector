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
        .frame(width: 500, height: 600)
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

#Preview {
    ContentView()
} 