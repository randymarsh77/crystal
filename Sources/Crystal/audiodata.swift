import AudioToolbox
import Foundation
import Time

public struct PacketInfo: @unchecked Sendable {
	public let descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>
	public let count: UInt32
}

public struct AudioData: Sendable {
	public let description: AudioStreamBasicDescription
	public let packetInfo: PacketInfo?
	public let data: Data
	public let startTime: AudioTimeStamp?

	internal static func create(
		_ description: AudioStreamBasicDescription, _ numBytes: UInt32, _ numPackets: UInt32,
		_ inputData: UnsafeRawPointer,
		_ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?,
		_ startTime: UnsafePointer<AudioTimeStamp>?
	) -> AudioData {
		let packetInfo =
			numPackets != 0 ? PacketInfo(descriptions: packetDescriptions!, count: numPackets) : nil
		let data = Data(bytes: inputData, count: Int(numBytes))
		return AudioData(
			description: description, packetInfo: packetInfo, data: data,
			startTime: startTime?.pointee)
	}
}

extension AudioData {
	public func totalTime() -> Time {
		let bytesPerSecond = Float64(description.mBytesPerFrame) * description.mSampleRate
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
				mNumberChannels: self.description.mChannelsPerFrame,
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
					description: using, packetInfo: nil,
					data: Data(bytes: buffer.mData!, count: Int(buffer.mDataByteSize)),
					startTime: i == 0 ? startingAt : nil))
		}

		return datas
	}
}
