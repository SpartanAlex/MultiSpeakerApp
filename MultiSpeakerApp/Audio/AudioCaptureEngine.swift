import AVFoundation

/// Captures microphone audio, resamples to 16 kHz PCM Int16 mono, and emits
/// fixed-size chunks suitable for streaming to AssemblyAI.
///
/// `onAudioChunk` is called on a background thread — callers must synchronise
/// any shared state they access inside the closure.
final class AudioCaptureEngine {

    // MARK: - Configuration

    /// Target sample rate required by AssemblyAI's streaming API.
    private let targetSampleRate: Double = 16_000
    /// 100 ms of audio at 16 kHz = 1600 samples = 3200 bytes (Int16).
    private let chunkSampleCount = 1_600

    // MARK: - State

    private(set) var isRunning = false

    /// Called with each complete PCM Int16 chunk (little-endian, mono, 16 kHz).
    var onAudioChunk: ((Data) -> Void)?

    // MARK: - Private

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    /// Samples that didn't fill a complete chunk yet; carried to next callback.
    private var leftoverSamples: [Int16] = []

    // MARK: - Public API

    func start() throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        // Hardware format (e.g. 44.1 kHz, Float32, stereo on most Macs).
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.outputFormatCreationFailed
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        self.converter = conv

        // Request ~100 ms worth of frames from the hardware at its native rate.
        let tapFrameCount = AVAudioFrameCount(inputFormat.sampleRate * 0.1)

        inputNode.installTap(onBus: 0, bufferSize: tapFrameCount, format: inputFormat) {
            [weak self] buffer, _ in
            self?.process(inputBuffer: buffer, converter: conv, outputFormat: outputFormat)
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        leftoverSamples.removeAll()
        converter = nil
        isRunning = false
    }

    // MARK: - Processing

    private func process(
        inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        // Calculate how many output frames the resampled audio will occupy.
        let ratio = targetSampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            (Double(inputBuffer.frameLength) * ratio).rounded(.up) + 1
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else { return }

        var conversionError: NSError?
        var inputConsumed = false

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error = conversionError {
            print("[AudioCaptureEngine] Conversion error: \(error.localizedDescription)")
            return
        }

        guard let int16Data = outputBuffer.int16ChannelData else { return }
        let frameCount = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: int16Data[0], count: frameCount))

        emit(samples: samples)
    }

    /// Accumulates samples across callbacks and emits fixed-size chunks.
    private func emit(samples: [Int16]) {
        var pool = leftoverSamples + samples

        while pool.count >= chunkSampleCount {
            let chunk = Array(pool.prefix(chunkSampleCount))
            pool.removeFirst(chunkSampleCount)

            // Pack Int16 array as little-endian bytes.
            let data = chunk.withUnsafeBytes { Data($0) }
            onAudioChunk?(data)
        }

        leftoverSamples = pool
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case outputFormatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .outputFormatCreationFailed:
            return "Failed to create 16 kHz Int16 mono output format."
        case .converterCreationFailed:
            return "Failed to create AVAudioConverter from hardware format to 16 kHz Int16 mono."
        }
    }
}
