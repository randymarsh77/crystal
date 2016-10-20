import Foundation
import AudioToolbox

public class Utility
{
	public static func GetDefaultInputDeviceSampleRate() -> (OSStatus, Float64)
	{
		var sampleRate = 0
#if TARGET_OS_MAC
		var propertySize = UInt32(sizeof(AudioDeviceID))

		var propertyAddress = AudioObjectPropertyAddress(
			mSelector: kAudioHardwarePropertyDefaultInputDevice,
			mScope: kAudioObjectPropertyScopeGlobal,
			mElement: 0)

		let propertyAddressPointer = UnsafeMutablePointer<AudioObjectPropertyAddress>.alloc(1)
		propertyAddressPointer.initialize(propertyAddress)

		let deviceIdPointer = UnsafeMutablePointer<AudioDeviceID>.alloc(1)
		deviceIdPointer.initialize(AudioDeviceID(kAudioObjectSystemObject))

		let propertySizePointer = UnsafeMutablePointer<UInt32>.alloc(1)
		propertySizePointer.initialize(propertySize)

		let dataSize: UnsafeMutablePointer<Void> = nil

		var error = AudioHardwareServiceGetPropertyData(
			deviceIdPointer.memory,
			propertyAddressPointer,
			0,
			dataSize,
			propertySizePointer,
			deviceIdPointer)

		if (error == 0)
		{
			propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
			propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
			propertyAddress.mElement = 0;
			propertySize = UInt32(sizeof(Float64))

			propertyAddressPointer.initialize(propertyAddress)
			propertySizePointer.initialize(propertySize)

			let sampleRatePointer = UnsafeMutablePointer<Float64>.alloc(1)
			sampleRatePointer.initialize(sampleRate)

			error = AudioHardwareServiceGetPropertyData(
				deviceIdPointer.memory,
				propertyAddressPointer,
				0,
				dataSize,
				propertySizePointer,
				sampleRatePointer);

			sampleRate = sampleRatePointer.memory
		}

		return ( error, sampleRate )
#else
		return ( OSStatus(0), 44100 )
#endif
	}

	public static func ComputeBufferSize(formatPointer: UnsafePointer<AudioStreamBasicDescription>, queue: AudioQueueRef, seconds: Float64) -> UInt32
	{
		var bytes: UInt32 = 0
		let format = formatPointer.pointee
		let frames = UInt32(ceil(seconds * format.mSampleRate))
		if (format.mBytesPerFrame > 0)
		{
			bytes = frames * format.mBytesPerFrame
		}
		else
		{
			let maxPacketSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
			maxPacketSize.initialize(to: format.mBytesPerPacket)
			if (format.mBytesPerPacket == 0)
			{
				let propertyDataSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
				propertyDataSize.initialize(to: UInt32(MemoryLayout<UInt32>.size))
				AudioQueueGetProperty(queue, kAudioConverterPropertyMaximumOutputPacketSize, maxPacketSize, propertyDataSize)
			}

			var packets = format.mFramesPerPacket > 0 ?
				frames / format.mFramesPerPacket :
				frames

			packets = packets == 0 ? 1 : packets

			bytes = packets * maxPacketSize.pointee
		}

		return bytes > 6144 ? 6144 : 6144;
	}
}
