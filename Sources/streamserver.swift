import Foundation
import IDisposable
import Scope
import Sockets
import Time

public class StreamServer : IDisposable
{
	let stream: SynchronizedDataStreamWithMetadata<Time>
	let synchronizer = TimeSynchronizer()
	var tcpServer: TCPServer?
	var connections = [Connection]()

	public init(stream: SynchronizedDataStreamWithMetadata<Time>, port: UInt16) throws
	{
		self.stream = stream
		self.tcpServer = try TCPServer(options: ServerOptions(port: .Specific(port))) { (socket) in
			self.addConnection(socket: socket)
		}
	}

	public func dispose() -> Void
	{
		for connection in self.connections {
			connection.dispose()
		}
		self.connections.removeAll()
		self.tcpServer?.dispose()
		self.tcpServer = nil
	}

	func addConnection(socket: Socket) -> Void
	{
		let token = self.synchronizer.addTarget(socket)
		let subscription = self.stream.addSubscriber { (data, metadata) in
			let synchronization = self.synchronizer.syncTarget(token: token, time: metadata)
			let header = SNSUtility.GenerateHeader(synchronization: synchronization)
			socket.write(header)
			socket.write(data)
		}
		connections.append(Connection(streamSubscription: subscription, socket: socket))
	}

	class Connection
	{
		var subscription: Scope
		var socket: Socket
		var onErrorScope: Scope?

		internal init(streamSubscription: Scope, socket: Socket)
		{
			self.subscription = streamSubscription
			self.socket = socket
			self.onErrorScope = self.socket.registerErrorHandler() {
				print("socket error")
				self.dispose()
			}
		}

		internal func dispose() -> Void
		{
			self.subscription.dispose()
			self.socket.dispose()
		}
	}
}
