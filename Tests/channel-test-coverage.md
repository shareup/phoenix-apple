# ChannelTests

## constructor

- [x] sets defaults
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L36
	- `testChannelInit()`

- [x] sets up joinPush objec with literal params
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L49
	- `testJoinPushPayload()`

- [x] sets up joinPush objec with closure params
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L59
	- `testJoinPushBlockPayload()`

## updating join params

- [x] can update the join params
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L76
	- `testJoinPushBlockPayload()`

## join

- [x] sets state to joining
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L105
	- `testIsJoiningAfterJoin()`

- [x] sets joinedOnce to true
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L111
	- _not applicable_

- [x] throws if attempting to join multiple times
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L119
	- `testJoinTwiceIsNoOp()`
	- **Our behavior is the opposite. We do not throw if a channel is joined twice.**

- [x] triggers socket push with channel params
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L125
	- `testJoinPushParamsMakeItToServer()`

- [x] can set timeout on joinPush
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L141
	- `testJoinCanHaveTimeout()`

- [x] leaves existings duplicate topic on new join
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L152
	- `testJoinSameTopicTwiceReturnsSameChannel()`
	- **Our behavior is different here. Joining an already-joined topic returns the original channel.**

## timeout behavior

- [x] succeeds before timeout
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L184
	- `testJoinSucceedsIfBeforeTimeout()`

- [x] retries with backoff after timeout
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L206
	- `testJoinRetriesWithBackoffIfTimeout()`

- [x] with socket and join delay
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L233
	- `testChannelConnectsAfterSocketAndJoinDelay()`

- [x] with socket delay only
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L263
	- `testChannelConnectsAfterSocketDelay()`

## joinPush

### receives 'ok'

- [x] sets channel state to joined
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L333
	- `testSetsChannelStateToJoinedAfterSuccessfulJoin()`

- [x] triggers receive('ok') callback after ok response
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L341
	- `testSetsChannelStateToJoinedAfterSuccessfulJoin()`
	- _all responses are funneled to the channel's observers_

- [x] triggers receive('ok') callback if ok response already received
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L351
	- _not applicable because our callbacks are only sent when joining from the closed state_

- [x] does not trigger other receive callbacks after ok response
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L361
	- `testOnlyReceivesSuccessfulCallbackFromSuccessfulJoin()`
	- _all responses are funneled to the channel's observers_

- [x] clears timeoutTimer
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L376
	- `testResetsJoinTimerAfterSuccessfulJoin()`

- [x] sets receivedResp
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L384
	- `testSetsChannelStateToJoinedAfterSuccessfulJoin()`
	- _all responses are funneled to the channel's observers_

- [x] removes channel bindings
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L392
	- _not applicable_

- [x] sets channel state to joined
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L402
	- `testSetsChannelStateToJoinedAfterSuccessfulJoin()`

- [x] resets channel rejoinTimer
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L408
	- `testResetsJoinTimerAfterSuccessfulJoin()`

- [x] sends and empties channel's buffered pushEvents
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L418
	- `testSendsAllBufferedMessagesAfterSuccessfulJoin()`

### receives 'timeout'

- [x] triggers receive('timeout') callback after ok response
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L444
	- `testReceivesCorrectErrorAfterJoinTimeout()`

- [x] does not trigger other receive callbacks after timeout response
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L454
	- `testOnlyReceivesTimeoutErrorAfterJoinTimeout()`

- [x] schedules rejoinTimer timeout
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L473
	- `testSchedulesRejoinTimerAfterJoinTimeout()`

### receives 'error'

- [x] triggers receive('error') callback after error response
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L489
	- `testReceivesErrorAfterJoinError()`

- [x] triggers receive('error') callback if error response already received
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L501
	- `testReceivesErrorAfterJoinError()`
	- _all responses are funneled to the channel's observers_

- [x] does not trigger other receive callbacks after error response
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L511
	- `testOnlyReceivesErrorResponseAfterJoinError()`

- [x] clears timeoutTimer
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L532
	- `testClearsTimeoutTimerAfterJoinError()`

- [x] sets receivedResp with error trigger after binding
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L540
	- _not applicable_

- [x] sets receivedResp with error trigger before binding
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L551
	- _not applicable_

