import AudioToolbox
import Cast
import Foundation
import IDisposable
import Time

public enum AQPlayerBehavior: Sendable {
	case infiniteStream
	case finite
}

public enum AQPlayerState: Sendable {
	case stopped
	case paused(Bool)
	case playing
}

public enum AQPlayerEvent: Sendable {
	case playTime(Float64, Time)
}

public enum AQPlayerChange: Sendable {
	case propertyValue(AQPropertyValue)
	case state(AQPlayerState)
	case event(AQPlayerEvent)
}

@available(iOS 13.0.0, *)
@available(macOS 10.15, *)
public actor AQPlayer: IAsyncDisposable, Sendable {
	public let propertyValueStream: AsyncStream<AQPlayerChange>
	private let propertyValueContinuation: AsyncStream<AQPlayerChange>.Continuation
	private var runningObserverTask: Task<Void, Error>?

	var queue: AudioQueueRef?
	var currentBuffer: AudioQueueBufferRef?
	var currentPosition: UInt32 = 0
	var packetDescriptions: [AudioStreamPacketDescription] = [AudioStreamPacketDescription]()
	var genBuffer: ((UInt32) throws -> AudioQueueBufferRef)?

	var playing: Bool = false
	var startTime: AudioTimeStamp?
	var buffered: UInt32 = 0
	var minimumQueues: UInt32 = 3

	var timeline: AudioQueueTimelineRef?
	var queueStartTime: Time?

	let behavior: AQPlayerBehavior

	public init(_ behavior: AQPlayerBehavior = .infiniteStream) {
		self.behavior = behavior

		let (stream, continuation):
			(AsyncStream<AQPlayerChange>, AsyncStream<AQPlayerChange>.Continuation) =
				createStreamAndContinuation()
		self.propertyValueContinuation = continuation
		self.propertyValueStream = stream
	}

	public func play(_ audio: AudioData) {
		let startTime = audio.startTime
		if self.startTime == nil && startTime != nil {
			self.startTime = startTime
		}

		audio.data.withUnsafeBytes {
			if audio.packetDescriptions?.count ?? 0 > 0 {
				self.fillBufferWithPackets(
					data: $0.baseAddress!, length: UInt32($0.count),
					packetDescriptions: audio.packetDescriptions!
				)
			} else {
				self.fillBufferWithRaw(data: $0.baseAddress!, length: UInt32($0.count))
			}
		}
	}

	public func dispose() {
		guard let queue = self.queue else {
			return
		}

		AudioQueueStop(queue, true)
		AudioQueueDispose(queue, true)

		self.runningObserverTask?.cancel()

	}

	public func initialize(
		asbd: UnsafeMutablePointer<AudioStreamBasicDescription>, cookieData: Data?
	) throws {
		let (queue, genBuffer) = try! AQFactory.createDefaultOutputQueue(propertyData: asbd) {
			if self.buffered > 0 { self.buffered -= 1 }

			self.updateTimeline()

			switch self.behavior {
			case .infiniteStream:
				// Auto-pause before we run out of buffer if we are streaming
				// Signal that we need more buffering time
				if self.buffered <= 1 && self.playing {
					try! self.pause()
					self.minimumQueues += 1
				}
			case .finite:
				if self.buffered < 1 && self.playing {
					try! self.pause()
				}
			}
		}

		self.queue = queue
		self.genBuffer = genBuffer

		if cookieData != nil {
			let result = cookieData!.withUnsafeBytes {
				AudioQueueSetProperty(
					self.queue!, kAudioQueueProperty_MagicCookie, $0.baseAddress!,
					UInt32(cookieData!.count))
			}
			if result != 0 {
				throw AStreamError.coreAudioError(code: result, message: "AQPlayer: Set Cookie")
			}
		}

		_ = AudioQueueSetParameter(self.queue!, kAudioQueueParam_Volume, 1.0)

		let timelineRef = UnsafeMutablePointer<AudioQueueTimelineRef?>.allocate(capacity: 1)
		_ = AudioQueueCreateTimeline(queue, timelineRef)
		self.timeline = timelineRef.pointee

		self.runningObserverTask = Task {
			for await x in AQPropertyUtility.observe(queue, .isRunning) {
				self.propertyValueContinuation.yield(.propertyValue(x))
			}
		}
	}

	func updateTimeline() {
		guard let timeline = self.timeline, let queue = self.queue else {
			return
		}

		let stamp = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
		let discontinuity = UnsafeMutablePointer<DarwinBoolean>.allocate(capacity: 1)
		_ = AudioQueueGetCurrentTime(queue, timeline, stamp, discontinuity)

		let ts = stamp.pointee
		let hostTime = Time.fromSystemTimeStamp(ts.mHostTime)
		let relative = hostTime - self.queueStartTime!
		self.propertyValueContinuation.yield(.event(.playTime(ts.mSampleTime, relative)))
	}

	func fillBufferWithRaw(data: UnsafeRawPointer, length: UInt32) {
		self.currentBuffer = try! self.genBuffer!(length)
		memcpy(
			self.currentBuffer!.pointee.mAudioData.advanced(by: Int(self.currentPosition)),
			data, Int(length))
		self.currentPosition += length

		try! self.advanceBuffer()
	}

	func fillBufferWithPackets(
		data: UnsafeRawPointer, length: UInt32,
		packetDescriptions: [AudioStreamPacketDescription]
	) {
		self.currentBuffer = try! self.genBuffer!(length)
		for packetDescription in packetDescriptions {
			let packetOffset = packetDescription.mStartOffset
			let packetSize = packetDescription.mDataByteSize

			let src = data.advanced(by: Int(packetOffset))
			let dest = self.currentBuffer!.pointee.mAudioData.advanced(
				by: Int(self.currentPosition))

			memcpy(dest, src, Int(packetSize))

			let pd = AudioStreamPacketDescription(
				mStartOffset: Int64(self.currentPosition),
				mVariableFramesInPacket: packetDescription.mVariableFramesInPacket,
				mDataByteSize: packetDescription.mDataByteSize)
			self.packetDescriptions.append(pd)
			self.currentPosition += packetDescription.mDataByteSize
		}
		try! self.advanceBuffer()
	}

	func advanceBuffer() throws {
		self.currentBuffer!.pointee.mAudioDataByteSize = self.currentPosition

		var pdc: UInt32 = 0
		var pd: SendableShim<UnsafeMutablePointer<AudioStreamPacketDescription>?> = SendableShim(
			nil)
		if self.packetDescriptions.first?.mDataByteSize ?? 0 > 0 {
			self.packetDescriptions.withUnsafeBufferPointer { (packetDescriptions) in
				let descriptionByteSize =
					self.packetDescriptions.count * MemoryLayout<AudioStreamPacketDescription>.size
				let copiedDescriptions = malloc(descriptionByteSize)
				memcpy(copiedDescriptions, packetDescriptions.baseAddress, descriptionByteSize)

				pd = SendableShim(cast(copiedDescriptions!))
				pdc = UInt32(self.packetDescriptions.count)
			}
		}

		let result = AudioQueueEnqueueBuffer(self.queue!, self.currentBuffer!, pdc, pd.value)
		if result != 0 {
			throw AStreamError.coreAudioError(code: result, message: "AQPlayer: Enqueue Buffer")
		}

		self.currentBuffer = nil
		self.packetDescriptions = [AudioStreamPacketDescription]()
		self.currentPosition = 0

		self.buffered += 1
		if !self.playing && self.buffered > self.minimumQueues {
			try! self.prime()
			try! self.play()
		}
	}

	func prime() throws {
		let primed = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		let primeResult = AudioQueuePrime(self.queue!, 0, primed)
		if primeResult != 0 {
			throw AStreamError.coreAudioError(
				code: primeResult, message: "AQPlayer: Failed to prime")
		}
		primed.deallocate()
	}

	public func play() throws {
		if self.playing {
			return
		}

		self.queueStartTime = Time.now
		let playResult = AudioQueueStart(self.queue!, nil)
		if playResult != 0 {
			throw AStreamError.coreAudioError(
				code: playResult, message: "AQPlayer: Failed to start playing")
		}
		self.startTime = nil
		self.playing = true
		self.propertyValueContinuation.yield(.state(.playing))
	}

	public func pause() throws {
		if !self.playing {
			return
		}

		let pauseResult = AudioQueuePause(self.queue!)
		if pauseResult != 0 {
			throw AStreamError.coreAudioError(
				code: pauseResult, message: "AQPlayer: Failed to pause")
		}
		self.playing = false
		self.propertyValueContinuation.yield(.state(.paused(false)))
	}
}

class MutableSendableShim<T>: @unchecked Sendable {
	public var value: T
	public init(_ value: T) {
		self.value = value
	}
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
func createStreamAndContinuation<T>() -> (AsyncStream<T>, AsyncStream<T>.Continuation) {
	let continuationShim = MutableSendableShim<AsyncStream<T>.Continuation?>(nil)
	let stream = AsyncStream<T> { continuation in
		continuationShim.value = continuation
	}
	return (stream, continuationShim.value!)
}
