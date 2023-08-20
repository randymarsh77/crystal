import AudioToolbox
import Streams
import Scope

public enum FormatToFileTypeError : Error
{
	case InvalidConversion(message: String)
}

func convertFormatToFileType(format: AudioFormatID) throws -> AudioFileTypeID {
	switch format {
	case kAudioFormatLinearPCM:
		return kAudioFileWAVEType
	case kAudioFormatMPEGLayer1:
		return kAudioFileMP1Type
	case kAudioFormatMPEGLayer2:
		return kAudioFileMP2Type
	case kAudioFormatMPEGLayer3:
		return kAudioFileMP3Type
	default:
		throw FormatToFileTypeError.InvalidConversion(message: "No file type for format: \(format)")
	}
}

public extension IReadableStream where ChunkType == AudioData
{
	func writeToFile(fileURL: URL) -> Scope {
        var audioFile: AudioFileID?
		var audioError: OSStatus = noErr
		var filePosition: Int64 = 0

		let unsubscribe = self.subscribe { data in
			if audioFile == nil && audioError == noErr {
				var asbd = data.description
				let fileType = try! convertFormatToFileType(format: asbd.mFormatID)
				audioError = AudioFileCreateWithURL(fileURL as CFURL, fileType, &asbd, .eraseFile, &audioFile)
				guard audioError == noErr else {
					// TODO: Support throwing
					print("Failed to create audio file: \(audioError)")
					return
				}
			}

			if let openFile = audioFile {
				let totalBytes = data.data.bytes.count
				var bytesWritten: UInt32 = 0
				var bytesToWrite: UInt32 = UInt32(totalBytes)
				while bytesWritten < totalBytes {
					let writeError = AudioFileWriteBytes(openFile, true, filePosition, &bytesToWrite, data.data.bytes)
					guard writeError == noErr else {
						// TODO: Support throwing
						print("Failed to write bytes: \(writeError)")
						return
					}

					bytesWritten += bytesToWrite
					filePosition += Int64(bytesToWrite)
				}
			}
		}
		

		let close = Scope {
			if let openFile = audioFile {
				print("Closing file")
				AudioFileClose(openFile)
			}
		}
		let dispose = Scope {
			unsubscribe.dispose()
			let doClose = close.transfer()
			doClose.dispose()
		}

		self.addDownstreamDisposable(dispose)

		return dispose
	}
}
