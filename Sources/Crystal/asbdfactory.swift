import AudioToolbox
import Foundation

public class ASBDFactory {
	enum ASBDFactoryError: Error {
		case unsupportedFormat(format: AudioFormatID)
		case coreAudioError(code: OSStatus)
	}

	public static func createDefaultDescription(format: AudioFormatID) throws
		-> UnsafeMutablePointer<AudioStreamBasicDescription>
	{
		var propertyData: UnsafeMutablePointer<AudioStreamBasicDescription>
		switch format
		{
		case kAudioFormatMPEG4AAC:
			propertyData = createMPEG4AAC()
		case kAudioFormatAppleLossless:
			propertyData = createAppleLossless()
		case kAudioFormatLinearPCM:
			propertyData = createLinearPCM()
		default:
			throw ASBDFactoryError.unsupportedFormat(format: format)
		}

		let propertyDataSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		propertyDataSize.initialize(to: UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

		let status = AudioFormatGetProperty(
			kAudioFormatProperty_FormatInfo,
			0,
			nil,
			propertyDataSize,
			propertyData)

		if status != 0 { throw ASBDFactoryError.coreAudioError(code: status) }

		return propertyData
	}

	private static func createMPEG4AAC() -> UnsafeMutablePointer<AudioStreamBasicDescription> {
		let (_, sampleRate) = Utility.getDefaultInputDeviceSampleRate()

		let propertyData = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		propertyData.initialize(
			to: AudioStreamBasicDescription(
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

	private static func createAppleLossless() -> UnsafeMutablePointer<AudioStreamBasicDescription> {
		let (_, sampleRate) = Utility.getDefaultInputDeviceSampleRate()

		let propertyData = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		propertyData.initialize(
			to: AudioStreamBasicDescription(
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

	private static func createLinearPCM() -> UnsafeMutablePointer<AudioStreamBasicDescription> {
		let (_, sampleRate) = Utility.getDefaultInputDeviceSampleRate()

		let bitsPerChannel = 8 * UInt32(MemoryLayout<CShort>.size)
		let bytesPerFrame = UInt32(MemoryLayout<CShort>.size) * 2

		let propertyData = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		propertyData.initialize(
			to: AudioStreamBasicDescription(
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
