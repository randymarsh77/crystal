# Crystal
Low latency, synchronized, live audio streaming in Swift. Use with [Soundflower](https://github.com/mattingalls/Soundflower) or any other audio input source.

## Why
Think [Sonos](http://www.sonos.com/) but without all the expensive equipment or restricted audio sources.  More like [Airfoil](https://rogueamoeba.com/airfoil/) and/or/combined with the other software from [RogueAmoeba](https://rogueamoeba.com).

## Status

Approaching lower latency. Currently, system latency is set to 400ms but can work at 50ms if the network and target devices can support it. Total e2e latency is closer to 1s. System latency being time from record input callback to speaker and e2e being from time output is fed to Soundflower to speaker. Next step on this front is adaptive latency optimized by aggregated ping results. Then, internalizing a Soundflower driver to cut out some of the redundancy.

## Future / Roadmap

Add "networking", network discovery, multipeer/bluetooth.

Opt-in authenticated and encrypted streams with once tokens.

Multiple simultaneous (on-demand) format outputs.

Linux support for rPi.

Auto-configuring surround sound with OpenAL and iBeacons.

Video streams, synchronized with audio playback.

Metadata server.

## On Latency
I originally implemented file segmentation similar to HLS (because it worked "out of the box" on a rPi), and discovered first hand how terrible of a solution for low latency live streaming this was. Immediately, latency suffers from the length of the file segment. Currently, `astream`s latency pipeline is [any delay in SoundFlower]->[any delay in AudioQueue recording]->[network latency]->[buffering]. Given the excellent (and growing) support for HLS, it is still a more scalable solution if you can afford the latency hit.

## On Networking
The goal with "networking" is to enable clients to always be on and servers to go on and offline. Clients need to discover servers and visa versa. Media source(s), output(s), routing, controls, metadata should all be configurable as separate network nodes.  Configuration, authentication, metadata should happen over HTTP. Data transfer should happen over authenticated sockets. For example, one computer has a music library and is exposing itself as a source. A phone sees some options to start and control playback. The rPi detects that it should recieve and play audio. The phone changes the volume, skips a track, changes the configuration of which clients are recieving audio, etc. Joe Hacker can see one of these networks when peeping the WiFi/public api, but he can't control playback, and he can't initiate a client socket connection that results in payload data transfer.
