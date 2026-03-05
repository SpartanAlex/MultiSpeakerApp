import Foundation

/// Accumulates raw PCM Int16 audio chunks in memory and can flush them to a
/// WAV file on demand. Thread-safe — chunks may be appended from the audio
/// capture thread while the main thread calls `reset()` or `writeWAV(to:)`.
final class AudioFileWriter {

    // MARK: - WAV parameters (must match AudioCaptureEngine output)

    private let sampleRate  = 16_000
    private let channels    = 1
    private let bitsPerSample = 16

    // MARK: - State

    private var chunks: [Data] = []
    private let lock = NSLock()

    // MARK: - Public API

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        chunks.append(chunk)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        chunks.removeAll()
    }

    /// Total bytes of PCM audio accumulated so far.
    var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.reduce(0) { $0 + $1.count }
    }

    /// Duration of accumulated audio in seconds.
    var duration: TimeInterval {
        let bytesPerSample = bitsPerSample / 8
        let bytesPerSecond = sampleRate * channels * bytesPerSample
        return TimeInterval(byteCount) / TimeInterval(bytesPerSecond)
    }

    /// Combines all accumulated chunks and writes them as a valid WAV file.
    /// Safe to call from any thread.
    func writeWAV(to url: URL) throws {
        lock.lock()
        let snapshot = chunks
        lock.unlock()

        let pcmData = snapshot.reduce(Data(), +)
        let wavData = makeWAVHeader(pcmByteCount: pcmData.count) + pcmData
        try wavData.write(to: url, options: .atomic)
    }

    // MARK: - WAV header construction

    private func makeWAVHeader(pcmByteCount: Int) -> Data {
        var header = Data()

        let byteRate   = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        func append(_ v: UInt32) {
            var le = v.littleEndian
            header.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        func append(_ v: UInt16) {
            var le = v.littleEndian
            header.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }

        // RIFF chunk descriptor
        header.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + pcmByteCount))       // ChunkSize
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        append(UInt32(16))                      // Subchunk1Size (PCM)
        append(UInt16(1))                       // AudioFormat (PCM = 1)
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(byteRate))
        append(UInt16(blockAlign))
        append(UInt16(bitsPerSample))

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        append(UInt32(pcmByteCount))

        return header  // 44 bytes total
    }
}
