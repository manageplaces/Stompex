# Future plans
--

Some plans on how Stompex will be refactored:

### Parser

Move frame parsing into a separate module, or series of modules to cater for
different stomp version depending on differences

### Builder

Provide a module for building up frames rather than interacting directly with structs.
This module will be imported. Example:

    import Stompex.FrameBuilder

    new_frame
    |> command(:send)
    |> put_header("key", "value")
    |> put_header("key2", "value2")
    |> put_headers(%{ "key3" => "value3" })
    |> content_type("application/json")
    |> body("test")
    |> append_body("more body")
    |> finish_frame

### FrameHandler

Most of this will be extracted into a parser. The `receive_frame/1` and
`send_frame/2` functions are both out of place here and should be put into
either the main stompex gen server, or into a separate module for handling
all TCP communication


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
