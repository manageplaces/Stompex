defmodule Stompex do
  @moduledoc """
  Stompex is a pure Elixir library for connecting to STOMP
  servers.

  ## Configuration

  Stompex provides a number of functions for setting up the
  initial connection. Two of these allow you to provide 
  a number of options to tailer the connection to your needs.
  
  Below is a list of configuration options available.

  
  - `:host` - The host address of the STOMP server.
  - `:port` - The port of the STOMP server. Defaults to 61618
  - `:login` - The username required to connect to the server.
  - `:passcode` - The password required to connect to the server.
  - `:headers` - A map of headers to send on connection.

  If the server you're connecting to requires a secure connection,
  the following options can be used.

  - `:secure` - Whether or not the server requires a secure connection.
  - `:ssl_opts` - A keyword list of options. The options available here are described in the erlang docs http://erlang.org/doc/man/ssl.html under the `ssl_options()` data type.

  For configuration in your own applications mix config file, 
  the options should be put under the `:stompex` key. 

  #### Examples

  - A basic configuration

      use Mix.Config

      config :stompex,
        host: "localhost",
        port: 61610,
        login: "username",
        passcode: "password"

  - A secure connection with default options

      use Mix.Config

      config :stompex,
        host: "localhost",
        port: 61610,
        login: "username",
        passcode: "password",

        secure: true

  - A secure connection with custom certificates

      use Mix.Config

      config :stompex,
        host: "localhost",
        port: 61610,
        login: "username",
        passcode: "password",

        secure: true,
        ssl_opts: [
          certfile: "/path/to/cert",
          cacertfile: "/path/to/ca"
        ]

  """

  use Connection
  use Stompex.Api
  require Logger

  import Stompex.FrameBuilder

  alias Stompex.Connection, as: Con

  @tcp_opts [:binary, active: false]

  @doc false
  def connect(_info, %{ secure: secure, host: host, port: port, timeout: timeout } = state) do
    conn_opts = case secure do
      true -> [ state.ssl_opts | @tcp_opts ]
      false -> @tcp_opts
    end
    
    case Con.start_link(host, port, secure, conn_opts, timeout) do
      { :ok, pid } ->
        stomp_connect(%{ state | conn: pid })

      { :error, _ } ->
        { :backoff, 1000, state }
    end
  end

  @doc false
  def disconnect(info, %{ conn: conn, receiver: receiver } = state) do
    frame =
      disconnect_frame()
      |> finish_frame()

    { :close, from } = info
    Connection.reply(from, :ok)
    GenServer.stop(receiver)

    case Con.send_frame(conn, frame) do
      :ok ->
        Con.close(conn)
        { :reply, :ok, %{ state | conn: nil, receiver: nil } }

      { :error, _ } = error ->
        GenServer.stop(conn)
        { :stop, error, error }
    end

    { :noconnect, %{ state | conn: nil } }
  end



  defp stomp_connect(%{ conn: conn } = state) do
    frame =
      connect_frame(state.version)
      |> put_header("host", state.host)
      |> put_headers(state.headers)
      |> finish_frame()

    with :ok <- Con.send_frame(conn, frame),
         { :ok, receiver } <- Stompex.Receiver.start_link(conn),
         { :ok, frame } <- Stompex.Receiver.receive_frame(receiver)
    do
      connected_with_frame(frame, %{ state | conn: conn, receiver: receiver })

    else
      error ->
        { :stop, "Error connecting to stomp server. #{inspect(error)}" }
    end

  end

  defp connected_with_frame(%{ cmd: "CONNECTED", headers: headers }, %{ receiver: receiver } = state) do
    IO.inspect(headers)
    case headers["version"] do
      nil ->
        # No version returned, so we're running on a version 1.0 server
        Logger.debug("STOMP server supplied no version. Reverting to version 1.0")
        Stompex.Receiver.set_version(receiver, 1.0)
        { :ok, %{ state | version: 1.0 } }

      version ->
        Logger.debug("Stompex using protocol version #{version}")
        Stompex.Receiver.set_version(receiver, version)
        { :ok, %{ state | version: version } }
    end
  end
  defp connected_with_frame(%{ cmd: "ERROR", headers: headers }, _state) do
    error = headers["message"] || "Server rejected connection"
    { :stop, error, error }
  end
  defp connected_with_frame(_frame, _state) do
    error = "Server rejected connection"
    { :stop, error, error }
  end


  @doc false
  def handle_call({ :register_callback, destination, func }, _, %{ callbacks: callbacks } = state) do
    dest_callbacks = Dict.get(callbacks, destination, []) ++ [func]
    callbacks = case Dict.has_key?(callbacks, destination) do
      true -> %{ callbacks | destination => dest_callbacks}
      false -> Map.merge(callbacks, %{ destination => dest_callbacks })
    end

    { :reply, :ok, %{ state | callbacks: callbacks }}
  end


  @doc """
  Removes a callback function for a given
  destination.

  This function should not be called directly.
  Instead, please use the `remove_callback/3`
  function instead.
  """
  def handle_call({ :remove_callback, destination, func }, _, %{ callbacks: callbacks } = state) do
    dest_callbacks = Dict.get(callbacks, destination, [])
    dest_callbacks = List.delete(dest_callbacks, func)

    callbacks = cond do
      Dict.has_key?(callbacks, destination) && dest_callbacks == [] ->
        Map.delete(callbacks, destination)

      dest_callbacks != [] ->
        %{ callbacks | destination => dest_callbacks }

      true -> callbacks
    end
    { :reply, :ok, %{ state | callbacks: callbacks }}
  end

  @doc false
  def handle_call({ :subscribe, destination, headers, opts }, _, %{ subscriptions: subscriptions } = state) do
    case Dict.has_key?(subscriptions, destination) do
      true ->
        { :reply, { :error, "You have already subscribed to this destination" }, state }
      false ->
        subscribe_to_destination(destination, headers, opts, state)
    end
  end

  @doc false
  def handle_call({ :unsubscribe, destination }, _, %{ subscriptions: subscriptions } = state) do
    case Dict.has_key?(subscriptions, destination) do
      true ->
        unsubscribe_from_destination(destination, state)
      false ->
        { :reply, { :error, "You are not subscribed to this destination" }, state }
    end
  end

  @doc false
  def handle_call(:close, from, state) do
    { :disconnect, { :close, from }, state }
  end

  @doc false
  def handle_call({ :send, destination, message }, %{ conn: conn } = state) do
    frame =
      send_frame()
      |> put_header("destination", destination)
      |> put_header("content-length", byte_size(message))
      |> set_body(message)
      |> finish_frame()

    response = Con.send_frame(conn, frame)
    { :reply, response, state }
  end




  @doc false
  def handle_cast({ :acknowledge, frame }, %{ conn: conn, version: version } = state) do
    frame =
      ack_frame()
      |> put_header(Stompex.Validator.ack_header(version), frame.headers["message-id"])
      |> put_header("subscription", frame.headers["subscription"])
      |> finish_frame()

    Con.send_frame(conn, frame)

    { :noreply, state }
  end
  @doc false
  def handle_cast({ :nack, _frame }, %{ version: 1.0 } = state ) do
    Logger.warn("'NACK' frame was requested, but is not valid for version 1.0 of the STOMP protocol. Ignoring")
    { :noreply, state }
  end
  @doc false
  def handle_cast({ :nack, frame }, %{ conn: conn, version: version } = state ) do
    frame =
      nack_frame()
      |> put_header(Stompex.Validator.ack_header(version), frame.headers["message-id"])
      |> put_header("subscription", frame.headers["subscription"])
      |> finish_frame()

    Con.send_frame(conn, frame)
    { :noreply, state }
  end

  @doc false
  def handle_cast({ :send_to_caller, send }, state) do
    { :noreply, %{ state | send_to_caller: send } }
  end







  @doc false
  def handle_info({ :receiver, frame }, %{ send_to_caller: true, calling_process: process, receiver: receiver } = state) do
    dest = frame.headers["destination"]
    frame = decompress_frame(frame, dest, state)

    send(process, { :stompex, dest, frame })
    Stompex.Receiver.next_frame(receiver)

    { :noreply, state }
  end

  @doc false
  def handle_info({ :receiver, frame }, %{ send_to_caller: false, callbacks: callbacks, receiver: receiver } = state) do
    dest = frame.headers["destination"]
    frame = decompress_frame(frame, dest, state)

    callbacks
    |> Dict.get(dest, [])
    |> Enum.each(fn(func) -> func.(frame) end)

    Stompex.Receiver.next_frame(receiver)

    { :noreply, state }
  end





  defp subscribe_to_destination(destination, headers, opts, %{ conn: conn, subscription_id: id, subscriptions: subs } = state) do
    frame =
      subscribe_frame()
      |> put_header("id", headers["id"] || id)
      |> put_header("ack", headers["ack"] || "auto")
      |> put_header("destination", destination)


    state = %{ state | subscription_id: (id + 1) }

    case Con.send_frame(conn, finish_frame(frame)) do
      :ok ->
        # Great we've subscribed. Now keep track of it
        subscription = %{
          id: frame.headers[:id],
          ack: frame.headers[:ack],
          compressed: Keyword.get(opts, :compressed, false)
        }

        Stompex.Receiver.next_frame(state.receiver)
        
        { :reply, :ok, %{ state | subscriptions: Map.merge(subs, %{ destination => subscription })} }

      { :error, _ } = error ->
        { :noreply, error, error }
    end
  end

  defp unsubscribe_from_destination(destination, %{ conn: conn, subscriptions: subscriptions } = state) do
    subscription = subscriptions[destination]
    frame =
      unsubscribe_frame()
      |> put_header("id", subscription[:id])
      |> finish_frame()

    case Con.send_frame(conn, frame) do
      :ok ->
        { :noreply, %{ state | subscriptions: Map.delete(subscriptions, destination)}}

      { :error, _ } = error ->
        { :noreply, error }
    end
  end


  defp decompress_frame(frame, dest, %{ subscriptions: subs }) do
    subscription = subs[dest]
    IO.inspect(frame)
    case subscription.compressed do
      true ->
        frame
        |> set_body(:zlib.gunzip(frame.body))

      false ->
        frame
    end
  end

end
