import Foundation
import IDisposable
import Streams

public protocol IAudioSource {
	func start(_ onAudio: @escaping (_ stream: ReadableStream<AudioData>) -> ()) -> IDisposable
}
