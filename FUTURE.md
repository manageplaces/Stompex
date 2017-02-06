# Future plans
--

### transactions

Provide really easy transaction support, ideally function based:

    Stompex.transaction do
    end

or

    Stompex.transaction(conn, fn() ->
    end)

Some plans on how Stompex will be refactored:

### Consider dropping `connection` library

I'm not convinced that it's providing any real benefit, and rather introducing
some complexity into the code. Consider whether or not this should be kept around
or removed.


### Stomp spec differences

##### 1.0 is the baseline

##### 1.1
  Protocol negotiation
  Heartbeats
  NACK frame
  Virtual hosting
  STOMP frame

##### 1.2
  Frame lines can end with carriage return AND new line, not just new line
  Message acknowledgements simplified, now using a dedicated header
  Repeated frame header entries
  Servers required to support STOMP frame
  content-length and content-type headers introduced
  connection lingering
  Scope and uniqueness of subscription and transaction identifiers
  Meaning of RECEIPT frame with regard to previous frame
