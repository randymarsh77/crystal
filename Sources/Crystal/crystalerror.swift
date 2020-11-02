import Foundation

public enum AStreamError : Error
{
	case CoreAudioError(code: OSStatus, message: String)
	case SNSInvalidHeader
}
