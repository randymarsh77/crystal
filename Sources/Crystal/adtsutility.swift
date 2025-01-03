import AudioToolbox
import Cast
import CryptoSwift
import Foundation
import Sockets
import Time

public enum ADTSDataFormat {
	case aacLC
	case aacHE
}

public struct ADTSEncodingOptions {
	var dataFormat: ADTSDataFormat
	var crc: Bool
}

public struct ADTSDecodingOptions {
	var dataFormat: ADTSDataFormat
	var decodeSNSHeader: Bool
}

public typealias ADTSDecoder = (Data) -> (AQInputData?, Data?)

public class ADTSUtility {
	public static func createADTSEncoder(options: ADTSEncodingOptions) -> (AQInputData) -> Data {
		return { (inputData: AQInputData) in

			let headerLength = options.crc ? 9 : 7
			let numPackets = Int(inputData.pdc)
			let adtsDataLength = numPackets * headerLength + inputData.data.count
			let adtsData = malloc(adtsDataLength)

			var currentPosition: UnsafeMutablePointer<UInt8> = bindingCast(
				adtsData!, adtsDataLength)
			for pd in UnsafeBufferPointer<AudioStreamPacketDescription>(
				start: UnsafePointer(inputData.pd), count: numPackets)
			{
				let packetOffset = pd.mStartOffset
				let packetSize = pd.mDataByteSize
				let frameLength: UInt16 = UInt16(packetSize) + UInt16(headerLength)

				let crc: UInt16? =
					options.crc
					? Checksum.crc16(
						[UInt8](
							inputData.data.advanced(by: Int(packetOffset)).prefix(
								upTo: Int(packetSize))))
					: nil

				writeHeader(
					data: currentPosition, options: options, frameLength: frameLength, crc: crc)

				currentPosition = currentPosition.advanced(by: headerLength)

				inputData.data.withUnsafeBytes { (audioData: UnsafeRawBufferPointer) -> Void in
					memcpy(
						currentPosition, audioData.baseAddress!.advanced(by: Int(packetOffset)),
						Int(packetSize))
				}

				currentPosition = currentPosition.advanced(by: Int(packetSize))
			}

			return Data(bytesNoCopy: adtsData!, count: adtsDataLength, deallocator: .free)
		}
	}

