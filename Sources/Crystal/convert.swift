import AudioToolbox
import Cast
import Foundation

func acDataSupplier(
	converter: AudioConverterRef, ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
	ioData: UnsafeMutablePointer<AudioBufferList>,
	outDataPacketDescription: UnsafeMutablePointer<
		UnsafeMutablePointer<AudioStreamPacketDescription>?
	>?,
	userData: UnsafeMutableRawPointer?
) -> OSStatus {
	let userDataPrime: UnsafePointer<ACDataSupplierUserData>? = cast(userData)
	let data = userDataPrime!.pointee.data.pointee

	// Only supporting one callback from a compressed format to PCM
	assert(ioNumberDataPackets.pointee <= data.packetDescriptions!.count)
	ioNumberDataPackets.pointee = UInt32(data.packetDescriptions!.count)

	ioData.initialize(to: data.toBufferList())

	data.packetDescriptions?.withUnsafeBufferPointer {
		let mutable = UnsafeMutablePointer<AudioStreamPacketDescription>(
			OpaquePointer($0.baseAddress))
		outDataPacketDescription?.initialize(to: mutable)
	}

	return 0
}

struct ACDataSupplierUserData {
	var data: UnsafePointer<AudioData>
}

@available(iOS 13.0.0, *)
@available(macOS 10.15, *)
extension AsyncStream where Element == AudioData {
	public func convert(to: AudioFormatID) async -> AsyncStream<AudioData> {
		return AsyncStream { continuation in
			Task {
				var converterCreated = false
				let converter = UnsafeMutablePointer<AudioConverterRef?>.allocate(capacity: 1)
				let inputFormat = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(
					capacity: 1)
				let destinationFormat = try! ASBDFactory.createDefaultDescription(format: to)

				for await data in self {
					if !converterCreated {
						converterCreated = true
						inputFormat.initialize(to: data.streamDescription)
						_ = AudioConverterNew(inputFormat, destinationFormat, converter)
					}

					let dataRef = UnsafeMutablePointer<AudioData>.allocate(capacity: 1)
					dataRef.initialize(to: data)
					let userData = UnsafeMutablePointer<ACDataSupplierUserData>.allocate(
						capacity: 1)
					userData.initialize(to: ACDataSupplierUserData(data: dataRef))

					let ioOutPacketCount = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
					ioOutPacketCount.initialize(to: 512)

					let outOutData = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
					outOutData.initialize(
						to: AudioBufferList(
							mNumberBuffers: 1,
							mBuffers: AudioBuffer(
								mNumberChannels: 2, mDataByteSize: 1024, mData: malloc(1024 * 2))))

					_ = AudioConverterFillComplexBuffer(
						converter.pointee!,
						acDataSupplier,
						userData,
						ioOutPacketCount,
						outOutData,
						nil)

					for convertedData in outOutData.pointee.toAudioData(
						using: destinationFormat.pointee, startingAt: data.startTime)
					{
						continuation.yield(convertedData)
					}
				}

				continuation.finish()
			}
		}
	}
}
