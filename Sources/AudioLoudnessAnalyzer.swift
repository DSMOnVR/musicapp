import AVFoundation
import Foundation

enum AudioLoudnessAnalyzer {
    /// Measures average PCM energy and attenuates unusually loud tracks.
    /// AVPlayer's volume is capped at 1, so quiet tracks are never amplified.
    static func playerGain(for url: URL) -> Float {
        guard let file = try? AVAudioFile(forReading: url) else { return 1 }
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let channels = buffer.floatChannelData else { return 1 }

        var sumSquares = 0.0
        var sampleCount = 0
        do {
            while file.framePosition < file.length {
                try file.read(into: buffer)
                let frames = Int(buffer.frameLength)
                if frames == 0 { break }
                for channel in 0..<Int(format.channelCount) {
                    let samples = channels[channel]
                    for frame in 0..<frames {
                        let sample = Double(samples[frame])
                        sumSquares += sample * sample
                    }
                    sampleCount += frames
                }
            }
        } catch {
            return 1
        }

        guard sampleCount > 0 else { return 1 }
        let rms = sqrt(sumSquares / Double(sampleCount))
        guard rms.isFinite, rms > 0.0001 else { return 1 }
        let targetRMS = 0.16
        return Float(max(0.25, min(1.0, targetRMS / rms)))
    }
}
