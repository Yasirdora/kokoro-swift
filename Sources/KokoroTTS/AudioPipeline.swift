import AVFoundation

/// Owns the AVAudioEngine/player node and serializes everything that touches
/// them. `AVAudioPlayerNode` scheduling is thread-safe, but ordering and
/// progress accounting are our job, so all entry points funnel through `lock`.
///
/// One engine is created per sample rate and lives for the process — engine
/// start/stop churn races the render thread and is a known crash source.
public final class AudioPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var scheduledSamples = 0
    private var generation = 0

    /// Fired on the main thread when the last scheduled buffer finishes.
    /// Bumped per stop/restart, so a stale completion never fires.
    public var onPlaybackFinished: (@MainActor () -> Void)?

    public init() {}

    private let gapSamples = Int(0.09 * 24000)  // 90 ms pause between sentences

    // MARK: - Configuration

    public func configure(sampleRate: Int) {
        let rate = Double(sampleRate)
        guard rate > 0 else { return }

        lock.lock()
        if let format, abs(format.sampleRate - rate) < 1 {
            lock.unlock()
            return  // already configured for this rate
        }
        // Detach the old engine under the lock, but stop/start it OUTSIDE:
        // engine.stop() and engine.start() synchronously drain the audio
        // queue, and pending buffer-completion handlers take this lock — so
        // holding it across those calls is a textbook deadlock.
        let oldEngine = audioEngine
        audioEngine = nil
        playerNode = nil
        self.format = nil
        scheduledSamples = 0
        lock.unlock()

        oldEngine.map { if $0.isRunning { $0.stop() } }

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        guard let newFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false
        ) else { return }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: newFormat)
        do {
            try engine.start()
        } catch {
            return
        }

        lock.lock()
        audioEngine = engine
        playerNode = node
        format = newFormat
        lock.unlock()
    }

    // MARK: - Queueing (called from the synthesis chunk callback)

    /// Enqueue one chunk for gapless sequential playback. `isLast` attaches
    /// the completion handler that fires `onPlaybackFinished`.
    public func enqueue(_ samples: [Float], isLast: Bool) {
        guard !samples.isEmpty else { return }
        lock.lock()
        guard let node = playerNode, let format else { lock.unlock(); return }
        let myGeneration = generation
        var frames = samples
        if !isLast { frames.append(contentsOf: [Float](repeating: 0, count: gapSamples)) }
        scheduledSamples += frames.count
        lock.unlock()

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frames.count)
        ) else { return }
        buffer.frameLength = buffer.frameCapacity
        frames.withUnsafeBufferPointer { src in
            if let dst = buffer.floatChannelData?[0], let base = src.baseAddress {
                dst.update(from: base, count: frames.count)
            }
        }

        if isLast {
            node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                guard let self, self.isCurrentGeneration(myGeneration) else { return }
                Task { @MainActor in
                    self.onPlaybackFinished?()
                }
            }
        } else {
            node.scheduleBuffer(buffer, at: nil, options: [])
        }
        if !node.isPlaying { node.play() }
    }

    /// Synchronous — safe to call from audio-completion callbacks.
    private func isCurrentGeneration(_ g: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == g
    }

    // MARK: - Transport

    public func stop() {
        // Bump the generation and grab the node under the lock, then stop the
        // node WITHOUT the lock: -[AVAudioPlayerNode stop] synchronously waits
        // for the audio queue, and pending buffer-completion handlers on that
        // queue take this lock (isCurrentGeneration). Holding it here deadlocks.
        lock.lock()
        generation &+= 1
        let node = playerNode
        scheduledSamples = 0
        lock.unlock()
        node?.stop()
    }

    // MARK: - Progress

    /// (playedSeconds, scheduledSeconds); nil when nothing is queued/playing.
    public func progress() -> (played: Double, scheduled: Double)? {
        lock.lock()
        guard let node = playerNode, node.isPlaying, scheduledSamples > 0 else {
            lock.unlock(); return nil
        }
        let total = scheduledSamples
        lock.unlock()
        guard let last = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: last)
        else { return nil }
        let rate = playerTime.sampleRate
        guard rate > 0 else { return nil }
        return (
            played: Double(playerTime.sampleTime) / rate,
            scheduled: Double(total) / rate
        )
    }

    deinit {
        lock.lock()
        let engine = audioEngine
        audioEngine = nil
        playerNode = nil
        format = nil
        lock.unlock()
        engine.map { if $0.isRunning { $0.stop() } }
    }
}
