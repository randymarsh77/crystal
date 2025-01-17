import AudioToolbox
import Cast
import Foundation
import Time

public struct AudioData: Sendable {
	public let streamDescription: AudioStreamBasicDescription
	public let packetDescriptions: [AudioStreamPacketDescription]?
	public let data: Data
	public let startTime: AudioTimeStamp?

	internal static func create(
		_ description: AudioStreamBasicDescription, _ numBytes: UInt32, _ numPackets: UInt32,
		_ inputData: UnsafeRawPointer,
		_ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?,
		_ startTime: UnsafePointer<AudioTimeStamp>?
	) -> AudioData {
		let data = Data(bytes: inputData, count: Int(numBytes))
		if numPackets == 0 {
			return AudioData(
				streamDescription: description, packetDescriptions: nil, data: data,
				startTime: startTime?.pointee)
		}

		var descriptions = [AudioStreamPacketDescription](
			repeating: AudioStreamPacketDescription(), count: Int(numPackets))
		let packetData = Data(
			bytesNoCopy: packetDescriptions!, count: Int(numPackets), deallocator: .none)
		packetData.withUnsafeBytes { src in
			descriptions.withUnsafeMutableBytes { dest in
				_ = src.copyBytes(to: dest)
			}
		}
		return AudioData(
			streamDescription: description, packetDescriptions: descriptions, data: data,
			startTime: startTime?.pointee)
	}
}

extension AudioData {
	public func totalTime() -> Time {
		let bytesPerSecond =
			Float64(streamDescription.mBytesPerFrame) * streamDescription.mSampleRate
		let seconds = Float64(data.count) / bytesPerSecond
		return Time.fromInterval(seconds, unit: .seconds)
	}
}

extension AudioData {
	public func toBufferList() -> AudioBufferList {
		var buffer: AudioBuffer?
		self.data.withUnsafeBytes {
			let b = UnsafeMutablePointer(
				mutating: $0.baseAddress!.assumingMemoryBound(to: UInt8.self))
			buffer = AudioBuffer(
				mNumberChannels: self.streamDescription.mChannelsPerFrame,
				mDataByteSize: UInt32(self.data.count), mData: b)
		}
		return AudioBufferList(mNumberBuffers: 1, mBuffers: buffer!)
	}
}

extension AudioBufferList {
	public func toAudioData(using: AudioStreamBasicDescription, startingAt: AudioTimeStamp?)
		-> [AudioData]
	{
		var datas = [AudioData]()
		if self.mNumberBuffers == 0 {
			print("0 buffers")
			return datas
		}

		// Assume one buffer for now
		assert(self.mNumberBuffers == 1)

		for i in 0...self.mNumberBuffers - 1 {
			let buffer = self.mBuffers
			datas.append(
				AudioData(
					streamDescription: using, packetDescriptions: nil,
					data: Data(bytes: buffer.mData!, count: Int(buffer.mDataByteSize)),
					startTime: i == 0 ? startingAt : nil))
		}

		return datas
	}
}
