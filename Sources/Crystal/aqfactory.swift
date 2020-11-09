import AudioToolbox
import Foundation
import Cast
import Streams

func aqInputCallback(userData: UnsafeMutableRawPointer?, queue: AudioQueueRef, bufferPointer: AudioQueueBufferRef, ts: UnsafePointer<AudioTimeStamp>, pdc: UInt32, pd: UnsafePointer<AudioStreamPacketDescription>?) -> Void
{
	let buffer = bufferPointer.pointee
	let data = Data(bytes: buffer.mAudioData, count: Int(buffer.mAudioDataByteSize))
	let callbackData = AQInputData(data: data, ts: ts, pdc: pdc, pd: pd)

	let userDataPrime: UnsafePointer<AQInputUserData>? = Cast(userData)
	userDataPrime!.pointee.callback(callbackData)

	AudioQueueEnqueueBuffer(queue, bufferPointer, 0, nil)
}

func aqOutputCallback(userData: UnsafeMutableRawPointer?, _: AudioQueueRef, buffer: AudioQueueBufferRef) -> Void
{
	let userDataPrime: UnsafePointer<AQOutputUserData>? = Cast(userData)
	userDataPrime!.pointee.callback(buffer)
}

struct AQInputUserData
{
	var callback: (_ data: AQInputData) -> Void
}

struct AQOutputUserData
{
	var callback: (_ buffer: AudioQueueBufferRef) -> Void
}

public struct AQInputData
{
	public var data: Data
	public var ts: UnsafePointer<AudioTimeStamp>?
	public var pdc: UInt32
	public var pd: UnsafePointer<AudioStreamPacketDescription>?
}

public class AQFactory
{
	public static func CreateDefaultInputQueue(propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>) throws -> (AudioQueueRef, ReadableStream<Data>)
	{
		let stream = Streams.Stream<Data>()
		let queue = try CreateDefaultInputQueue(propertyData: propertyData) { data in
			if (data.data.count != 0) {
				stream.publish(data.data)
			}
		}
		return (queue, ReadableStream(stream))
	}

	public static func CreateDefaultInputQueue(propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>, callback: @escaping (_ data: AQInputData) -> Void) throws -> AudioQueueRef
	{
		let userData = UnsafeMutablePointer<AQInputUserData>.allocate(capacity: 1)
		userData.initialize(to: AQInputUserData(callback: callback))

		let queue = UnsafeMutablePointer<AudioQueueRef?>.allocate(capacity: 1)
		let createQueueResult = AudioQueueNewInput(propertyData, aqInputCallback, userData, nil, nil, 0, queue)
		if (createQueueResult != 0) { throw AStreamError.CoreAudioError(code: createQueueResult, message: "Failed to create input queue") }

		let propertyDataSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		propertyDataSize.initialize(to: UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

		let getQueueFormatResult = AudioQueueGetProperty(
			queue.pointee!,
			kAudioConverterCurrentOutputStreamDescription,
			propertyData,
			propertyDataSize)
		if (getQueueFormatResult != 0) { throw AStreamError.CoreAudioError(code: getQueueFormatResult, message: "Failed to get queue's format") }

		let bufferSize = Utility.ComputeBufferSize(formatPointer: propertyData, queue: queue.pointee!, seconds: 0.1)
		let isVBR = propertyData.pointee.mBytesPerPacket == 0

		for _ in 1...3
		{
			let buffer = UnsafeMutablePointer<AudioQueueBufferRef?>.allocate(capacity: 1)
			let allocateBufferResult = isVBR ?
				AudioQueueAllocateBufferWithPacketDescriptions(queue.pointee!, bufferSize, 512, buffer) :
				AudioQueueAllocateBuffer(queue.pointee!, bufferSize, buffer)
			if (allocateBufferResult != 0) { throw AStreamError.CoreAudioError(code: allocateBufferResult, message: "Failed to allocate buffer") }

			let enqueueBufferResult = AudioQueueEnqueueBuffer(queue.pointee!, buffer.pointee!, 0, nil)
			if (enqueueBufferResult != 0) { throw AStreamError.CoreAudioError(code: enqueueBufferResult, message: "Failed to enqueue buffer") }
		}

		return queue.pointee!
	}

	public static func CreateDefaultOutputQueue(
		propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>,
		onBufferFinishedPlaying: @escaping () -> ()
		) throws -> (AudioQueueRef, (UInt32) throws -> AudioQueueBufferRef)
	{
		let userData = UnsafeMutablePointer<AQOutputUserData>.allocate(capacity: 1)
		let queue = UnsafeMutablePointer<AudioQueueRef?>.allocate(capacity: 1)
		let createQueueResult = AudioQueueNewOutput(propertyData, aqOutputCallback, userData, nil, nil, 0, queue)
		if (createQueueResult != 0) { throw AStreamError.CoreAudioError(code: createQueueResult, message: "Failed to create output queue") }

		userData.initialize(to: AQOutputUserData() { (buffer: AudioQueueBufferRef) in
			onBufferFinishedPlaying()
			AudioQueueFreeBuffer(queue.pointee!, buffer)
		})

		return (queue.pointee!, { (size) in try! genBuffer(queue: queue.pointee!, size: size) })
	}
}

func genBuffer(queue: AudioQueueRef, size: UInt32) throws -> AudioQueueBufferRef
{
	let buffer = UnsafeMutablePointer<AudioQueueBufferRef?>.allocate(capacity: 1)
	let allocateBufferResult = AudioQueueAllocateBuffer(queue, size, buffer)
	if (allocateBufferResult != 0) { throw AStreamError.CoreAudioError(code: allocateBufferResult, message: "Failed to allocate buffer") }
	return buffer.pointee!
}
