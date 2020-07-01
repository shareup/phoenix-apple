# SocketTests

## constructor

- [x] sets defaults
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L24
	- `testSocketInit()`

- [x] supports closure or literal params
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L41
	- _not applicable_

- [x] overrides some defaults with options
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L49
	- `testSocketInitOverrides()`

## with Websocket

- [x] defaults to Websocket transport if available
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L83
	- _not applicable_

## protocol

- [ ] returns wss when location.protocol is https
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L95
	-

- [ ] returns ws when location.protocol is http
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L101
	-

## endpointURL

- [ ] returns endpoint for given full url
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L109
	-

- [ ] returns endpoint for given protocol-relative url
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L116
	-

- [ ] returns endpoint for given path on https host
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L123
	-

- [ ] returns endpoint for given path on http host
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L130
	-

## connect with WebSocket

- [x] establishes websocket connection with endpoint
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L153
	- `testSocketConnectAndDisconnect()`

- [x] sets callbacks for connection
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L161
	- `testSocketConnectDisconnectAndReconnect()`

- [x] is idempotent
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L187
	- `testSocketConnectIsNoOp()`

## connect with long poll

- [x] establishes long poll connection with endpoint
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L203
	- _not applicable_

- [x] sets callbacks for connection
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L212
	- _not applicable_

- [x] is idempotent
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L242
	- _not applicable_

## disconnect

- [x] removes existing connection
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L268
	- `testDisconnectTwiceOnlySendsMessagesOnce()`

- [x] calls callback
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L277
	- `testSocketIsClosed()`

- [x] calls connection close callback
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L287
	- `testSocketIsClosed()`

- [x] does not throw when no connection
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L297
	- `testDisconnectTwiceOnlySendsMessagesOnce()`

## connectionState

- [x] defaults to closed
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L309
	- `testSocketDefaultsToClosed()`

- [x] returns closed if readyState unrecognized
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L313
	- _not applicable_

- [x] returns connecting
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L320
	- `testSocketIsConnecting()`

- [x] returns open
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L328
	- `testSocketIsOpen()`

- [x] returns closing
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L336
	- `testSocketIsClosing()`

- [x] returns closed
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L344
	- `testSocketIsClosed()`

## channel

- [x] returns channel with given topic and params
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L360
	- `testChannelInitWithParams()`

- [x] adds channel to sockets channels list
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L368
	- `testChannelsAreTracked()`

## remove

- [x] removes given channel from channels
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L385
	- `testChannelsAreRemoved()`

## push

- [x] sends data to connection when connected
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L413
	- `testPushOntoSocket()`

- [x] buffers data when not connected
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L424
	- `testPushOntoDisconnectedSocketBuffers()`

## makeRef

- [x] returns next message ref
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L448
	- `testRefGeneratorReturnsCurrentAndNextRef()`

- [x] restarts for overflow
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L456
	- `testRefGeneratorRestartsForOverflow()`

## sendHeartbeat

- [x] closes socket when heartbeat is not ack'd within heartbeat window
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L470
	- `testHeartbeatTimeoutMovesSocketToClosedState()`

- [x] pushes heartbeat data when connected
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L481
	- `testPushesHeartbeatWhenConnected()`

- [x] no ops when not connected
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L491
	- `testHeartbeatIsNotSentWhenDisconnected()`

## flushSendBuffer

- [x] calls callbacks in buffer when connected
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L508
	- `testFlushesPushesOnOpen()`

- [x] empties sendBuffer
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L523
	- `testFlushesAllQueuedMessages()`

## onConnOpen

- [x] flushes the send buffer
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L551
	- `testFlushesPushesOnOpen()`

- [x] resets reconnectTimer
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L561
	- `testConnectionOpenResetsReconnectTimer()`

- [x] triggers onOpen callback
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L569
	- `testConnectionOpenPublishesOpenMessage()`

## onConnClose

- [x] schedules reconnectTimer timeout if normal close
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L598
	- `testSocketReconnectAfterRemoteClose()`

- [x] does not schedule reconnectTimer timeout if normal close after explicit disconnect
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L608
	- `testSocketDoesNotReconnectIfExplicitDisconnect()`

- [x] schedules reconnectTimer timeout if not normal close
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L618
	- `testSocketReconnectAfterRemoteException()`

- [x] schedules reconnectTimer timeout if connection cannot be made after a previous clean disconnect
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L628
	- `testSocketReconnectsAfterExplicitDisconnectAndThenConnect()`

- [x] triggers onClose callback
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L643
	- `testRemoteClosePublishesClose()`

- [ ] triggers channel error if joining
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L653
	- _we think this works but it's hard to test currently_

- [x] triggers channel error if joined
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L664
	- `testRemoteExceptionErrorsChannels()`
	- `testSocketCloseErrorsChannels()`

- [x] does not trigger channel error after leave
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L676
	- `testSocketCloseDoesNotErrorChannelsIfLeft()`

## onConnError

- [ ] triggers onClose callback
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L707
	-

- [ ] triggers channel error if joining
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L717
	-

- [ ] triggers channel error if joined
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L728
	-

- [ ] does not trigger channel error after leave
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L740
	-

## conConnMessage

- [x] parses raw message and triggers channel event
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L771
	- `testChannelReceivesMessages()`

- [x] triggers onMessage callback
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L788
	- `testSocketDecodesAndPublishesMessage()`

## custom encoder and decoder

- [x] encodes to JSON array by default
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L806
	- _not applicable_

- [x] allows custom encoding when using WebSocket transport
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L815
	- _not applicable_

- [x] forces JSON encoding when using LongPoll transport
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L824
	- _not applicable_

- [x] decodes JSON by default
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L834
	- _not applicable_

- [x] allows custom decoding when using WebSocket transport
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L843
	- _not applicable_

- [x] forces JSON decoding when using LongPoll transport
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/socket_test.js#L852
	- _not applicable_