	public static func createADTSDecoder(options: ADTSDecodingOptions) -> (Data) -> (
		AQInputData?, Data?
	) {
		let maxHeaderSize = 9 + (options.decodeSNSHeader ? SNSHeaderLength : 0)

		return { (chunk: Data) in

			var bytesParsed: Int = 0
			var parsedAudioBytes: UnsafeMutableRawPointer?
			var leftoverData: Data?
			var packets = [AudioStreamPacketDescription]()
			var startTime: UnsafePointer<AudioTimeStamp>?

			var position = 0
			var bytes = chunk.withUnsafeBytes {
				UnsafeMutablePointer<UInt8>(
					mutating: $0.baseAddress!.assumingMemoryBound(to: UInt8.self))
			}
			while position < chunk.count - maxHeaderSize {
				var bytesLost = 0
				while !verifyAtHeader(bytes: bytes) && position < chunk.count {
					if options.decodeSNSHeader {
						let snsHeaderChunk = Data(
							bytesNoCopy: bytes, count: SNSHeaderLength, deallocator: .none)
						if SNSUtility.isValidHeader(chunk: snsHeaderChunk) {
							let synchronization = try! SNSUtility.parseHeader(chunk: snsHeaderChunk)
							let actualStart =
								synchronization.syncTime + (Time.now - synchronization.receiveGuess)
							let timeData = UnsafeMutablePointer<AudioTimeStamp>.allocate(
								capacity: 1)
							timeData.initialize(to: AudioTimeStamp())
							timeData.pointee.mHostTime = actualStart.systemTimeStamp
							timeData.pointee.mFlags = .hostTimeValid

							startTime = UnsafePointer(timeData)

							bytes = bytes.advanced(by: SNSHeaderLength)
							position += SNSHeaderLength
							continue
						}
					}
					print("Losing data")
					bytesLost += 1
					position += 1
					bytes = bytes.advanced(by: 1)
				}
				if bytesLost > 0 { print("lost bytes: ", bytesLost) }

				let headerLength = parseHeaderLength(bytes: bytes)
				let frameLength = parseADTSFrameLength(bytes: bytes) - Int(headerLength)
				let adtsDataLength = Int(headerLength) + frameLength

				let chunkContainsFullFrame = chunk.count - position >= adtsDataLength
				if chunkContainsFullFrame {
					if parsedAudioBytes == nil { parsedAudioBytes = malloc(chunk.count) }

					packets.append(
						AudioStreamPacketDescription(
							mStartOffset: Int64(bytesParsed),
							mVariableFramesInPacket: 0,
							mDataByteSize: UInt32(frameLength)))

					if headerLength == 9 {
						let parsedCRC = parseCRC(bytes: bytes)
						let computedCRC: UInt16? = Checksum.crc16(
							Array(
								UnsafeBufferPointer(
									start: UnsafePointer<UInt8>(
										bytes.advanced(by: Int(headerLength))),
									count: Int(frameLength))))
						if parsedCRC != computedCRC {
							print("Detected Data Corruption :(")
						}
					}

					memcpy(
						parsedAudioBytes!.advanced(by: bytesParsed),
						bytes.advanced(by: Int(headerLength)), Int(frameLength))

					bytesParsed += frameLength
					position += adtsDataLength
					bytes = bytes.advanced(by: adtsDataLength)
				} else {
					leftoverData = Data(
						bytesNoCopy: bytes, count: chunk.count - position, deallocator: .none)
					position = chunk.count
				}
			}

			if position < chunk.count {
				leftoverData = Data(
					bytesNoCopy: bytes, count: chunk.count - position, deallocator: .none)
			}

			var parsedData: AQInputData?
			if bytesParsed > 0 {
				var pd: UnsafeMutablePointer<AudioStreamPacketDescription>?
				packets.withUnsafeBufferPointer { (packetDescriptions) in
					let descriptionByteSize =
						packets.count * MemoryLayout<AudioStreamPacketDescription>.size
					let copiedDescriptions = malloc(descriptionByteSize)
					memcpy(copiedDescriptions, packetDescriptions.baseAddress, descriptionByteSize)

					pd = copiedDescriptions?.bindMemory(
						to: AudioStreamPacketDescription.self, capacity: packets.count)
				}

				let data = Data(
					bytesNoCopy: parsedAudioBytes!.bindMemory(
						to: UInt8.self, capacity: bytesParsed), count: bytesParsed,
					deallocator: .free)
				parsedData = AQInputData(
					data: data, ts: startTime, pdc: UInt32(packets.count), pd: pd!)
			}

			return (parsedData, leftoverData)
		}
	}

	private static func writeHeader(
		data: UnsafeMutablePointer<UInt8>, options: ADTSEncodingOptions, frameLength: UInt16,
		crc: UInt16?
	) {
		let profile: UInt8 = getProfile(format: options.dataFormat)
		let freqIdx: UInt8 = 4  // 44.1KHz
		let chanCfg: UInt8 = 2  // CPE

		data[0] = 0xFF
		data[1] = options.crc ? 0xF0 : 0xF1
		data[2] = ((profile - 1) << 6) | (freqIdx << 2) | (chanCfg >> 2)
		data[3] = ((chanCfg & 3) << 6) | UInt8(frameLength >> 11)
		data[4] = UInt8((frameLength & 0x7FF) >> 3)
		data[5] = UInt8((frameLength & 7) << 5) | 0x1F
		data[6] = 0xFC

		if options.crc {
			data[7] = UInt8((crc! & 0xFF00) >> 8)
			data[8] = UInt8(crc! & 0x00FF)
		}
	}
}

func verifyAtHeader(bytes: UnsafeMutablePointer<UInt8>) -> Bool {
	return bytes[0] == 0xFF && bytes[1] & 0xF0 == 0xF0
}

func parseHeaderLength(bytes: UnsafeMutablePointer<UInt8>) -> UInt8 {
	return bytes[1] & 0xF1 == 0xF1 ? 7 : 9
}

func parseADTSFrameLength(bytes: UnsafeMutablePointer<UInt8>) -> Int {
	return (Int(bytes[3] & 0x03) << 11) | (Int(bytes[4]) << 3) | (Int(bytes[5] & 0xE0) >> 5)
}

func parseCRC(bytes: UnsafeMutablePointer<UInt8>) -> UInt16 {
	return (UInt16(bytes[7]) << 8) | UInt16(bytes[8])
}

func getProfile(format: ADTSDataFormat) -> UInt8 {
	switch format {
	case .aacHE:
		return 1
	case .aacLC:
		return 2
	}
}
