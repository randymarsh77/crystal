import Foundation
import AudioToolbox
import AVFoundation
import IDisposable
import Scope
import Streams

public class MicrophoneAudioSource : IAudioSource {
	private var keepRecording = false
	private var queue: AudioQueueRef?

	public init() {}

	public func start(_ onAudio: @escaping (_ stream: ReadableStream<AudioData>) -> ()) -> IDisposable {
		startRecording(onAudio)
		return Scope {
			self.stopRecording()
		}
	}

	private func startRecording(_ onAudio: @escaping (_ stream: ReadableStream<AudioData>) -> ()) {
		self.keepRecording = true
		let doStart = {
			let propertyData = try! ASBDFactory.CreateDefaultDescription(format: kAudioFormatLinearPCM)
			let (q, audio) = try! AQFactory.CreateDefaultInputQueue(propertyData: propertyData)
			if (self.keepRecording) {
				self.queue = q
				AudioQueueStart(q, nil)
				onAudio(audio)
			}
		}

		if #available(macOS 10.14, *) {
			switch AVCaptureDevice.authorizationStatus(for: .audio) {
			case .authorized: // The user has previously granted access to the microphone.
				doStart()
				break
			case .notDetermined: // The user has not yet been asked for microphone access.
				AVCaptureDevice.requestAccess(for: .audio) { granted in
					if granted {
						doStart()
					}
				}
				break

			case .denied: break // The user has previously denied access.
			case .restricted: // The user can't grant access due to restrictions.
				break
			@unknown default:
				break
			}
		} else {
			// Just try to start
			doStart()
		}
	}

	private func stopRecording() {
		self.keepRecording = false
		if let q = self.queue {
			AudioQueueStop(q, false)
			self.queue = nil
		}
	}
}
