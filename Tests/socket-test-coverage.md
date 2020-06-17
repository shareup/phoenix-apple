# SocketTests

## constructor

- [x] sets defaults
	- testSocketInit()

- [x] overrides some defaults with options
	- testSocketInitOverrides()

- [x] with Websocket
	- _not applicable_

## protocol

- [ ] returns wss when location.protocol is https
	-

- [ ] returns ws when location.protocol is http
	-

## endpointURL

- [ ] returns endpoint for given full url
	-

- [ ] returns endpoint for given protocol-relative url
	-

- [ ] returns endpoint for given path on https host
	-

- [ ] returns endpoint for given path on http host
	-

## connect with WebSocket

- [x] establishes websocket connection with endpoint
	- testSocketConnectAndDisconnect()

- [x] sets callbacks for connection
	- testSocketConnectDisconnectAndReconnect()

- [x] is idempotent
	- testSocketConnectIsNoOp()

## connect with long poll

- [x] establishes long poll connection with endpoint
	- _not applicable_

- [x] sets callbacks for connection
	- _not applicable_

- [x] is idempotent
	- _not applicable_

## disconnect

- [x] removes existing connection
	- testDisconnectTwiceOnlySendsMessagesOnce()

- [x] calls callback
	- testSocketIsClosed()

- [x] calls connection close callback
	- testSocketIsClosed()

- [x] does not throw when no connection
	- testDisconnectTwiceOnlySendsMessagesOnce()

## connectionState

- [x] defaults to closed
	- testSocketDefaultsToClosed()

- [x] returns closed if readyState unrecognized
	- _not applicable_

- [x] returns connecting
	- testSocketIsConnecting()

- [x] returns open
	- testSocketIsOpen()

- [x] returns closing
	- testSocketIsClosing()

- [x] returns closed
	- testSocketIsClosed()

## channel

- [x] returns channel with given topic and params
	- testChannelInitWithParams()

- [x] adds channel to sockets channels list
	- testChannelsAreTracked()

- [x] removes given channel from channels
	- testChannelsAreRemoved()

## push

- [x] sends data to connection when connected
	- testPushOntoSocket()

- [x] buffers data when not connected
	- testPushOntoDisconnectedSocketBuffers()

## makeRef

- [x] returns next message ref
	- testRefGeneratorReturnsCurrentAndNextRef()

- [x] restarts for overflow
	- testRefGeneratorRestartsForOverflow()

## sendHeartbeat

- [x] closes socket when heartbeat is not ack'd within heartbeat window
	- testHeartbeatTimeoutMovesSocketToClosedState()

- [x] pushes heartbeat data when connected
	- testPushesHeartbeatWhenConnected()

- [x] no ops when not connected
	- testHeartbeatIsNotSentWhenDisconnected()

## flushSendBuffer

- [x] calls callbacks in buffer when connected
	- testFlushesPushesOnOpen()

- [x] empties sendBuffer
	- testFlushesAllQueuedMessages()

## onConnOpen

- [x] flushes the send buffer
	- testFlushesPushesOnOpen()

- [x] resets reconnectTimer
	- testConnectionOpenResetsReconnectTimer()

- [x] triggers onOpen callback
	- testConnectionOpenPublishesOpenMessage()

## onConnClose

- [x] schedules reconnectTimer timeout if normal close
	- testSocketReconnectAfterRemoteClose()

- [x] does not schedule reconnectTimer timeout if normal close after explicit disconnect
	- testSocketDoesNotReconnectIfExplicitDisconnect()

- [x] schedules reconnectTimer timeout if not normal close
	- testSocketReconnectAfterRemoteException()

- [x] schedules reconnectTimer timeout if connection cannot be made after a previous clean disconnect
	- testSocketReconnectsAfterExplicitDisconnectAndThenConnect()

- [x] triggers onClose callback
	- testRemoteClosePublishesClose()

- [ ] triggers channel error if joining
	-

- [x] triggers channel error if joined
	- testRemoteExceptionErrorsChannels()
	- testSocketCloseErrorsChannels()

- [x] does not trigger channel error after leave
	- testSocketCloseDoesNotErrorChannelsIfLeft()

- [x] parses raw message and triggers channel event
	- testChannelReceivesMessages()

- [x] triggers onMessage callback
	- testSocketDecodesAndPublishesMessage()

## custom encoder and decoder

- [x] encodes to JSON array by default
	- _not applicable_

- [x] allows custom encoding when using WebSocket transport
	- _not applicable_

- [x] forces JSON encoding when using LongPoll transport
	- _not applicable_

- [x] decodes JSON by default
	- _not applicable_

- [x] allows custom decoding when using WebSocket transport
	- _not applicable_

- [x] forces JSON decoding when using LongPoll transport
	- _not applicable_
