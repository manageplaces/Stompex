defmodule Stompex.FrameBuilder do
  @moduledoc """
  Provides functionality for building a stomp frame. This can be
  used for both sending and receiving frames, and simply generates
  a new Frame struct.

  All functions in the FrameBuilder module can be piped, with each
  returning the frame with the updates.

  ## Example

      import Stompex.FrameBuilder

      new_frame
      |> set_command("SEND")
      |> put_header("message-id", "123456abc")
      |> put_header("sender", "stompex")
      |> content_type("application/json")
      |> set_body("{ \"test\": \"test\",")
      |> append_body("\"test2\": \"test2\"}")
      |> finish_frame

  As a shortcut, frames can also be created via the command helpers.
  These will generate a frame with the command pre-populated. For example:

      $ send_frame()
        %Stompex.Frame{ cmd: "SEND" }

  **Please note** that there are only helpers available for client
  frames, and NOT server frames. Commands such as `CONNECTED` or
  `RECEIPT` if needed must be created explicitly, but should not
  be needed as Stompex does not implement a server.

  """
  use Stompex.Constants
  require Logger

  alias Stompex.Frame
  alias Stompex.Validator

  @eol "\n"

  @doc """
  Returns a blank frame. No properties will be set, and can
  be used for any type of STOMP frame required. In the event
  that a server frame is needed, this is the function you
  will need in conjuntion with `command/2`
  """
  def new_frame, do: %Frame{}

  @doc """
  Returns a new frame with the command pre-populated with
  SEND. This frame is used for sending new data to the
  STOMP server.
  """
  def send_frame, do: new_frame("SEND")

  @doc """
  Returns a new frame with the command pre-populated with
  SUBSCRIBE. This frame is used to subscribe stompex to
  a particular queue or topic on the STOMP server. In most
  situations, you will not need to use this frame directly,
  as Stompex will handle subscriptions for you.
  """
  def subscribe_frame, do: new_frame("SUBSCRIBE")

  @doc """
  Returns a new frame with the command pre-populated with
  UNSUBSCRIBE. This frame is used to unsubscribe Stompex
  from a particular queue or topic on the STOMP server.
  In most situations, you will not need to use this frame
  directly, as Stompex will handle subscriptions for you.
  """
  def unsubscribe_frame, do: new_frame("UNSUBSCRIBE")

  @doc """
  Returns a new frame with the command pre-populated with
  BEGIN. This frame is used to start a new transaction.
  In most situations, you will not need to use this frame
  directly, as Stompex will transactions for you.
  """
  def begin_frame, do: new_frame("BEGIN")

  @doc """
  Returns a new frame with the command pre-populated with
  COMMIT. This frame is used to commit a transaction.
  In most situations, you will not need to use this frame
  directly, as Stompex will handle transactions for you.
  """
  def commit_frame, do: new_frame("COMMIT")

  @doc """
  Returns a new frame with the command pre-populated with
  ABORT. This frame is used to rollback a transaction.
  In most situations, you will not need to use this frame
  directly, as Stompex will handle transactions for you.
  """
  def abort_frame, do: new_frame("ABORT")

  @doc """
  Returns a new frame with the command pre-populated with
  ACK. This frame is used to acknowledge a message from
  the STOMP server. In most situations, you will not need
  to use this frame directly, as Stompex will handle
  acknowledgements for you.
  """
  def ack_frame, do: new_frame("ACK")

  @doc """
  Returns a new frame with the command pre-populated with
  NACK. This frame is used to notify the server that the
  message was not consumed. In most situations, you will
  not need to use this frame directly, as Stompex will
  handle acknowledgements for you.

  **Pleast note** that NACK frames were introduced in
  STOMP v1.2. If you are connecting to a server that
  does not support this version of the specification,
  Stompex will simply ignore these frames.
  """
  def nack_frame, do: new_frame("NACK")

  @doc """
  Returns a new frame with the command pre-populated with
  DISCONNECT. This frame is used to inform the server that
  the client will be disconnecting. In most situations,
  you will not need to use this frame directly, as Stompex
  will handle the connection for you.
  """
  def disconnect_frame, do: new_frame("DISCONNECT")

  @doc """
  Returns a new frame with the command pre-populated with
  CONNECT. This frame is used as a handshake between the
  client and the server. In most situations, you will not
  need to use this frame directly, as Stompex will handle
  the connection for you.
  """
  def connect_frame(version \\ @default_version)
  def connect_frame(1.0), do: new_frame("CONNECT")
  def connect_frame(_version), do: new_frame("STOMP")

  @doc """
  Returns a new frame with the command pre-populated with
  STOMP. This frame is identical to the CONNECT frame, and
  should be used for connections to a server supporting
  version 1.1 or above. In most situations, you will not
  need to use this frame directly, as Stompex will handle
  the connection for you.
  """
  def stomp_frame, do: new_frame("STOMP")


  #
  # Create a new frame with the specified command.
  #
  defp new_frame(cmd) do
    new_frame()
    |> set_command(cmd)
  end

  @doc """
  Sets the command field of the frame supplied. This
  function will ensure that the command value supplied
  is a valid command. In the event that an invalid
  command is supplied, this function will do nothing,
  and simply return the frame it was supplied.
  """
  def set_command(frame, cmd) do
    case Validator.valid_command?(cmd) do
      true ->
        %{ frame | cmd: cmd }

      false ->
        Logger.warn("Ignoring `set_command/2` call. Command '#{cmd}' is invalid")
        frame
    end
  end

  @doc """
  Adds a new header to the supplied frame.
  If the header being added already exists, its current
  value will be replaced by the new value.
  """
  def put_header(frame, key, value) do
    %{ frame | headers: Map.merge(frame.headers, Validator.format_header(key, value)) }
  end

  @doc """
  Adds multiple headers to the supplied frame.

  This function will simply merge the map of headers supplied
  with the existing headers in the frame if any. As such, any
  headers that are already set that have the same key as those
  being added, will have their values overwritten.

  For adding a single header, see `put_header/3`.
  """
  def put_headers(frame, headers) do
    %{ frame | headers: Map.merge(frame.headers, headers)}
  end

  @doc """
  Sets the body of the supplied frame.
  **Please note** that this function will completely replace
  any existing contents in the body. If you wish to add to
  the existing body, then use `append_body/3` instead.
  """
  def set_body(frame, body) do
    %{ frame | body: body }
  end

  @doc """
  Appends the supplied string to the body of the supplied
  frame. By default, this function will also append a new
  line to the end of whatever is being appended. If you
  do not want this to happen, then you may pass a third
  argument to disable this:

      frame |> append_body("body")
      frame |> append_body("body", new_line: false)
  """
  def append_body(frame, body, opts \\ [new_line: true])
  def append_body(%{ body: nil } = frame, to_append, [new_line: false]) do
    set_body(frame, to_append)
  end
  def append_body(frame, body, new_line: false) do
    %{ frame | body: frame.body <> body }
  end
  def append_body(frame, body, new_line: true) do
    frame
    |> append_body(body, new_line: false)
    |> append_body(@eol, new_line: false)
  end


  @doc """
  Once the headers and body are finished, the frame must
  be finished before it can be used. Because the underlying
  connection used is an erlang library, the message must
  be converted to a chart list rather than a binary string.
  This function will append the terminating character, add
  a new line character, and then convert the frame into a
  character list.

  Please note that this function cannot be used to pipe
  into any of the other frame builder functions, as it
  does not return a frame.
  """
  @spec finish_frame(Stompex.Frame.t) :: charlist
  def finish_frame(frame) do
    frame
    |> append_body(<<0>>, new_line: false)
    |> append_body(@eol, new_line: false)
    |> to_string()
    |> to_char_list()
  end


  @doc """
  Once a frame has been received, this function should
  be called to clear out any trailing null characters
  or new lines from the command and body.

  **Note:** This should not be called multiple times.
  The receiving process is guaranteed to have trailing
  characters, so this function is safe to be used once,
  but any further use may start removing characters
  that are valid in the frames body.
  """
  @spec clean_frame(Stompex.Frame.t) :: Stompex.Frame.t
  def clean_frame(frame) do
    cleaned_body =
      frame.body
      |> String.trim_trailing()
      |> String.replace_suffix(<<0>>, "")

    frame
    |> set_command(String.trim_trailing(frame.cmd))
    |> set_body(cleaned_body)
  end

end
