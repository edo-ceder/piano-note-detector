import Foundation
import ScreenCaptureKit
import AVFoundation
import Accelerate
import SwiftUI

class AudioProcessor: NSObject, SCStreamOutput {
    private var noteDetector: NoteDetector
    private var sampleRate: Double = 48000
    private var fftSize = 2048
    private var fftSetup: FFTSetup?
    private var audioBuffer: [Float] = []
    private let processingQueue = DispatchQueue(label: "AudioProcessing", qos: .userInitiated)
    private var autocorrelationCounter: Int = 0
    
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
        NSLog("🔧 PianoNoteDetector: FFT setup created with log2n=\(log2n), fftSize=\(fftSize)")
        
        // Verify the setup is valid
        if fftSetup == nil {
            NSLog("❌ PianoNoteDetector: FFT setup FAILED!")
        } else {
            NSLog("✅ PianoNoteDetector: FFT setup successful")
        }
    }
    
    // This delegate method is called by ScreenCaptureKit with audio buffers.
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { 
            print("🎬 AudioProcessor received non-audio buffer (type: \(type))")
            return 
        }

        // ULTRA-MINIMAL CALLBACK: Only dispatch to safe queue and return immediately
        NSLog("🎤 PianoNoteDetector: AudioProcessor received buffer - dispatching to safe queue")
        
        // Move ALL processing to a safe dispatch queue - NOTHING else should happen in this callback
        processingQueue.async {
            self.processAudioSampleBufferSafely(sampleBuffer)
        }
    }
    
    private func processAudioSampleBufferSafely(_ sampleBuffer: CMSampleBuffer) {
        NSLog("🔧 PianoNoteDetector: Processing audio buffer safely in background queue")
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            NSLog("❌ PianoNoteDetector: Failed to get block buffer from sample buffer.")
            return
        }
        
        NSLog("✅ PianoNoteDetector: Got block buffer, proceeding with data extraction")
        
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        var totalLength = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        guard status == noErr, let data = dataPointer, totalLength > 0 else {
            NSLog("❌ PianoNoteDetector: Failed to get data pointer from block buffer. Status: \(status), totalLength: \(totalLength)")
            return
        }
        
        NSLog("✅ PianoNoteDetector: Got data pointer, totalLength: \(totalLength)")

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        let channels = 2 // Assume stereo
        let samplesPerChannel = numSamples / channels
        let floatPointer = data.withMemoryRebound(to: Float.self, capacity: numSamples) { $0 }
        let sampleData = UnsafeBufferPointer(start: floatPointer, count: numSamples)
        
        NSLog("📊 PianoNoteDetector: Processing \(samplesPerChannel) samples per channel")
        
        // Convert to mono and process
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(samplesPerChannel)
        
        for i in 0..<samplesPerChannel {
            let leftIndex = i * channels
            let rightIndex = leftIndex + 1
            
            if rightIndex < sampleData.count {
                let monoSample = (sampleData[leftIndex] + sampleData[rightIndex]) / 2.0
                monoSamples.append(monoSample)
            }
        }
        
        audioBuffer.append(contentsOf: monoSamples)
        
        let audioLevel = calculateAudioLevel(monoSamples)
        
        // Debug buffer accumulation - log EVERY buffer to see what's happening
        NSLog("🔢 PianoNoteDetector: Audio buffer now has \(audioBuffer.count)/\(fftSize) samples (just added \(monoSamples.count), need \(fftSize - audioBuffer.count) more for FFT)")
        
        // Also log audio level
        NSLog("📊 PianoNoteDetector: Audio level: \(audioLevel), max sample: \(monoSamples.max() ?? 0.0)")
        
        Task { @MainActor in
            noteDetector.updateAudioVisualization(level: audioLevel, sampleCount: audioBuffer.count, spectrum: [], dominantFreq: 0.0)
        }
        
        if audioBuffer.count >= fftSize {
            NSLog("✅ PianoNoteDetector: Buffer ready for FFT analysis!")
            
            // Log a few sample values before FFT to verify data is changing
            let sampleValues = Array(audioBuffer.prefix(10))
            NSLog("🔍 PianoNoteDetector: First 10 buffer samples: \(sampleValues.map { String(format: "%.6f", $0) }.joined(separator: ", "))")
            
            performFFTAnalysis()
            // Keep much more data for autocorrelation - only remove 25% of the buffer
            let removeCount = fftSize / 4
            if audioBuffer.count > removeCount {
                audioBuffer.removeFirst(removeCount) // Keep 75% overlap for autocorrelation
            }
            NSLog("🧹 PianoNoteDetector: Buffer cleaned, \(audioBuffer.count) samples remaining")
        }
    }
    
    private func processAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        print("🏁 processAudioSampleBuffer called")
        
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
        
        // Debug buffer accumulation
        if audioBuffer.count % 512 == 0 { // Log every 512 samples
            print("📈 Audio buffer: \(audioBuffer.count)/\(fftSize) samples (need \(fftSize - audioBuffer.count) more)")
        }
        
        Task { @MainActor in
            noteDetector.updateAudioVisualization(level: audioLevel, sampleCount: audioBuffer.count, spectrum: [], dominantFreq: 0.0)
        }
        
        if audioBuffer.count >= fftSize {
            NSLog("✅ PianoNoteDetector: Buffer ready for FFT analysis!")
            
            // Log a few sample values before FFT to verify data is changing
            let sampleValues = Array(audioBuffer.prefix(10))
            NSLog("🔍 PianoNoteDetector: First 10 buffer samples: \(sampleValues.map { String(format: "%.6f", $0) }.joined(separator: ", "))")
            
            performFFTAnalysis()
            
            // Keep much more data for autocorrelation - only remove 25% of the buffer
            let removeCount = fftSize / 4
            if audioBuffer.count > removeCount {
                audioBuffer.removeFirst(removeCount) // Keep 75% overlap for autocorrelation
            }
            NSLog("🧹 PianoNoteDetector: Buffer cleaned, \(audioBuffer.count) samples remaining")
        }
    }
    
    private func calculateAudioLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return min(1.0, max(0.0, rms * 5.0))
    }
    
    private func performFFTAnalysis() {
        guard let fftSetup = fftSetup, audioBuffer.count >= fftSize else { 
            NSLog("⚠️ PianoNoteDetector: FFT skipped - setup: \(fftSetup != nil), buffer size: \(audioBuffer.count)/\(fftSize)")
            return 
        }
        
        NSLog("🔧 PianoNoteDetector: Starting FFT analysis with \(audioBuffer.count) samples")
        
        var realParts = [Float](audioBuffer.prefix(fftSize))
        var imaginaryParts = [Float](repeating: 0.0, count: fftSize)
        
        // Log first few values being fed to FFT to verify they match our buffer samples
        let firstFewFFTSamples = Array(realParts.prefix(10))
        NSLog("🔧 PianoNoteDetector: First 10 FFT input samples: \(firstFewFFTSamples.map { String(format: "%.6f", $0) }.joined(separator: ", "))")
        
        // Remove DC offset before FFT analysis
        let mean = realParts.reduce(0, +) / Float(realParts.count)
        for i in 0..<realParts.count {
            realParts[i] -= mean
        }
        NSLog("🔧 PianoNoteDetector: Removed DC offset: \(mean), first few after DC removal: \(Array(realParts.prefix(5)).map { String(format: "%.6f", $0) }.joined(separator: ", "))")
        
        // Apply Hann window
        vDSP_hann_window(&realParts, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        let log2n = vDSP_Length(log2(Float(fftSize)))
        NSLog("🔧 PianoNoteDetector: Performing FFT with log2n=\(log2n)")
        
        // Disable FFT completely to fix CPU leak - just use autocorrelation
        NSLog("🔧 PianoNoteDetector: FFT disabled - using autocorrelation only")
        
        // Skip FFT entirely and just do autocorrelation-based detection
        // Create thread-safe copy of audio buffer for calculations
        guard !audioBuffer.isEmpty else {
            NSLog("⚠️ Empty audio buffer for processing")
            return
        }
        
        let audioBufferCopy = Array(audioBuffer)
        
        // Calculate RMS level for audio visualization
        var sumOfSquares: Float = 0.0
        for sample in audioBufferCopy {
            sumOfSquares += sample * sample
        }
        let rmsLevel = sqrt(sumOfSquares / Float(audioBufferCopy.count))
        
        // Create minimal spectrum data for visualization (just zeros since we're not doing FFT)
        let spectrumData = [Float](repeating: 0.0, count: 50)
        
        // Throttle autocorrelation to prevent CPU overload
        // Only run autocorrelation every 5th buffer (~100ms intervals instead of ~20ms)
        autocorrelationCounter += 1
        let shouldRunAutocorrelation = (autocorrelationCounter % 5 == 0)
        
        Task { @MainActor in
            noteDetector.updateAudioVisualization(level: rmsLevel, sampleCount: audioBufferCopy.count, spectrum: spectrumData, dominantFreq: 0.0)
            noteDetector.updateRawAudioWaveform(Array(audioBufferCopy.suffix(1024))) // Send last 1024 samples for waveform
            
            // Only run expensive autocorrelation every 5th buffer to reduce CPU usage
            if shouldRunAutocorrelation {
                let detectedNotes = detectPitchWithAutocorrelation(audioBufferCopy)
                noteDetector.updateDetectedNotes(detectedNotes)
            }
        }
    }
    
    private func findNotesFromFFT(magnitudes: [Float]) {
        NSLog("🎵 PianoNoteDetector: findNotesFromFFT called with \(magnitudes.count) magnitudes")
        let binSize = sampleRate / Double(fftSize)
        var peaks: [(frequency: Double, magnitude: Float)] = []
        
        // Skip DC component (bin 0) for spectrum display and analysis
        guard magnitudes.count > 1 else {
            NSLog("⚠️ Insufficient magnitude data: \(magnitudes.count)")
            return
        }
        
        let spectrumData = Array(magnitudes[1...].prefix(min(50, magnitudes.count-1)))
        let musicalMagnitudes = Array(magnitudes[1...]) // Skip DC component
        let maxMagnitudeIndex = musicalMagnitudes.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let dominantFrequency = Double(maxMagnitudeIndex + 1) * binSize // +1 because we skipped bin 0
        
        NSLog("🎯 PianoNoteDetector: Max musical magnitude: \(musicalMagnitudes.max() ?? 0.0) at bin \(maxMagnitudeIndex + 1), freq: \(dominantFrequency)Hz")
        
        NSLog("🔍 PianoNoteDetector: Peak detection - Bin size: \(binSize)Hz, Dominant freq: \(dominantFrequency)Hz")
        
        // Debug: Log some magnitude values to understand the spectrum
        let sampleMagnitudes = Array(magnitudes.prefix(20))
        NSLog("📈 PianoNoteDetector: First 20 magnitude values: \(sampleMagnitudes.map { String(format: "%.6f", $0) }.joined(separator: ", "))")
        
        // Log some mid and high frequency values too
        let midStart = magnitudes.count / 4
        let midMagnitudes = Array(magnitudes[midStart..<min(midStart + 10, magnitudes.count)])
        NSLog("📈 PianoNoteDetector: Mid-frequency magnitudes (bins \(midStart)-\(midStart+9)): \(midMagnitudes.map { String(format: "%.6f", $0) }.joined(separator: ", "))")
        
        // Skip DC component and calculate dynamic threshold from musical frequencies  
        guard magnitudes.count > 3 else {
            NSLog("⚠️ Not enough magnitude data: \(magnitudes.count)")
            return
        }
        
        let musicalBins = Array(magnitudes[3...])  // Skip first 3 bins (DC and very low freq)
        
        NSLog("🔧 PianoNoteDetector: DC component magnitude: \(magnitudes[0]), First musical bin: \(magnitudes[3])")
        let sortedMusicalMagnitudes = musicalBins.sorted()
        
        guard !musicalBins.isEmpty else {
            NSLog("⚠️ Empty musical bins array")
            return
        }
        
        let noiseFloor = sortedMusicalMagnitudes[musicalBins.count / 4] // 25th percentile as noise floor
        let meanMagnitude = musicalBins.reduce(0, +) / Float(musicalBins.count)
        let dynamicThreshold = max(noiseFloor * 1.5, 0.001) // Much more sensitive threshold for testing
        
        // Calculate overall magnitude statistics
        let maxMagnitude = magnitudes.max() ?? 0.0
        let totalMagnitude = magnitudes.reduce(0, +)
        
        NSLog("🔍 PianoNoteDetector: Noise floor: \(noiseFloor), Mean: \(meanMagnitude), Dynamic threshold: \(dynamicThreshold)")
        
        // Create raw peaks array for debugging
        var rawPeaks: [FrequencyPeak] = []
        
        // Find peaks with simpler, more lenient algorithm
        for i in 1..<(magnitudes.count - 1) {  // Start from bin 1 to skip DC
            // Simple local maximum: just higher than immediate neighbors
            if magnitudes[i] > magnitudes[i-1] && magnitudes[i] > magnitudes[i+1] {
                let frequency = Double(i) * binSize
                
                // Add to raw peaks for debugging (all peaks, not just musical ones)
                rawPeaks.append(FrequencyPeak(frequency: frequency, magnitude: magnitudes[i], binIndex: i))
                
                // Musical frequency range with relaxed threshold
                if frequency >= 80.0 && frequency <= 4000.0 && magnitudes[i] > dynamicThreshold {
                    peaks.append((frequency: frequency, magnitude: magnitudes[i]))
                    NSLog("🎯 Peak detected: \(String(format: "%.1f", frequency))Hz, magnitude: \(String(format: "%.6f", magnitudes[i]))")
                }
            }
        }
        
        peaks.sort { $0.magnitude > $1.magnitude }
        NSLog("🎯 PianoNoteDetector: Found \(peaks.count) peaks in frequency range 80-4000Hz")
        
        // Log all peaks if we have a reasonable number
        if peaks.count <= 10 {
            for (index, peak) in peaks.enumerated() {
                NSLog("  Peak \(index + 1): \(String(format: "%.1f", peak.frequency))Hz, magnitude: \(String(format: "%.6f", peak.magnitude))")
            }
        } else {
            // Log just top 5 if too many
            for (index, peak) in peaks.prefix(5).enumerated() {
                NSLog("  Peak \(index + 1): \(String(format: "%.1f", peak.frequency))Hz, magnitude: \(String(format: "%.6f", peak.magnitude))")
            }
        }
        
        // Disable FFT-based note detection for now - autocorrelation is working better
        // let detectedNotes: [DetectedNote] = [] // Array(peaks.prefix(5)).compactMap { frequencyToNote(frequency: $0.frequency, magnitude: $0.magnitude) }
        
        NSLog("🎵 PianoNoteDetector: FFT detection disabled - using autocorrelation only")
        
        // Calculate RMS level for audio visualization with thread safety
        guard !audioBuffer.isEmpty else {
            NSLog("⚠️ Empty audio buffer for RMS calculation")
            return
        }
        
        // Create thread-safe copy of audio buffer for calculations
        let audioBufferCopy = Array(audioBuffer)
        
        // Safer RMS calculation
        var sumOfSquares: Float = 0.0
        for sample in audioBufferCopy {
            sumOfSquares += sample * sample
        }
        let rmsLevel = sqrt(sumOfSquares / Float(audioBufferCopy.count))
        
        Task { @MainActor in
            noteDetector.updateAudioVisualization(level: rmsLevel, sampleCount: audioBufferCopy.count, spectrum: spectrumData, dominantFreq: dominantFrequency)
            noteDetector.updateFrequencyAnalysis(peaks: rawPeaks, threshold: dynamicThreshold, noiseFloor: noiseFloor, maxMag: maxMagnitude, totalMag: totalMagnitude)
            noteDetector.updateRawAudioWaveform(Array(audioBufferCopy.suffix(1024))) // Send last 1024 samples for waveform
            noteDetector.updateSpectrumDisplay(Array(magnitudes[1...])) // Send spectrum without DC component
            
            // Try simple autocorrelation-based pitch detection (like guitar tuners)
            // Use the full buffer for autocorrelation, not just the last part
            let simpleDetectedNotes = detectPitchWithAutocorrelation(audioBufferCopy)
            noteDetector.updateDetectedNotes(simpleDetectedNotes)
        }
    }
    
    private func frequencyToNote(frequency: Double, magnitude: Float) -> DetectedNote? {
        let noteNumber = 12.0 * log2(frequency / 440.0) + 69.0
        let roundedNote = Int(round(noteNumber))
        let cents = (noteNumber - Double(roundedNote)) * 100.0
        let noteName = midiNoteToName(roundedNote)
        
        NSLog("🎼 FrequencyToNote: \(String(format: "%.2f", frequency))Hz → noteNum=\(String(format: "%.2f", noteNumber)), rounded=\(roundedNote), cents=\(String(format: "%.1f", cents)), name=\(noteName)")
        
        guard abs(cents) <= 50.0 else { 
            NSLog("❌ Rejected \(noteName): \(String(format: "%.1f", cents)) cents off (> 50 cent limit)")
            return nil 
        }
        
        NSLog("✅ Accepted \(noteName): \(String(format: "%.2f", frequency))Hz, \(String(format: "%.1f", cents)) cents off")
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
    
    // Simple autocorrelation-based pitch detection (like guitar tuners use)
    private func detectPitchWithAutocorrelation(_ samples: [Float]) -> [DetectedNote] {
        // Create a local copy to avoid threading issues
        let localSamples = Array(samples)
        
        guard localSamples.count > 1024 else { 
            NSLog("⚠️ Not enough samples for autocorrelation: \(localSamples.count)")
            return [] 
        }
        
        // Check if we have any actual audio signal - use safer bounds checking
        guard !localSamples.isEmpty else {
            NSLog("⚠️ Empty samples array")
            return []
        }
        
        // Safer RMS calculation with bounds checking
        var sumOfSquares: Float = 0.0
        for sample in localSamples {
            sumOfSquares += sample * sample
        }
        
        let rmsLevel = sqrt(sumOfSquares / Float(localSamples.count))
        guard rmsLevel > 0.001 else {
            NSLog("⚠️ Audio signal too weak for pitch detection: RMS=\(rmsLevel)")
            return []
        }
        
        let minPeriod = Int(sampleRate / 800.0)  // ~800 Hz max
        let maxPeriod = Int(sampleRate / 80.0)   // ~80 Hz min
        
        guard maxPeriod < localSamples.count / 2 else { 
            NSLog("⚠️ Not enough samples for max period: need \(maxPeriod * 2), have \(localSamples.count)")
            return [] 
        }
        
        var bestPeriod = 0
        var maxCorrelation: Float = 0.0
        
        NSLog("🔍 Autocorrelation search: periods \(minPeriod) to \(maxPeriod), RMS=\(rmsLevel)")
        
        // Optimized autocorrelation with reduced search space
        // Search every 2nd period for speed, then refine around the best match
        let stepSize = 2
        
        // First pass: coarse search with larger steps
        for period in stride(from: minPeriod, through: maxPeriod, by: stepSize) {
            var correlation: Float = 0.0
            let compareLength = min(localSamples.count - period, 256) // Smaller window for speed
            
            // Extra bounds checking
            guard compareLength > 0 && period < localSamples.count else { continue }
            
            for i in 0..<compareLength {
                guard i + period < localSamples.count else { break }
                correlation += localSamples[i] * localSamples[i + period]
            }
            
            // Normalize by signal power
            correlation = correlation / Float(compareLength)
            
            if correlation > maxCorrelation {
                maxCorrelation = correlation
                bestPeriod = period
            }
        }
        
        // Second pass: refine around the best period found (only if we found something)
        if bestPeriod > 0 && maxCorrelation > 0.01 {
            let refinementRange = max(1, stepSize)
            let startPeriod = max(minPeriod, bestPeriod - refinementRange)
            let endPeriod = min(maxPeriod, bestPeriod + refinementRange)
            
            for period in startPeriod...endPeriod {
                var correlation: Float = 0.0
                let compareLength = min(localSamples.count - period, 512) // Larger window for refinement
                
                guard compareLength > 0 && period < localSamples.count else { continue }
                
                for i in 0..<compareLength {
                    guard i + period < localSamples.count else { break }
                    correlation += localSamples[i] * localSamples[i + period]
                }
                
                correlation = correlation / Float(compareLength)
                
                if correlation > maxCorrelation {
                    maxCorrelation = correlation
                    bestPeriod = period
                }
            }
        }
        
        NSLog("🎯 Autocorrelation: best period=\(bestPeriod), correlation=\(maxCorrelation)")
        
        // Lower threshold for testing
        guard maxCorrelation > 0.005 && bestPeriod > 0 else {  // Lower threshold - we're seeing 0.044 correlations 
            NSLog("⚠️ Weak correlation (\(maxCorrelation)) - no pitch detected")
            return [] 
        }
        
        let frequency = sampleRate / Double(bestPeriod)
        NSLog("🎵 Detected frequency: \(frequency) Hz")
        
        guard let note = frequencyToNote(frequency: frequency, magnitude: maxCorrelation) else { return [] }
        
        return [note]
    }
}

import SwiftUI

extension Color {
    static let mint = Color(red: 0.0, green: 1.0, blue: 0.8)
} 