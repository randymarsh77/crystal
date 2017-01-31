import Foundation
import IDisposable
import Scope
import Sockets

public class StreamServer : IDisposable
{
	var stream: SynchronizedDataStreamWithMetadata<Double>
	var synchronizer: TimeSynchronizer
	var connections: Array<Connection>
	var tcpServer: TCPServer?

	public init(stream: SynchronizedDataStreamWithMetadata<Double>, port: UInt16)
	{
		self.stream = stream
		self.synchronizer = TimeSynchronizer()
		self.connections = Array<Connection>()
		self.tcpServer = TCPServer(port: port) { (socket) in
			self.addConnection(socket: socket)
		}
	}

	public func dispose() -> Void
	{
		for connection in self.connections {
			connection.dispose()
		}
		self.connections.removeAll()
		self.tcpServer!.dispose()
		self.tcpServer = nil
	}

	func addConnection(socket: Socket) -> Void
	{
		let token = self.synchronizer.addTarget(socket)
		let subscription = self.stream.addSubscriber { (data, metadata) in
			let (start, guess) = self.synchronizer.syncTarget(token: token, time: metadata)
			let header = SNSUtility.GenerateHeader(start: start, guess: guess)
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
