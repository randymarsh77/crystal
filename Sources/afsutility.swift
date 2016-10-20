import Foundation
import AudioToolbox

public typealias OnStreamReadyDelegate = (_ streamId: AudioFileStreamID?, _ asbd: UnsafeMutablePointer<AudioStreamBasicDescription>, _ cookieData: Data?) -> Void
public typealias OnPacketsDelegate = (_ numBytes: UInt32, _ numPackets: UInt32, _ inputData: UnsafeRawPointer, _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?, _ startTime: UnsafePointer<AudioTimeStamp>?) -> Void

public class AFSUtility
{
	public static func CreateAudioStreamParser(onStreamReady: @escaping OnStreamReadyDelegate, onPackets: @escaping OnPacketsDelegate) throws -> ((_ data: Data) throws -> Void, AudioFileStreamID)
	{
		let userData = UnsafeMutablePointer<StreamContext>.allocate(capacity: 1)
		let fileStream = UnsafeMutablePointer<AudioFileStreamID?>.allocate(capacity: 1)

		let openStreamResult = AudioFileStreamOpen(
			userData,
			afsPropertyListener,
			afsPackets,
			kAudioFileAAC_ADTSType,
			fileStream)

		if openStreamResult != 0 { throw AStreamError.CoreAudioError(code: openStreamResult, message: "open stream error") }

		let context = StreamContext(streamId: fileStream.pointee!, onStreamReady: onStreamReady, onPackets: onPackets)
		userData.initialize(to: context)

		return ({ (data) in
			try! userData.pointee.addBufferedData(data: data)
		}, userData.pointee.streamId)
	}

	public static func CreateCustomAudioStreamParser(onStreamReady: @escaping OnStreamReadyDelegate, onPackets: @escaping OnPacketsDelegate) throws -> (_ data: Data) throws -> Void
	{
		let context = CustomStreamContext(onStreamReady: onStreamReady, onPackets: onPackets)
		return { (data) in
			try! context.addBufferedData(data: data)
		}
	}
}

