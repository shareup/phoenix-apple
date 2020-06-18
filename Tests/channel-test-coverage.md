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
	- `testSetsJoinedOnceToTrue()`

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

- [ ] succeeds before timeout
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L184
	- ``

- [ ] retries with backoff after timeout
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L206
	- ``

- [ ] with socket and join delay
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L233
	- ``

- [ ] with socket delay only
	- https://github.com/phoenixframework/phoenix/blob/ce8ec7eac3f1966926fd9d121d5a7d73ee35f897/assets/test/channel_test.js#L263
	- ``

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-

- [ ]
	-
