import Foundation
import IDisposable
import Scope
import Sockets
import Time

@available(iOS 13.0, *)
@available(macOS 10.15.0, *)
public final actor StreamServer: Sendable, IAsyncDisposable {
	let stream: AsyncStream<SynchronizedAudioChunk>
	let synchronizer = TimeSynchronizer()
	var tcpServer: TCPServer?
	var connections = [Connection]()

	public init(stream: AsyncStream<SynchronizedAudioChunk>, port: UInt16) async throws {
		self.stream = stream
		tcpServer = try TCPServer(options: ServerOptions(port: .specific(port))) { (socket) in
			await self.addConnection(socket: socket)
		}
	}

	public func dispose() async {
		for connection in self.connections {
			await connection.dispose()
		}
		self.connections.removeAll()
		await tcpServer?.dispose()
		tcpServer = nil
	}

	func addConnection(socket: Socket) async {
		let t = Task {
			let token = await self.synchronizer.addTarget(socket)
			for await data in self.stream {
				let synchronization = await self.synchronizer.syncTarget(
					token: token, time: data.time)
				let header = SNSUtility.generateHeader(synchronization: synchronization)

				// TODO: Combine into one write
				await socket.write(header)
				await socket.write(data.chunk)
			}
		}
		let subscription = Scope {
			t.cancel()
		}
		let connection = Connection(streamSubscription: subscription, socket: socket)
		_ = await socket.registerErrorHandler {
			print("socket error")
			await connection.dispose()
		}

		connections.append(connection)
	}

	@available(iOS 13.0.0, *)
	final class Connection: Sendable, IAsyncDisposable {
		let subscription: Scope
		let socket: Socket

		internal init(streamSubscription: Scope, socket: Socket) {
			self.subscription = streamSubscription
			self.socket = socket
		}

		internal func dispose() async {
			await self.subscription.dispose()
			await self.socket.dispose()
		}
	}
}
