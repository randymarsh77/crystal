import AudioToolbox
import Cast
import Foundation
import IDisposable

public enum AQPropertyValue: Sendable {
	case isRunning(Bool)
}

public enum AQProperty: Sendable {
	case isRunning
}

func preparePropertyData(_ property: AQProperty) -> (
	UnsafeMutableRawPointer, UnsafeMutablePointer<UInt32>
) {
	switch property {
	case .isRunning:
		let value = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 2)
		let valueSize = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
		return (value, valueSize)
	}
}

func mapPropertyToID(_ property: AQProperty) -> AudioQueuePropertyID {
	switch property {
	case .isRunning:
		return kAudioQueueProperty_IsRunning
	}
}

func propertyListenerCallback(
	userData: UnsafeMutableRawPointer?, queue: AudioQueueRef, propertyID: AudioQueuePropertyID
) {
	let me = Unmanaged<AQPropertyData<Any>>.fromOpaque(userData!).takeUnretainedValue()
	try! me.updatePropertyFromSource()
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public class AQPropertyUtility {
	public static func isRunning(_ queue: AudioQueueRef) -> AsyncStream<Bool> {
		return AsyncStream<Bool> { continuation in
			let observer = AQPropertyData<Bool>(property: .isRunning, queue: queue) { value in
				continuation.yield(value)
			}
			continuation.onTermination = { _ in
				observer.dispose()
			}
		}
	}

	public static func observe(_ queue: AudioQueueRef, _ property: AQProperty) -> AsyncStream<
		AQPropertyValue
	> {
		return AsyncStream<AQPropertyValue> { continuation in
			switch property {
			case .isRunning:
				let observer = AQPropertyData<Bool>(property: .isRunning, queue: queue) { value in
					continuation.yield(AQPropertyValue.isRunning(value))
				}
				continuation.onTermination = { _ in
					observer.dispose()
				}
			}
		}
	}
}

public final class AQPropertyData<T>: IDisposable, Sendable {
	public func dispose() {
		AudioQueueRemovePropertyListener(
			self.queue.value, mapPropertyToID(property), propertyListenerCallback,
			Unmanaged.passUnretained(self).toOpaque())
	}

	init(
		property: AQProperty, queue: AudioQueueRef,
		onChanged: @Sendable @escaping (_ value: T) -> Void
	) {
		self.property = property
		self.queue = SendableShim(queue)
		self.onChanged = onChanged

		AudioQueueAddPropertyListener(
			queue, mapPropertyToID(property), propertyListenerCallback,
			Unmanaged.passUnretained(self).toOpaque())
	}

	func updatePropertyFromSource() throws {
		let (data, dataSize) = preparePropertyData(self.property)
		let result = AudioQueueGetProperty(
			self.queue.value, mapPropertyToID(property), data, dataSize)
		guard result == 0 else {
			data.deallocate()
			dataSize.deallocate()
			throw AStreamError.coreAudioError(
				code: result, message: "Error getting property: \(self.property)")
		}
		let value: UnsafeMutablePointer<T> = cast(data)
		self.onChanged(value.pointee)

		data.deallocate()
		dataSize.deallocate()
	}

	let property: AQProperty
	let queue: SendableShim<AudioQueueRef>
	let onChanged: @Sendable (_ value: T) -> Void
}