- [x] does not set channel state to joined
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L561
	- `testDoesNotSetChannelStateToJoinedAfterJoinError()`

- [x] does not trigger channel's buffered pushEvents
	- https://github.com/phoenixframework/phoenix/blob/496627f2f7bbe92fc481bad81a59dd89d8205508/assets/test/channel_test.js#L567
	- `testDoesNotSendAnyBufferedMessagesAfterJoinError()`

## onError

- [x] sets state to 'errored'
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L603
	- `testReceivesErrorAfterJoinError()`

- [x] does not trigger redundant errors during backoff
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L611
	- `testOnlyReceivesErrorResponseAfterJoinError()`

- [x] does not rejoin if channel leaving
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L627
	- `testDoesNotRejoinChannelAfterLeaving()`

- [x] does not rejoin if channel closed
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L643
	- `testDoesNotRejoinChannelAfterClosing()`

- [x] triggers additional callbacks after join
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L659
	- `testChannelSendsChannelErrorsToSubscribersAfterJoin()`

## onClose

- [x] sets state to 'closed'
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L694
	- `testClosingChannelSetsStateToClosed()`

- [x] does not rejoin
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L702
	- `testChannelDoesNotRejoinAfterClosing()`

- [x] triggers additional callbacks
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L714
	- `testClosingChannelSetsStateToClosed()`

- [x] removes channel from socket
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L725
	- `testChannelIsRemovedFromSocketsListOfChannelsAfterClose()`

## onMessage

- [x] returns payload by default
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L742
	- `testIncomingMessageIncludesPayload()`

## canPush

- [x] returns true when socket connected and channel joined
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L757
	- `testCanPushIsTrueWhenSocketAndChannelAreConnected()`

- [x] otherwise returns false
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L764
	- `testCanPushIsFalseWhenSocketIsDisconnectedOrChannelIsNotJoined()`

## on

- [x] sets up callback for event
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L792
	- `testCallsCallbackButDoesNotNotifySubscriberForReply()`

- [x] other event callbacks are ignored
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L805
	- `testDoesNotCallCallbackForOtherMessages()`

- [x] generates unique refs for callbacks
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L820
	- `testChannelGeneratesUniqueRefsForEachEvent()`

- [x] calls all callbacks for event if they modified during event processing
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L826
	- _not applicable because we don't allow modifying events_

## off

- [x] removes all callbacks for event
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L848
	- `testRemovingSubscriberBeforeEventIsPushedPreventsNotification()`

- [x] removes callback by its ref
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L867
	- _not applicable because callbacks can't be removed after being added_

## push

- [x] sends push event when successfully joined
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L911
	- `testSendsPushEventAfterJoiningChannel()`

- [x] enqueues push event to be sent once join has succeeded
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L918
	- `testEnqueuesPushEventToBeSentWhenChannelIsJoined()`

- [x] does not push if channel join times out
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L930
	- `testDoesNotPushIfChannelJoinTimesOut()`

- [x] uses channel timeout by default
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L942
	- `testPushesUseChannelTimeoutByDefault()`

- [x] accepts timeout arg
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L956
	- `testPushesCanAcceptCustomTimeout()`
	- `testPushesTimeoutAfterCustomTimeout()`

- [x] does not time out after receiving 'ok'
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L970
	- `testPushDoesNotTimeoutAfterReceivingReply()`

- [x] throws if channel has not been joined
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L985
	- _not applicable because we buffer events until the channel is joined_

## leave

- [x] unsubscribes from server events
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1009
	- `testLeaveUnsubscribesFromServerEvents()`

- [x] closes channel on 'ok' from server
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1024
	- `testClosesChannelAfterReceivingOkResponseFromServer()`

- [x] sets state to closed on 'ok' event
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1034
	- `testClosesChannelAfterReceivingOkResponseFromServer()`

- [x] sets state to leaving initially
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1046
	- `testChannelSetsStateToLeaving()`

- [x] closes channel on 'timeout'
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1054
	- `testClosesChannelOnTimeoutOfLeavePush()`

- [x] accepts timeout arg
	- https://github.com/phoenixframework/phoenix/blob/118999e0fd8e8192155b787b4b71e3eb3719e7e5/assets/test/channel_test.js#L1062
	- `testClosesChannelOnTimeoutOfLeavePush()`
