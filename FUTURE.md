# Future plans

THere are a number of thing missing from Stompex, so here is a brief list of
things that still need to be addded.

## Transactions

Provide really easy transaction support, ideally function based:

```elixir
Stompex.transaction do
end
```

or

```elixir
Stompex.transaction(conn, fn() ->
end)
```

## Two-way heartbeat support

Curerntly Stompex can receive heartbeats, but
cannot send them.

## Fully support all STOMP versions

## Increased test coverage

## Anything else specified in the STOMP specification

## Refactoring

Some plans on how Stompex will be refactored:

### Consider dropping `connection` library

I'm not convinced that it's providing any real benefit, and rather introducing
some complexity into the code. Consider whether or not this should be kept around
or removed.

## Stomp spec differences

- 1.0 is the baseline.

### STOMP 1.1

- Protocol negotiation
- Heartbeats
- NACK frame
- Virtual hosting
- STOMP frame

### STOMP 1.2

- Frame lines can end with carriage return AND new line, not just new line
- Message acknowledgements simplified, now using a dedicated header
- Repeated frame header entries
- Servers required to support STOMP frame
- content-length and content-type headers introduced
- connection lingering
- Scope and uniqueness of subscription and transaction identifiers
- Meaning of RECEIPT frame with regard to previous frame
