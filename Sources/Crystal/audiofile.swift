import AudioToolbox
import Scope

public enum FormatToFileTypeError: Error {
	case invalidConversion(message: String)
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
		throw FormatToFileTypeError.invalidConversion(message: "No file type for format: \(format)")
	}
}

@available(iOS 13.0, *)
@available(macOS 10.15.0, *)
extension AsyncStream where Element == AudioData {
	public func writeToFile(fileURL: URL) async {
		var audioFile: AudioFileID?
		var audioError: OSStatus = noErr
		var filePosition: Int64 = 0

		for await data in self {
			if audioFile == nil && audioError == noErr {
				var asbd = data.streamDescription
				let fileType = try! convertFormatToFileType(format: asbd.mFormatID)
				audioError = AudioFileCreateWithURL(
					fileURL as CFURL, fileType, &asbd, .eraseFile, &audioFile)
				guard audioError == noErr else {
					// TODO: Support throwing
					print("Failed to create audio file: \(audioError)")
					break
				}
			}

			if let openFile = audioFile {
				let totalBytes = data.data.bytes.count
				var bytesWritten: UInt32 = 0
				var bytesToWrite: UInt32 = UInt32(totalBytes)
				while bytesWritten < totalBytes {
					let writeError = AudioFileWriteBytes(
						openFile, true, filePosition, &bytesToWrite, data.data.bytes)
					guard writeError == noErr else {
						// TODO: Support throwing
						print("Failed to write bytes: \(writeError)")
						break
					}

					bytesWritten += bytesToWrite
					filePosition += Int64(bytesToWrite)
				}
			}
		}

		if let openFile = audioFile {
			AudioFileClose(openFile)
		}
	}
}
