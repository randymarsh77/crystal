import AVFoundation
import AudioToolbox
import Foundation
import IDisposable
import Scope

@available(iOS 13.0.0, *)
@available(macOS 10.15, *)
public class MicrophoneAudioSource: IAudioSource {
	public init() {}

	public func start() async -> (Scope, AsyncStream<AudioData>) {
		guard await getAuthorizationToRecord() else {
			return (Scope(dispose: nil), emptyStream())
		}

		let propertyData = try! ASBDFactory.createDefaultDescription(format: kAudioFormatLinearPCM)
		return AQFactory.createDefaultInputQueue(propertyData: propertyData)
	}

	private func getAuthorizationToRecord() async -> Bool {
		switch AVCaptureDevice.authorizationStatus(for: .audio) {
		case .authorized:  // The user has previously granted access to the microphone.
			return true
		case .notDetermined:  // The user has not yet been asked for microphone access.
			return await withCheckedContinuation { continuation in
				AVCaptureDevice.requestAccess(for: .audio) { granted in
					continuation.resume(returning: granted)
				}
			}
		case .denied: break  // The user has previously denied access.
		case .restricted:  // The user can't grant access due to restrictions.
			break
		@unknown default:
			break
		}
		return false
	}
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
private func emptyStream() -> AsyncStream<AudioData> {
	return AsyncStream<AudioData> { continuation in continuation.finish() }
}