func afsPropertyListener(userData: UnsafeMutableRawPointer, fs: AudioFileStreamID, propertyID: AudioFileStreamPropertyID, flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) -> Void
{
	if (propertyID != kAudioFileStreamProperty_ReadyToProducePackets) { return }

	let context = userData.bindMemory(to: StreamContext.self, capacity: 1).pointee
	let afsId = context.streamId

	let asbd = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
	let asbdSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
	asbdSize.initialize(to: UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
	guard let _ = call(method: {
		AudioFileStreamGetProperty(afsId, kAudioFileStreamProperty_DataFormat, asbdSize, asbd) },
		log: { (result) in context.logError(error: AStreamError.CoreAudioError(code: result, message: "AFSGetProperty: asbd")) }
	) else { return }
	context.asbd = asbd.pointee

	let byteCount = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
	let byteCountSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
	byteCountSize.initialize(to: UInt32(MemoryLayout<UInt64>.size))
	let byteCountResult = call(method: {
		AudioFileStreamGetProperty(afsId, kAudioFileStreamProperty_AudioDataByteCount, byteCountSize, byteCount) },
		log: { (result) in context.logError(error: AStreamError.CoreAudioError(code: result, message: "AFSGetProperty: byte count")) })
	if (byteCountResult == 0)
	{
		context.byteCount = byteCount.pointee
	}

	let packetSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
	let packetSizeSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
	packetSizeSize.initialize(to: UInt32(MemoryLayout<UInt32>.size))
	let ub = call(method: {
		AudioFileStreamGetProperty(afsId, kAudioFileStreamProperty_PacketSizeUpperBound, packetSize, packetSizeSize) },
		log: { (result) in context.logError(error: AStreamError.CoreAudioError(code: result, message: "AFSGetProperty: packet size upper bound"))
	})
	if ub != nil && packetSize.pointee == 0
	{
		guard let _ = call(method: {
			AudioFileStreamGetProperty(afsId, kAudioFileStreamProperty_MaximumPacketSize, packetSize, packetSizeSize)},
			log: { (result) in context.logError(error: AStreamError.CoreAudioError(code: result, message: "AFSGetProperty: maximum packet size"))
		}) else { return }
	}
	context.packetSize = packetSize.pointee

	let hasCookieData = UnsafeMutablePointer<DarwinBoolean>.allocate(capacity: 1)
	let cookieDataLength = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
	cookieDataLength.initialize(to: 1)
	let _ = call(method: {
		AudioFileStreamGetPropertyInfo(afsId, kAudioFileStreamProperty_MagicCookieData, cookieDataLength, hasCookieData) },
		log: { (result) in context.logError(error: AStreamError.CoreAudioError(code: result, message: "AFSGetProperty: Test for magic cookie"))
	})

	if (cookieDataLength.pointee > 1)
	{
		let cookieData = calloc(1, Int(cookieDataLength.pointee))
		guard let _ = call(method: {
			AudioFileStreamGetProperty(afsId, kAudioFileStreamProperty_MagicCookieData, cookieDataLength, cookieData!) },
			log: { (result) in context.logError(error: AStreamError.CoreAudioError(code: result, message: "AFSGetProperty: Retrieve magic cookie"))
		}) else { return }
	}

	context.onReady(afsId, asbd, nil)
}

func afsPackets(userData: UnsafeMutableRawPointer, numBytes: UInt32, numPackets: UInt32, inputData: UnsafeRawPointer, packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>) -> Void
{
	let context = userData.bindMemory(to: StreamContext.self, capacity: 1).pointee
	context.expect = Int(numBytes)
	context.onPackets(numBytes, numPackets, inputData, packetDescriptions, nil)
}

class StreamContext
{
	var streamId: AudioFileStreamID
	var onPackets: OnPacketsDelegate
	var onReady: OnStreamReadyDelegate

	var asbd: AudioStreamBasicDescription?
	var byteCount: UInt64?
	var packetSize: UInt32?
	var magicCookie: Data?

	var expect: Int = 0

	init(streamId: AudioFileStreamID, onStreamReady: @escaping OnStreamReadyDelegate, onPackets: @escaping OnPacketsDelegate)
	{
		self.streamId = streamId
		self.onReady = onStreamReady
		self.onPackets = onPackets
	}

	func addBufferedData(data: Data) throws -> Void
	{
		self.expect = data.count
		let result = data.withUnsafeBytes() { (bytes: UnsafePointer<UInt8>) -> OSStatus in
			AudioFileStreamParseBytes(
				self.streamId,
				UInt32(data.count),
				bytes,
				AudioFileStreamParseFlags.discontinuity)
		}

		if result != 0 { throw AStreamError.CoreAudioError(code: result, message: "parse bytes error") }

		print("Expected: ", data.count, " parsed: ", self.expect)
	}

	func logError(error: AStreamError) -> Void
	{
	}
}

class CustomStreamContext
{
	var onPackets: OnPacketsDelegate
	var onReady: OnStreamReadyDelegate

	var decode: ADTSDecoder
	var buffer: UnsafeMutableRawPointer
	var bufferSize: Int
	var bufferPosition: Int

	var asbd: UnsafeMutablePointer<AudioStreamBasicDescription>? = nil

	init(onStreamReady: @escaping OnStreamReadyDelegate, onPackets: @escaping OnPacketsDelegate)
	{
		self.onPackets = onPackets
		self.onReady = onStreamReady

		let options = ADTSDecodingOptions(dataFormat: .AAC_LC, decodeSNSHeader: true)
		self.decode = ADTSUtility.CreateADTSDecoder(options: options)
		self.bufferSize = 1024 * 16
		self.buffer = malloc(self.bufferSize)
		self.bufferPosition = 0
	}

	func addBufferedData(data: Data) throws -> Void
	{
		if self.asbd == nil {
			self.asbd = try! ASBDFactory.CreateDefaultDescription(format: kAudioFormatMPEG4AAC)
			self.onReady(nil, self.asbd!, nil)
		}

		var bufferedData = data
		if (self.bufferPosition > 0)
		{
			data.withUnsafeBytes() { (bytes: UnsafePointer<UInt8>) -> () in
				memcpy(self.buffer.advanced(by: self.bufferPosition), bytes, data.count)
			}
			self.bufferPosition += data.count
			bufferedData = Data(bytesNoCopy: self.buffer.bindMemory(to: UInt8.self, capacity: self.bufferPosition), count: self.bufferPosition, deallocator: .none)
		}

		let (parsed, leftovers) = self.decode(bufferedData)
		if (parsed != nil)
		{
			let pd = UnsafeMutablePointer<AudioStreamPacketDescription>(mutating: parsed!.pd)
			parsed!.data.withUnsafeBytes() { (bytes: UnsafePointer<UInt8>) -> () in
				self.onPackets(
					UInt32(parsed!.data.count),
					parsed!.pdc,
					bytes,
					pd,
					parsed!.ts)
			}
		}

		if (leftovers != nil)
		{
			leftovers!.withUnsafeBytes() { (bytes) -> () in
				memcpy(self.buffer, bytes, leftovers!.count)
			}
			self.bufferPosition = leftovers!.count
		}
		else
		{
			self.bufferPosition = 0
		}
	}
}

func call(method: () -> OSStatus, log: (OSStatus) -> Void) -> OSStatus?
{
	let result = method()
	if (result != 0) {
		log(result)
	}
	return result == 0 ? result : nil
}
