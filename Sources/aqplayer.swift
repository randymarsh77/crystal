import AudioToolbox
import Foundation
import Cast
import Time

public class AQPlayer
{
	public var playPackets: OnPacketsDelegate?

	var queue: AudioQueueRef?
	var currentBuffer: AudioQueueBufferRef?
	var currentPosition: UInt32 = 0
	var packetDescriptions: Array<AudioStreamPacketDescription> = Array<AudioStreamPacketDescription>()
	var genBuffer: ((UInt32) throws -> AudioQueueBufferRef)?

	var playing: Bool = false
	var startTime: UnsafePointer<AudioTimeStamp>? = nil
	var buffered: UInt32 = 0
	var minimumQueues: UInt32 = 3

	public init()
	{
		self.playPackets = { (numBytes: UInt32, numPackets: UInt32, inputData: UnsafeRawPointer, packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?, startTime: UnsafePointer<AudioTimeStamp>?) in

			if self.startTime == nil && startTime != nil {
				self.startTime = startTime
			}

			if (packetDescriptions != nil)
			{
				self.fillBufferWithPackets(data: inputData, length: numBytes, packetDescriptions: packetDescriptions!, numPackets: numPackets)
			}
			else
			{
				self.fillBufferWithRaw(data: inputData, length: numBytes)
			}
		}
	}

	public func initialize(asbd: UnsafeMutablePointer<AudioStreamBasicDescription>, cookieData: Data?) throws -> Void
	{
		let (queue, genBuffer) = try! AQFactory.CreateDefaultOutputQueue(propertyData: asbd)
		{
			if self.buffered > 0 { self.buffered -= 1 }
			if self.buffered <= 1 && self.playing
			{
				AudioQueuePause(self.queue!)
				self.playing = false
				self.minimumQueues += 1
			}
		}

		self.queue = queue
		self.genBuffer = genBuffer

		if cookieData != nil
		{
			let result = cookieData!.withUnsafeBytes() { (bytes: UnsafePointer) -> OSStatus in
				AudioQueueSetProperty(self.queue!, kAudioQueueProperty_MagicCookie, bytes, UInt32(cookieData!.count))
			}
			if (result != 0)
			{
				throw AStreamError.CoreAudioError(code: result, message: "AQPlayer: Set Cookie")
			}
		}

		_ = AudioQueueSetParameter(self.queue!, kAudioQueueParam_Volume, 1.0)
	}

	func fillBufferWithRaw(data: UnsafeRawPointer, length: UInt32) -> Void
	{
		self.currentBuffer = try! self.genBuffer!(length)
		memcpy(self.currentBuffer!.pointee.mAudioData.advanced(by: Int(self.currentPosition)), data, Int(length))
		self.currentPosition += length

		try! self.advanceBuffer()
	}

	func fillBufferWithPackets(data: UnsafeRawPointer, length: UInt32, packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>, numPackets: UInt32) -> Void
	{
		self.currentBuffer = try! self.genBuffer!(length)
		for packetDescription in UnsafeBufferPointer<AudioStreamPacketDescription>(start: UnsafePointer(packetDescriptions), count: Int(numPackets))
		{
			let packetOffset = packetDescription.mStartOffset
			let packetSize = packetDescription.mDataByteSize

			memcpy(self.currentBuffer!.pointee.mAudioData.advanced(by: Int(self.currentPosition)), data.advanced(by: Int(packetOffset)), Int(packetSize))

			let pd = AudioStreamPacketDescription(mStartOffset: Int64(self.currentPosition), mVariableFramesInPacket: packetDescription.mVariableFramesInPacket, mDataByteSize: packetDescription.mDataByteSize)
			self.packetDescriptions.append(pd)
			self.currentPosition += packetDescription.mDataByteSize
		}
		try! self.advanceBuffer()
	}

	func advanceBuffer() throws -> Void
	{
		var pd: UnsafeMutablePointer<AudioStreamPacketDescription>? = nil
		let pdc = UInt32(self.packetDescriptions.count)
		self.currentBuffer!.pointee.mAudioDataByteSize = self.currentPosition
		self.packetDescriptions.withUnsafeBufferPointer() { (packetDescriptions) in
			let descriptionByteSize = self.packetDescriptions.count * MemoryLayout<AudioStreamPacketDescription>.size
			let copiedDescriptions = malloc(descriptionByteSize)
			memcpy(copiedDescriptions, packetDescriptions.baseAddress, descriptionByteSize)

			pd = Cast(copiedDescriptions)
		}

		let result = AudioQueueEnqueueBuffer(self.queue!, self.currentBuffer!, pdc, pd)
		if (result != 0)
		{
			throw AStreamError.CoreAudioError(code: result, message: "AQPlayer: Enqueue Buffer")
		}

		self.currentBuffer = nil
		self.packetDescriptions = Array<AudioStreamPacketDescription>()
		self.currentPosition = 0

		self.buffered += 1
		if (!self.playing && self.buffered > self.minimumQueues)
		{
			DispatchQueue.main.async
			{
				if (!self.playing && self.buffered > self.minimumQueues)
				{
					self.playing = true

					try! self.prime()
					try! self.play()
				}
			}
		}
	}

	func prime() throws
	{
		let primed = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		let primeResult = AudioQueuePrime(self.queue!, 0, primed)
		if (primeResult != 0)
		{
			throw AStreamError.CoreAudioError(code: primeResult, message: "AQPlayer: Failed to prime")
		}
	}

	func play() throws
	{
		print("CurrentHost: ", Time.ConvertToTimeStamp(Time.Current()))
		let playResult = AudioQueueStart(self.queue!, self.startTime)
		if (playResult != 0)
		{
			throw AStreamError.CoreAudioError(code: playResult, message: "AQPlayer: Failed to start playing")
		}
		self.startTime = nil
	}
}
