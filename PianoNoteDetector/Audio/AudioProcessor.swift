import Foundation
import ScreenCaptureKit
import AVFoundation
import Accelerate

class AudioProcessor: NSObject, SCStreamOutput {
    private var noteDetector: NoteDetector
    private var sampleRate: Double = 44100
    private var fftSize = 4096
    private var fftSetup: FFTSetup?
    private var audioBuffer: [Float] = []
    
    init(noteDetector: NoteDetector) {
        self.noteDetector = noteDetector
        super.init()
        setupFFT()
    }
    
    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
    
    private func setupFFT() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    // This delegate method is called by ScreenCaptureKit with audio buffers.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Let's confirm we're getting here.
        print("🎤 AudioProcessor received a sample buffer.")
        
        // Update sample rate from buffer description if needed
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            if let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
                self.sampleRate = streamBasicDescription.mSampleRate
                print("📊 Sample rate: \(self.sampleRate) Hz")
            }
        }
        
        processAudioSampleBuffer(sampleBuffer)
    }
    
    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("❌ Failed to get block buffer from sample buffer.")
            return
        }
        
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        var totalLength = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        guard status == noErr, let data = dataPointer, totalLength > 0 else {
            print("❌ Failed to get data pointer from block buffer. Status: \(status)")
            return
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        let floatSampleCount = totalLength / MemoryLayout<Float>.size
        let floatPointer = data.withMemoryRebound(to: Float.self, capacity: floatSampleCount) { $0 }
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: floatSampleCount))

        var monoSamples: [Float] = []
        if floatSampleCount == numSamples * 2 { // Stereo
            for i in stride(from: 0, to: samples.count - 1, by: 2) {
                monoSamples.append((samples[i] + samples[i + 1]) * 0.5)
            }
        } else { // Mono
            monoSamples = samples
        }
        
        audioBuffer.append(contentsOf: monoSamples)
        
        let audioLevel = calculateAudioLevel(monoSamples)
        
        Task { @MainActor in
            noteDetector.updateAudioVisualization(level: audioLevel, sampleCount: audioBuffer.count, spectrum: [], dominantFreq: 0.0)
        }
        
        if audioBuffer.count >= fftSize {
            performFFTAnalysis()
            audioBuffer = Array(audioBuffer.suffix(fftSize / 2))
        }
    }
    
    private func calculateAudioLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return min(1.0, max(0.0, rms * 5.0))
    }
    
    private func performFFTAnalysis() {
        guard let fftSetup = fftSetup, audioBuffer.count >= fftSize else { return }
        
        var realParts = [Float](audioBuffer.prefix(fftSize))
        var imaginaryParts = [Float](repeating: 0.0, count: fftSize)
        
        vDSP_hann_window(&realParts, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imaginaryParts.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &splitComplex, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                
                var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                
                let scale = 1.0 / (Float(fftSize) * 2.0)
                vDSP_vsmul(magnitudes, 1, [scale], &magnitudes, 1, vDSP_Length(fftSize / 2))
                
                findNotesFromFFT(magnitudes: magnitudes)
            }
        }
    }
    
    private func findNotesFromFFT(magnitudes: [Float]) {
        let binSize = sampleRate / Double(fftSize)
        var peaks: [(frequency: Double, magnitude: Float)] = []
        
        let spectrumData = Array(magnitudes.prefix(min(50, magnitudes.count)))
        let maxMagnitudeIndex = magnitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let dominantFrequency = Double(maxMagnitudeIndex) * binSize
        
        for i in 2..<(magnitudes.count - 2) {
            if magnitudes[i] > magnitudes[i-1] && magnitudes[i] > magnitudes[i+1] && magnitudes[i] > magnitudes[i-2] && magnitudes[i] > magnitudes[i+2] {
                let frequency = Double(i) * binSize
                if frequency >= 80.0 && frequency <= 2000.0 {
                    peaks.append((frequency: frequency, magnitude: magnitudes[i]))
                }
            }
        }
        
        peaks.sort { $0.magnitude > $1.magnitude }
        let detectedNotes = Array(peaks.prefix(5)).compactMap { frequencyToNote(frequency: $0.frequency, magnitude: $0.magnitude) }
        
        Task { @MainActor in
            noteDetector.updateAudioVisualization(level: noteDetector.audioLevel, sampleCount: noteDetector.sampleCount, spectrum: spectrumData, dominantFreq: dominantFrequency)
            noteDetector.updateDetectedNotes(detectedNotes)
        }
    }
    
    private func frequencyToNote(frequency: Double, magnitude: Float) -> DetectedNote? {
        let noteNumber = 12.0 * log2(frequency / 440.0) + 69.0
        let roundedNote = Int(round(noteNumber))
        let cents = (noteNumber - Double(roundedNote)) * 100.0
        guard abs(cents) <= 50.0 else { return nil }
        let noteName = midiNoteToName(roundedNote)
        return DetectedNote(name: noteName, frequency: frequency, magnitude: magnitude, cents: cents, color: noteColor(for: noteName))
    }
    
    private func midiNoteToName(_ midiNote: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (midiNote / 12) - 1
        let noteIndex = midiNote % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    private func noteColor(for noteName: String) -> Color {
        let note = noteName.prefix(while: { !$0.isNumber })
        switch note {
            case "C": return .red
            case "D": return .orange
            case "E": return .yellow
            case "F": return .green
            case "G": return .blue
            case "A": return Color(red: 0.29, green: 0, blue: 0.51) // Indigo
            case "B": return .purple
            default: return .white
        }
    }
}

import SwiftUI

extension Color {
    static let mint = Color(red: 0.0, green: 1.0, blue: 0.8)
} 