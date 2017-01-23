import AudioToolbox
import Foundation

public struct PacketInfo
{
	public let descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>
	public let count: UInt32
}

public struct AudioData
{
	public let description: AudioStreamBasicDescription
	public let packetInfo: PacketInfo?
	public let data: Data
	public let startTime: AudioTimeStamp?

	internal static func Create(_ description: AudioStreamBasicDescription, _ numBytes: UInt32, _ numPackets: UInt32, _ inputData: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?, _ startTime: UnsafePointer<AudioTimeStamp>?) -> AudioData {
		let packetInfo = numPackets != 0 ? PacketInfo(descriptions: packetDescriptions!, count: numPackets) : nil
		let data = Data(bytes: inputData, count: Int(numBytes))
		return AudioData(description: description, packetInfo: packetInfo, data: data, startTime: startTime?.pointee)
	}
}

public extension AudioData
{
	public func toBufferList() -> AudioBufferList
	{
		let buffer = AudioBuffer(mNumberChannels: self.description.mChannelsPerFrame, mDataByteSize: UInt32(self.data.count), mData: nil)
		return AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
	}
}

public extension AudioBufferList
{
	public func toAudioData(using: AudioStreamBasicDescription, startingAt: AudioTimeStamp?) -> [AudioData]
	{
		var datas = [AudioData]()

		// Assume one buffer for now
		assert(self.mNumberBuffers == 1)

		for i in 0...self.mNumberBuffers-1 {
			let buffer = self.mBuffers
			datas.append(AudioData(description: using, packetInfo: nil, data: Data(bytes: buffer.mData!, count:Int(buffer.mDataByteSize)), startTime: i == 0 ? startingAt : nil))
		}

		return datas
	}
}
