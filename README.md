# Phoenix channels client for Apple OS's

## _(macOS, iOS, iPadOS, tvOS, and watchOS)_

A package for connecting to and interacting with Phoenix channels from Apple OS's written in Swift taking advantage of the built in `Websocket` support and `Combine` for publishing events to downstream consumers.

**Compatible with Phoenix channels vsn=2.0.0 only.**

## Tests

### Using Xcode

1. In your Terminal, navigate to the `phoenix-apple` directory
2. Start the Phoenix server using `./start-server`
3. Open the `phoenix-apple` directory using Xcode
4. Make sure the build target is macOS
5. Product -> Test

### Using `swift test`

1. In your Terminal, navigate to the `phoenix-apple` directory
2. Start the Phoenix server using `./start-server`
3. Open the `phoenix-apple` directory in another Terminal window
4. Run the tests using `swift test`

## Running sample phoenix-js client

1. In your Terminal, navigate to the `phoenix-apple` directory
2. Start the Phoenix server using `./start-server`
3. In a new Terminal tab, navigate to the `phoenix-apple` directory
4. Start the `phoenix-js` cleint using `./start-phoenix-js`
5. Open the developer console in the just-opened Web browser window and send commands to the client using standard JavaScript 
