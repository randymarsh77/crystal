import Foundation
import AudioToolbox
import AVFoundation
import IDisposable
import Scope
import Streams

public class FileAudioSource : IAudioSource {
	public init(_ file: URL) {
		self.file = file
	}

	public func start(_ onAudio: @escaping (ReadableStream<AudioData>) -> ()) -> IDisposable {
		var fileId: AudioFileID? = nil
		let openErr = AudioFileOpenURL(file as CFURL, AudioFilePermissions.readPermission, 0, &fileId)
		guard openErr == noErr else {
			print("Failed to open file: \(openErr)")
			return Scope {}
		}

		var dataSize: UInt32 = 0
		var isWritable: UInt32 = 0

		let desInfoErr = AudioFileGetPropertyInfo(fileId!, kAudioFilePropertyDataFormat, &dataSize, &isWritable)
		guard desInfoErr == noErr else {
			print("Failed to read property info: \(desInfoErr)")
			return Scope {}
		}

		var streamDesc = AudioStreamBasicDescription()
		let desErr = AudioFileGetProperty(fileId!, kAudioFilePropertyDataFormat, &dataSize, &streamDesc)
		guard desInfoErr == noErr else {
			print("Failed to read property: \(desErr)")
			return Scope {}
		}

		let numPackInfoErr = AudioFileGetPropertyInfo(fileId!, kAudioFilePropertyAudioDataPacketCount, &dataSize, &isWritable)
		guard numPackInfoErr == noErr else {
			print("Failed to read property info: \(numPackInfoErr)")
			return Scope {}
		}

		var totalPackets: UInt64 = 0
		let numPackErr = AudioFileGetProperty(fileId!, kAudioFilePropertyAudioDataPacketCount, &dataSize, &totalPackets)
		guard numPackErr == noErr else {
			print("Failed to read property: \(numPackErr)")
			return Scope {}
		}


		let stream = Streams.Stream<AudioData>()
		onAudio(ReadableStream(stream))

		var keepReading = true

		DispatchQueue.global().async {

			var ioNumBytes: UInt32 = 1024
			let buffer = malloc(Int(ioNumBytes))

			var ioNumPackets: UInt32 = UInt32(min(totalPackets, 128))
			var position: Int64 = 0

			let pDescRaw = malloc(1024)
			let pDesc = pDescRaw.unsafelyUnwrapped.assumingMemoryBound(to: AudioStreamPacketDescription.self)

			var moreToRead = position < totalPackets
			while (keepReading && moreToRead) {
				let readErr = AudioFileReadPacketData(fileId!, true, &ioNumBytes, pDesc, position, &ioNumPackets, buffer)
				guard readErr == noErr else {
					print("Failed to read packets: \(readErr)")
					AudioFileClose(fileId!)
					return
				}

				let audioData = AudioData.Create(streamDesc, ioNumBytes, ioNumPackets, buffer!, pDesc, nil)

				stream.publish(audioData)

				position += Int64(ioNumPackets)
				moreToRead = position < totalPackets

				ioNumBytes = 1024
				ioNumPackets = UInt32(min(Int64(totalPackets) - position, 128))
			}

			AudioFileClose(fileId!)
		}

		return Scope {
			keepReading = false
		}
	}

	public let file: URL
}
