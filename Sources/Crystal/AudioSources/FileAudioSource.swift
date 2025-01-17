import AVFoundation
import AudioToolbox
import Cancellation
import Foundation
import IDisposable
import Scope

@available(iOS 13.0.0, *)
@available(macOS 10.15, *)
public final class FileAudioSource: IAudioSource, Sendable {
	public init(_ file: URL) {
		self.file = file
	}

	public func start() async -> AsyncStream<AudioData> {
		return AsyncStream<AudioData> { continuation in
			DispatchQueue.global().async {
				var fileIdRef: AudioFileID?
				let openErr = AudioFileOpenURL(
					self.file as CFURL, AudioFilePermissions.readPermission, 0, &fileIdRef)
				guard openErr == noErr else {
					print("Failed to open file: \(openErr)")
					continuation.finish()
					return
				}
				let fileId = fileIdRef!

				var dataSize: UInt32 = 0
				var isWritable: UInt32 = 0

				let desInfoErr = AudioFileGetPropertyInfo(
					fileId, kAudioFilePropertyDataFormat, &dataSize, &isWritable)
				guard desInfoErr == noErr else {
					print("Failed to read property info: \(desInfoErr)")
					continuation.finish()
					return
				}

				var streamDescRef = AudioStreamBasicDescription()
				let desErr = AudioFileGetProperty(
					fileId, kAudioFilePropertyDataFormat, &dataSize, &streamDescRef)
				guard desInfoErr == noErr else {
					print("Failed to read property: \(desErr)")
					continuation.finish()
					return
				}
				let streamDesc = streamDescRef

				let numPackInfoErr = AudioFileGetPropertyInfo(
					fileId, kAudioFilePropertyAudioDataPacketCount, &dataSize, &isWritable)
				guard numPackInfoErr == noErr else {
					print("Failed to read property info: \(numPackInfoErr)")
					continuation.finish()
					return
				}

				var totalPacketsRef: UInt64 = 0
				let numPackErr = AudioFileGetProperty(
					fileId, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPacketsRef)
				guard numPackErr == noErr else {
					print("Failed to read property: \(numPackErr)")
					continuation.finish()
					return
				}

				let totalPackets = totalPacketsRef

				var ioNumBytes: UInt32 = 1024
				let buffer = malloc(Int(ioNumBytes))

				var ioNumPackets: UInt32 = UInt32(min(totalPackets, 128))
				var position: Int64 = 0

				let pDescRaw = calloc(1024, 1)
				let pDesc = pDescRaw.unsafelyUnwrapped.assumingMemoryBound(
					to: AudioStreamPacketDescription.self)

				let cts = CancellationTokenSource()
				continuation.onTermination = { _ in
					cts.cancel()
				}

				var moreToRead = position < totalPackets
				while !cts.isCancellationRequested && moreToRead {
					let readErr = AudioFileReadPacketData(
						fileId, true, &ioNumBytes, pDesc, position, &ioNumPackets, buffer)
					guard readErr == noErr else {
						print("Failed to read packets: \(readErr)")
						AudioFileClose(fileId)
						return
					}

					let audioData = AudioData.create(
						streamDesc, ioNumBytes, ioNumPackets, buffer!, pDesc, nil)
					continuation.yield(audioData)

					position += Int64(ioNumPackets)
					moreToRead = position < totalPackets

					ioNumBytes = 1024
					ioNumPackets = UInt32(min(Int64(totalPackets) - position, 128))
				}

				AudioFileClose(fileId)
				continuation.finish()
			}
		}
	}

	public let file: URL
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
private func emptyStream() -> AsyncStream<AudioData> {
	return AsyncStream<AudioData> { continuation in continuation.finish() }
}
