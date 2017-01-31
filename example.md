# Server

The following snippet implements a simple audio streaming server using Crystal. This code can be run as a Swift command line application / script.

- Audio is generated from the default input source.
- Audio is streamed from a tcp server listening on the specified port.
- A bonjour service is advertised.

```
import Foundation
import Bonjour
import Crystal
import Time
import Using

Time.Initialize()

let port = 4321
let settings = BroadcastSettings(
name: "host",
serviceType: .Unregistered(identifier: "_crystal"),
serviceProtocol: .TCP,
domain: .AnyDomain,
port: Int32(port))

using (AudioStreamGenerator()) { (generator: AudioStreamGenerator) in
using (StreamServer(stream: generator.stream, port: UInt16(port))) {
using (Bonjour.Broadcast(settings)) {
  getchar()
}}}

```

# Client

The following snippet implements a client that plays audio streaming from a server like in the example above. This code can be used in an iOS or Cocoa application, or slightly modified to run as a Swift command line applicaiton / script.

```
import AVFoundation
import Async
import Bonjour
import Crystal
import Sockets
import Time
import Using

...


Time.Initialize()
Async.Schedule(q: DispatchQueue.main)

let session = AVAudioSession.sharedInstance()
try! session.setCategory(AVAudioSessionCategoryPlayback)
try! session.setActive(true)

let qSettings = QuerySettings(
  serviceType: .Unregistered(identifier: "_crystal"),
  serviceProtocol: .TCP,
  domain: .AnyDomain
)

DispatchQueue.global(qos: .default).async {
  let services = await(Bonjour.FindAll(qSettings))
  if (services.count != 0) {
    let service = services[0]
    await(Bonjour.Resolve(service))
    let client = TCPClient(endpoint: service.getEndpointAddress()!)
    using ((try! client.tryConnect())!) { (socket: Socket) in
      socket.pong()
      _ = socket.createAudioStream()
        .pipe(to: AudioStreamPlayer().stream)

        await (UntilPigsFly())
    }
  } else {
    NSLog("No services found")
  }
}

func UntilPigsFly() -> Task<Void> {
  return async {
    Async.Suspend()
  }
}
```
