import Foundation

public enum AStreamError: Error {
	case coreAudioError(code: OSStatus, message: String)
	case invalidSNSHeader
}
