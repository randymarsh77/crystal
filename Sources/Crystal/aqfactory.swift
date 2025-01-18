import AudioToolbox
import Cancellation
import Cast
import Foundation
import Scope

func aqInputCallback(
	userData: UnsafeMutableRawPointer?, queue: AudioQueueRef, bufferPointer: AudioQueueBufferRef,
	ts: UnsafePointer<AudioTimeStamp>, pdc: UInt32, pd: UnsafePointer<AudioStreamPacketDescription>?
) {
	let buffer = bufferPointer.pointee
	let data = Data(bytes: buffer.mAudioData, count: Int(buffer.mAudioDataByteSize))
	let callbackData = AQInputData(data: data, ts: ts, pdc: pdc, pd: pd)

	let userDataPrime: UnsafePointer<AQInputUserData>? = cast(userData)
	userDataPrime!.pointee.callback(callbackData)

	AudioQueueEnqueueBuffer(queue, bufferPointer, 0, nil)
}

func aqOutputCallback(
	userData: UnsafeMutableRawPointer?, _: AudioQueueRef, buffer: AudioQueueBufferRef
) {
	let userDataPrime: UnsafePointer<AQOutputUserData>? = cast(userData)
	userDataPrime!.pointee.callback(buffer)
}

struct AQInputUserData {
	var callback: (_ data: AQInputData) -> Void
}

struct AQOutputUserData {
	var callback: (_ buffer: AudioQueueBufferRef) -> Void
}

public struct AQInputData {
	public var data: Data
	public var ts: UnsafePointer<AudioTimeStamp>?
	public var pdc: UInt32
	public var pd: UnsafePointer<AudioStreamPacketDescription>?
}

struct SendableQueue: @unchecked Sendable {
	public let queue: AudioQueueRef
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public class AQFactory {
	public static func createDefaultInputQueue(
		propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>
	) -> (Scope, AsyncStream<AudioData>) {
		let cts = CancellationTokenSource()
		let scope = Scope { cts.cancel() }
		return (
			scope,
			AsyncStream<AudioData> { continuation in
				let maybeQueue = try? createDefaultInputQueue(propertyData: propertyData) {
					aqInputData in
					if aqInputData.data.count != 0 {
						let audioData = AudioData(
							streamDescription: propertyData.pointee, packetDescriptions: nil,
							data: aqInputData.data,
							startTime: aqInputData.ts?.pointee)
						continuation.yield(audioData)
					}
				}
				if let queue = maybeQueue {
					let sendable = SendableQueue(queue: queue)
					let observation = try! cts.token.register {
						continuation.finish()
					}
					continuation.onTermination = { _ in
						AudioQueueStop(sendable.queue, false)
						observation.dispose()
						cts.dispose()
					}
					AudioQueueStart(queue, nil)
				} else {
					continuation.finish()
				}
			}
		)
	}

	public static func createDefaultInputQueue(
		propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>,
		callback: @escaping (_ data: AQInputData) -> Void
	) throws -> AudioQueueRef {
		let userData = UnsafeMutablePointer<AQInputUserData>.allocate(capacity: 1)
		userData.initialize(to: AQInputUserData(callback: callback))

		let queue = UnsafeMutablePointer<AudioQueueRef?>.allocate(capacity: 1)
		let createQueueResult = AudioQueueNewInput(
			propertyData, aqInputCallback, userData, nil, nil, 0, queue)
		if createQueueResult != 0 {
			throw AStreamError.coreAudioError(
				code: createQueueResult, message: "Failed to create input queue")
		}

		let propertyDataSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		propertyDataSize.initialize(to: UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

		let getQueueFormatResult = AudioQueueGetProperty(
			queue.pointee!,
			kAudioConverterCurrentOutputStreamDescription,
			propertyData,
			propertyDataSize)
		if getQueueFormatResult != 0 {
			throw AStreamError.coreAudioError(
				code: getQueueFormatResult, message: "Failed to get queue's format")
		}

		let bufferSize = Utility.computeBufferSize(
			formatPointer: propertyData, queue: queue.pointee!, seconds: 0.1)
		let isVBR = propertyData.pointee.mBytesPerPacket == 0

		for _ in 1...3 {
			let buffer = UnsafeMutablePointer<AudioQueueBufferRef?>.allocate(capacity: 1)
			let allocateBufferResult =
				isVBR
				? AudioQueueAllocateBufferWithPacketDescriptions(
					queue.pointee!, bufferSize, 512, buffer)
				: AudioQueueAllocateBuffer(queue.pointee!, bufferSize, buffer)
			if allocateBufferResult != 0 {
				throw AStreamError.coreAudioError(
					code: allocateBufferResult, message: "Failed to allocate buffer")
			}

			let enqueueBufferResult = AudioQueueEnqueueBuffer(
				queue.pointee!, buffer.pointee!, 0, nil)
			if enqueueBufferResult != 0 {
				throw AStreamError.coreAudioError(
					code: enqueueBufferResult, message: "Failed to enqueue buffer")
			}
		}

		return queue.pointee!
	}

	public static func createDefaultOutputQueue(
		propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>,
		onBufferFinishedPlaying: @escaping () -> Void
	) throws -> (AudioQueueRef, (UInt32) throws -> AudioQueueBufferRef) {
		let userData = UnsafeMutablePointer<AQOutputUserData>.allocate(capacity: 1)
		let queue = UnsafeMutablePointer<AudioQueueRef?>.allocate(capacity: 1)
		let createQueueResult = AudioQueueNewOutput(
			propertyData, aqOutputCallback, userData, nil, nil, 0, queue)
		if createQueueResult != 0 {
			throw AStreamError.coreAudioError(
				code: createQueueResult, message: "Failed to create output queue")
		}

		userData.initialize(
			to: AQOutputUserData { (buffer: AudioQueueBufferRef) in
				onBufferFinishedPlaying()
				AudioQueueFreeBuffer(queue.pointee!, buffer)
			})

		return (queue.pointee!, { (size) in try! genBuffer(queue: queue.pointee!, size: size) })
	}
}

func genBuffer(queue: AudioQueueRef, size: UInt32) throws -> AudioQueueBufferRef {
	let buffer = UnsafeMutablePointer<AudioQueueBufferRef?>.allocate(capacity: 1)
	let allocateBufferResult = AudioQueueAllocateBuffer(queue, size, buffer)
	if allocateBufferResult != 0 {
		throw AStreamError.coreAudioError(
			code: allocateBufferResult, message: "Failed to allocate buffer")
	}
	return buffer.pointee!
}
