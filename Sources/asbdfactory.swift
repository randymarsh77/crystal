import Foundation
import AudioToolbox

public class ASBDFactory
{
	enum ASBDFactoryError : Error
	{
		case UnsupportedFormat(format: AudioFormatID)
		case CoreAudioError(code: OSStatus)
	}

	public static func CreateDefaultDescription(format: AudioFormatID) throws -> UnsafeMutablePointer<AudioStreamBasicDescription>
	{
		var propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>
		switch format
		{
		case kAudioFormatMPEG4AAC:
			propertyData = CreateMPEG4AAC()
		case kAudioFormatAppleLossless:
			propertyData = CreateAppleLossless()
		case kAudioFormatLinearPCM:
			propertyData = CreateLinearPCM()
		default:
			throw ASBDFactoryError.UnsupportedFormat(format: format)
		}

		let propertyDataSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		propertyDataSize.initialize(to: UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

		let status = AudioFormatGetProperty(
			kAudioFormatProperty_FormatInfo,
			0,
			nil,
			propertyDataSize,
			propertyData)

		if (status != 0) { throw ASBDFactoryError.CoreAudioError(code: status) }

		return propertyData
	}

	private static func CreateMPEG4AAC() -> UnsafeMutablePointer<AudioStreamBasicDescription>
	{
		let ( _, sampleRate ) = Utility.GetDefaultInputDeviceSampleRate()

		let propertyData = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		propertyData.initialize(to: AudioStreamBasicDescription(
			mSampleRate: sampleRate,
			mFormatID: kAudioFormatMPEG4AAC,
			mFormatFlags: 0,
			mBytesPerPacket: 0,
			mFramesPerPacket: 1024,
			mBytesPerFrame: 0,
			mChannelsPerFrame: 2,
			mBitsPerChannel: 0,
			mReserved: 0))

		return propertyData
	}

	private static func CreateAppleLossless() -> UnsafeMutablePointer<AudioStreamBasicDescription>
	{
		let ( _, sampleRate ) = Utility.GetDefaultInputDeviceSampleRate()

		let propertyData = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		propertyData.initialize(to: AudioStreamBasicDescription(
			mSampleRate: sampleRate,
			mFormatID: kAudioFormatAppleLossless,
			mFormatFlags: 0,
			mBytesPerPacket: 0,
			mFramesPerPacket: 1,
			mBytesPerFrame: 0,
			mChannelsPerFrame: 1,
			mBitsPerChannel: 0,
			mReserved: 0))

		return propertyData
	}

	private static func CreateLinearPCM() -> UnsafeMutablePointer<AudioStreamBasicDescription>
	{
		let ( _, sampleRate ) = Utility.GetDefaultInputDeviceSampleRate()

		let bitsPerChannel = 8 * UInt32(MemoryLayout<CShort>.size)
		let bytesPerFrame = UInt32(MemoryLayout<CShort>.size) * 2

		let propertyData = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		propertyData.initialize(to: AudioStreamBasicDescription(
			mSampleRate: sampleRate,
			mFormatID: kAudioFormatLinearPCM,
			mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
			mBytesPerPacket: bytesPerFrame * bitsPerChannel,
			mFramesPerPacket: 1,
			mBytesPerFrame: bytesPerFrame,
			mChannelsPerFrame: 2,
			mBitsPerChannel: bitsPerChannel,
			mReserved: 0))

		return propertyData
	}
}
