# Phoenix channels client for Apple OS's

## _(macOS, iOS, iPadOS, tvOS, and watchOS)_

A package for connecting to and interacting with Phoenix channels from Apple OSes written in Swift taking advantage of the built-in WebSocket support and Swift Concurrency.

The public interfaces of `Socket` and `Channel` are simple structs whose public methods are exposed as closures. The reason for this design is to make it easy to inject fake sockets and channels into your code for testing purposes.

The actual implementations of Phoenix socket and channel are `PhoenixSocket` and `PhoenixChannel`, but those are not available publicly. Rather, you can opt in to using them via the `Socket.production(url:)` factory. 

**Compatible with Phoenix channels vsn=2.0.0 only.**

## Installation

To use Phoenix, add a dependency to your Package.swift file:

```swift
let package = Package(
  dependencies: [
    .package(
      url: "https://github.com/shareup/phoenix-apple.git",
      from: "8.0.0"
    )
  ]
)
```

## Usage

```swift
import Phoenix

let socket = Socket.production(url: URL(string: "wss://example.com/socket")!)
await socket.connect()

let channel = await socket.channel("room:123", [:])

let messagesTask = Task {
  for await message in channel.messages() {
    print(message)
  }
}

let joinResponse = try await channel.join()

try await channel.send("one-off-message", [:])
let response = try await channel.request("message-needing-reply", [:])
try await channel.leave()

messagesTask.cancel()
```

## Tests

### Using Xcode

1. In your Terminal, navigate to the `phoenix-apple` directory
2. Open the `phoenix-apple` directory using Xcode
3. Make sure the build target is macOS
4. Product -> Test

### Using `swift test`

1. In your Terminal, navigate to the `phoenix-apple` directory
2. Run the tests using `swift test`
