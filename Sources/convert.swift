import AudioToolbox
import Cast
import Foundation
import Streams

func acDataSupplier(converter: AudioConverterRef, ioNumberDataPackets: UnsafeMutablePointer<UInt32>, ioData: UnsafeMutablePointer<AudioBufferList>, outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?, userData: UnsafeMutableRawPointer?) -> OSStatus
{
	let userDataPrime: UnsafePointer<ACDataSupplierUserData>? = Cast(userData)
	let data = userDataPrime!.pointee.data.pointee

	// Only supporting one callback from a compressed format to PCM
	assert(ioNumberDataPackets.pointee == data.packetInfo!.count)

	ioData.initialize(to: data.toBufferList())
	outDataPacketDescription?.initialize(to: data.packetInfo!.descriptions)

	return 0
}

struct ACDataSupplierUserData
{
	var data: UnsafePointer<AudioData>
}

public extension IReadableStream where ChunkType == AudioData
{
	public func convert(to: AudioFormatID) -> ReadableStream<AudioData>
	{
		var converterCreated = false
		let converter = UnsafeMutablePointer<AudioConverterRef?>.allocate(capacity: 1)
		let inputFormat = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
		let destinationFormat = try! ASBDFactory.CreateDefaultDescription(format: to)

		let stream = Streams.Stream<AudioData>()
		_ = self.subscribe { (data: AudioData) in
			if (!converterCreated) {
				converterCreated = true
				inputFormat.initialize(to: data.description)
				_ = AudioConverterNew(inputFormat, destinationFormat, converter)
			}

			let dataRef = UnsafeMutablePointer<AudioData>.allocate(capacity: 1)
			dataRef.initialize(to: data)
			let userData = UnsafeMutablePointer<ACDataSupplierUserData>.allocate(capacity: 1)
			userData.initialize(to: ACDataSupplierUserData(data: dataRef))

			let ioOutPacketCount = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
			ioOutPacketCount.initialize(to: 0)

			let outOutData = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)

			AudioConverterFillComplexBuffer(converter.pointee!,
				acDataSupplier,
				userData,
				ioOutPacketCount,
				outOutData,
				nil)

			for convertedData in outOutData.pointee.toAudioData(using: destinationFormat.pointee, startingAt: data.startTime)
			{
				stream.publish(convertedData)
			}
		}

		return ReadableStream(stream)
	}
}
