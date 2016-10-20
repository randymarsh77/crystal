import Foundation
import Scope

public class SynchronizedDataStream
{
	var syncQueue: DispatchQueue
	var subscribers: Array<Subscriber>

	public init()
	{
		self.syncQueue = DispatchQueue(label: "SDS")
		self.subscribers = Array<Subscriber>()
	}

	public func publish(chunk: Data) -> Void
	{
		self.syncQueue.async {
			for subscriber in self.subscribers {
				subscriber.publish(data: chunk)
			}
		}
	}

	public func addSubscriber(onData: @escaping (_ data: Data) -> Void) -> Scope
	{
		let subscriber = Subscriber(callback: onData)
		(self.syncQueue).async {
			self.subscribers.append(subscriber)
		}
		return Scope(dispose: { self.removeSubscriber(subscriber: subscriber) })
	}

	func removeSubscriber(subscriber: Subscriber) -> Void
	{
		self.syncQueue.async {
			let i = self.subscribers.index(where: { (x) -> Bool in
				return x === subscriber
			})
			self.subscribers.remove(at: i!)
		}
	}

	class Subscriber
	{
		var callback: (_ data: Data) -> Void
		var syncQueue: DispatchQueue

		internal init(callback: @escaping (_ data: Data) -> Void)
		{
			self.callback = callback
			self.syncQueue = DispatchQueue(label: "Subscriber")
		}

		internal func publish(data: Data) -> Void
		{
			self.syncQueue.async {
				self.callback(data)
			}
		}
	}
}

public class SynchronizedDataStreamWithMetadata<T>
{
	var syncQueue: DispatchQueue
	var subscribers: Array<Subscriber<T>>

	public init()
	{
		self.syncQueue = DispatchQueue(label: "SDCWM")
		self.subscribers = Array<Subscriber<T>>()
	}

	public func publish(chunk: Data, meta: T) -> Void
	{
		self.syncQueue.async {
			for subscriber in self.subscribers {
				subscriber.publish(data: chunk, meta: meta)
			}
		}
	}

	func removeSubscriber(subscriber: Subscriber<T>) -> Void
	{
		self.syncQueue.async {
			let i = self.subscribers.index(where: { (x) -> Bool in
				return x === subscriber
			})
			self.subscribers.remove(at: i!)
		}
	}

	public func addSubscriber(onData: @escaping (_ data: Data, _ meta: T) -> Void) -> Scope
	{
		let subscriber = Subscriber<T>(callback: onData)
		(self.syncQueue).async {
			self.subscribers.append(subscriber)
		}
		return Scope(dispose: { self.removeSubscriber(subscriber: subscriber) })
	}
}

class Subscriber<T>
{
	var callback: (_ data: Data, _ meta: T) -> Void
	var syncQueue: DispatchQueue

	internal init(callback: @escaping (_ data: Data, _ meta: T) -> Void)
	{
		self.callback = callback
		self.syncQueue = DispatchQueue(label: "Subscriber")
	}

	internal func publish(data: Data, meta: T) -> Void
	{
		(self.syncQueue).async {
			self.callback(data, meta)
		}
	}
}
