import Foundation
import SwiftUI
import Combine

struct DetectedNote {
    let name: String
    let frequency: Double
    let magnitude: Float
    let cents: Double  // How many cents off from perfect pitch
    let color: Color
}

@MainActor
class NoteDetector: ObservableObject {
    @Published var primaryNote: DetectedNote?
    @Published var secondaryNotes: [DetectedNote] = []
    @Published var sensitivity: Double = 0.5
    
    // Audio visualization data
    @Published var audioLevel: Float = 0.0
    @Published var sampleCount: Int = 0
    @Published var spectrumData: [Float] = []
    @Published var dominantFrequency: Double = 0.0
    
    private var noteHistory: [DetectedNote] = []
    private let maxHistorySize = 10
    private let stabilityThreshold = 3  // How many consecutive detections before showing a note
    
    init() {}
    
    func updateDetectedNotes(_ notes: [DetectedNote]) {
        print("🎯 NoteDetector received \(notes.count) notes, sensitivity: \(sensitivity)")
        
        // Filter notes based on sensitivity
        let filteredNotes = notes.filter { note in
            Double(note.magnitude) > sensitivity * 1000  // Adjust threshold based on sensitivity
        }
        
        print("🔍 After sensitivity filtering: \(filteredNotes.count) notes")
        
        guard !filteredNotes.isEmpty else {
            // No strong notes detected
            print("⚫ No strong notes detected - fading out")
            fadeOutNotes()
            return
        }
        
        // Update primary note (strongest)
        let strongest = filteredNotes.first!
        print("🎵 Primary note: \(strongest.name) (\(String(format: "%.1f", strongest.frequency))Hz, mag: \(strongest.magnitude))")
        updatePrimaryNote(strongest)
        
        // Update secondary notes (weaker but still significant)
        let secondary = Array(filteredNotes.dropFirst().prefix(3))
        print("🎶 Secondary notes: \(secondary.map { $0.name }.joined(separator: ", "))")
        updateSecondaryNotes(secondary)
    }
    
    private func updatePrimaryNote(_ note: DetectedNote) {
        // Add to history for stability checking
        noteHistory.append(note)
        if noteHistory.count > maxHistorySize {
            noteHistory.removeFirst()
        }
        
        // Check if we have enough stable detections
        let recentNotes = noteHistory.suffix(stabilityThreshold)
        let stableNote = findStableNote(in: Array(recentNotes))
        
        if let stable = stableNote {
            print("✅ Setting primary note to: \(stable.name)")
            primaryNote = stable
        } else {
            print("⚠️ No stable note found yet, history: \(noteHistory.count)/\(stabilityThreshold)")
        }
    }
    
    private func updateSecondaryNotes(_ notes: [DetectedNote]) {
        secondaryNotes = notes
    }
    
    private func findStableNote(in notes: [DetectedNote]) -> DetectedNote? {
        guard notes.count >= stabilityThreshold else { return nil }
        
        // Group notes by name (ignoring octave for stability)
        let groupedNotes = Dictionary(grouping: notes) { note in
            String(note.name.prefix(2))  // Just the note name without octave
        }
        
        // Find the most frequent note
        let mostFrequent = groupedNotes.max { $0.value.count < $1.value.count }
        
        guard let (_, noteGroup) = mostFrequent,
              noteGroup.count >= stabilityThreshold else { return nil }
        
        // Return the most recent note from the most frequent group
        return noteGroup.last
    }
    
    private func fadeOutNotes() {
        // Gradually fade out notes when no signal is detected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.noteHistory.isEmpty {
                self.primaryNote = nil
                self.secondaryNotes = []
            }
        }
    }
    
    // Update audio visualization data
    func updateAudioVisualization(level: Float, sampleCount: Int, spectrum: [Float], dominantFreq: Double) {
        self.audioLevel = level
        self.sampleCount = sampleCount
        self.spectrumData = spectrum
        self.dominantFrequency = dominantFreq
        print("📊 Audio visualization updated - Level: \(level), Samples: \(sampleCount), Peak: \(dominantFreq)Hz")
    }
} 