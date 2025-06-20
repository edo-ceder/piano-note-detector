import Foundation
import ScreenCaptureKit
import Combine
import AppKit

@MainActor
class AudioCaptureManager: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var hasPermission = false
    @Published var isCheckingPermission = true

    private var stream: SCStream?
    private var audioProcessor: AudioProcessor?
    private var noteDetector: NoteDetector?
    private var permissionCheckTimer: Timer?
    private var permissionCheckCount = 0  // Make this a class property
    
    // Add a debug mode to bypass permission checks
    private let debugBypassPermissions = false  // Set to false to use real permission checks

    func setNoteDetector(_ noteDetector: NoteDetector) {
        self.noteDetector = noteDetector
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
    }

    func checkPermissions() {
        isCheckingPermission = true
        NSLog("🔍 PianoNoteDetector: Checking screen recording permissions...")
        print("🔍 Checking screen recording permissions...")
        
        // Cancel any existing timer
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        
        Task {
            defer {
                DispatchQueue.main.async {
                    self.isCheckingPermission = false
                    
                    // If we don't have permission, start a timer to check periodically
                    if !self.hasPermission {
                        self.startPermissionCheckTimer()
                    }
                }
            }
            
            // The key insight: We need to actually try to use ScreenCaptureKit
            // to properly detect if we have permissions. Just checking for
            // shareable content isn't enough in all launch contexts.
            
            do {
                NSLog("🔎 PianoNoteDetector: Attempting to create minimal SCStream to verify permissions...")
                
                // Get shareable content
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                
                // Try to create a minimal stream configuration to truly test permissions
                if let display = content.displays.first {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = 1
                    config.height = 1
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                    
                    // Create a minimal stream - this will fail if we don't have permissions
                    let testStream = SCStream(filter: filter, configuration: config, delegate: nil)
                    
                    // If we get here, we have permissions
                    NSLog("✅ PianoNoteDetector: Screen recording permission verified!")
                    print("✅ Screen recording permission verified!")
                    DispatchQueue.main.async {
                        self.hasPermission = true
                    }
                    
                    // Clean up the test stream
                    try? await testStream.stopCapture()
                } else {
                    NSLog("⚠️ PianoNoteDetector: No displays found")
                    print("⚠️ No displays found")
                    DispatchQueue.main.async {
                        self.hasPermission = false
                    }
                }
            } catch let error as NSError {
                NSLog("❌ PianoNoteDetector: Permission check failed: \(error.localizedDescription) (domain: \(error.domain), code: \(error.code))")
                print("❌ Permission check failed: \(error.localizedDescription) (domain: \(error.domain), code: \(error.code))")
                
                // Check for the specific TCC error
                if error.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && error.code == -3801 {
                    NSLog("❌ PianoNoteDetector: Screen recording permission denied")
                    print("❌ Screen recording permission denied")
                }
                
                DispatchQueue.main.async {
                    self.hasPermission = false
                }
            }
        }
    }
    
    func requestPermissions() {
        NSLog("📱 PianoNoteDetector: Requesting screen recording permissions...")
        print("📱 Requesting screen recording permissions...")
        
        // The only way to trigger the system permission dialog is to actually try to use ScreenCaptureKit
        Task {
            do {
                // Get shareable content
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                
                if let display = content.displays.first {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    
                    // Create a minimal configuration to trigger permission request
                    let config = SCStreamConfiguration()
                    config.capturesAudio = true
                    config.excludesCurrentProcessAudio = true
                    config.sampleRate = 48000
                    config.channelCount = 2
                    
                    // Try to create a stream - this will trigger the permission dialog
                    _ = SCStream(filter: filter, configuration: config, delegate: nil)
                    
                    NSLog("📱 PianoNoteDetector: Permission request completed")
                    print("📱 Permission request completed")
                }
            } catch {
                NSLog("📱 PianoNoteDetector: Permission request completed with error: \(error)")
                print("📱 Permission request completed with error: \(error)")
            }
            
            // Check permissions after request
            checkPermissions()
        }
    }
    
    private func startPermissionCheckTimer() {
        // Cancel any existing timer
        permissionCheckTimer?.invalidate()
        
        let maxChecks = 10 // Stop checking after 20 seconds (10 checks * 2 seconds)
        
        // Check every 2 seconds if permissions have been granted
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                self.permissionCheckCount += 1
                
                if !self.hasPermission && !self.isCheckingPermission && self.permissionCheckCount < maxChecks {
                    NSLog("⏱️ PianoNoteDetector: Auto-checking permissions... (attempt \(self.permissionCheckCount)/\(maxChecks))")
                    print("⏱️ Auto-checking permissions... (attempt \(self.permissionCheckCount)/\(maxChecks))")
                    self.checkPermissions()
                } else if self.permissionCheckCount >= maxChecks {
                    NSLog("⏱️ PianoNoteDetector: Stopping automatic permission checks after \(maxChecks) attempts")
                    print("⏱️ Stopping automatic permission checks after \(maxChecks) attempts")
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                }
            }
        }
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        print("📱 Opened System Settings > Privacy & Security > Screen Recording")
        print("💡 Please toggle the permission for PianoNoteDetector ON, then click 'Refresh'")
    }

    func startCapture() {
        guard !isCapturing else { return }
        NSLog("▶️ PianoNoteDetector: startCapture called.")
        print("▶️ startCapture called.")
        
        // Check permissions one more time before starting
        guard hasPermission else {
            NSLog("⚠️ PianoNoteDetector: Cannot start capture - no permission. Please grant Screen Recording permission.")
            print("⚠️ Cannot start capture - no permission. Please grant Screen Recording permission.")
            checkPermissions()
            return
        }

        Task {
            do {
                NSLog("1/5 PianoNoteDetector: Getting shareable content...")
                print("1/5: Getting shareable content...")
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                NSLog("2/5 PianoNoteDetector: Shareable content found. Displays: \(content.displays.count), Applications: \(content.applications.count)")
                print("2/5: Shareable content found. Displays: \(content.displays.count), Applications: \(content.applications.count)")

                guard let display = content.displays.first else {
                    throw NSError(domain: "PianoNoteDetector", code: -1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
                }

                NSLog("3/5 PianoNoteDetector: Creating content filter...")
                print("3/5: Creating content filter...")
                
                // Create a filter that captures the entire display INCLUDING audio from all applications
                // Simplified filter - just capture everything from the display
                let filter = SCContentFilter(display: display, excludingWindows: [])
                
                NSLog("4/5 PianoNoteDetector: Creating stream configuration...")
                print("4/5: Creating stream configuration...")
                
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = false  // Changed to false to capture ALL audio
                config.sampleRate = 48000 // Use a commonly-supported rate
                config.channelCount = 2
                
                // Set minimal video configuration (required even for audio-only capture)
                config.width = 1920
                config.height = 1080
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                
                NSLog("4.5 PianoNoteDetector: Stream config - capturesAudio: \(config.capturesAudio), sampleRate: \(config.sampleRate), channels: \(config.channelCount)")
                print("4.5: Stream config - capturesAudio: \(config.capturesAudio), sampleRate: \(config.sampleRate), channels: \(config.channelCount)")
                print("4/5: Created stream configuration.")

                stream = SCStream(filter: filter, configuration: config, delegate: self)  // Changed delegate back to self
                print("4.1: Created SCStream instance")
                
                if let noteDetector = self.noteDetector {
                    self.audioProcessor = AudioProcessor(noteDetector: noteDetector)
                    print("4.2: Created AudioProcessor instance")
                    let queue = DispatchQueue(label: "com.pianoapp.PianoNoteDetector.AudioQueue")
                    print("4.3: Created audio processing queue")
                    try stream?.addStreamOutput(self.audioProcessor!, type: .audio, sampleHandlerQueue: queue)
                    print("5/5: Added audio stream output.")
                    
                    // Add a test to see if we can get stream info
                    if let stream = stream {
                        print("Stream info: \(stream)")
                    }
                } else {
                    throw AudioCaptureError.noteDetectorMissing
                }

                print("5.1: About to start capture...")
                stream?.startCapture { error in
                    if let error = error {
                        NSLog("❌ PianoNoteDetector: Failed to start stream capture: \(error)")
                        print("❌ Failed to start stream capture: \(error)")
                    } else {
                        NSLog("✅ PianoNoteDetector: Stream capture started successfully")
                        print("✅ Stream capture started successfully")
                    }
                }
                self.isCapturing = true
                print("✅ Audio capture started successfully.")
                print("✅ Stream is now capturing audio. Waiting for audio buffers...")

            } catch {
                print("❌ Failed to start capture: \(error.localizedDescription)")
                self.isCapturing = false
                
                // Re-check permissions in case they were revoked
                self.checkPermissions()
            }
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        
        stream?.stopCapture() { [weak self] error in
            if let error = error {
                print("❌ Error stopping capture: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.isCapturing = false
                self?.stream = nil
                self?.audioProcessor = nil
                print("✅ Audio capture stopped.")
            }
        }
    }
}

extension AudioCaptureManager: @preconcurrency SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.isCapturing = false
            print("❌ Stream stopped with error: \(error.localizedDescription)")
            
            // Re-check permissions in case they were revoked
            self.checkPermissions()
        }
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case noteDetectorMissing
    case noDisplayFound
    
    var errorDescription: String? {
        switch self {
        case .noteDetectorMissing:
            return "NoteDetector was not configured before starting capture."
        case .noDisplayFound:
            return "No display was found in the shareable content to capture from."
        }
    }
}