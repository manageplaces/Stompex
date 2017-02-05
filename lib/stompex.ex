defmodule Stompex do
  use Connection
  use Stompex.Api
  require Logger

  import Stompex.FrameBuilder

  @tcp_opts [:binary, active: false]

  @doc false
  def connect(_info, %{ sock: nil, host: host, port: port, timeout: timeout } = state) do
    case :gen_tcp.connect(to_char_list(host), port, @tcp_opts, timeout) do
      { :ok, sock } ->
        stomp_connect(sock, state)

      { :error, _ } ->
        { :backoff, 1000, state }
    end
  end

  @doc false
  def disconnect(info, %{ sock: sock, parser: parser } = state) do
    frame =
      disconnect_frame()
      |> to_string()
      |> to_char_list()

    { :close, from } = info
    Connection.reply(from, :ok)
    GenServer.stop(parser)

    case :gen_tcp.send(sock, frame) do
      :ok ->
        :gen_tcp.close(sock)
        { :reply, :ok, %{ state | sock: nil, parser: nil } }

      { :error, _ } = error ->
        { :stop, error, error }
    end

    { :noconnect, %{ state | sock: nil } }
  end



  defp stomp_connect(conn, state) do
    frame =
      connect_frame()
      |> put_header("host", state[:host])
      |> put_headers(state[:headers])
      |> to_string
      |> to_char_list

    with :ok <- :gen_tcp.send(conn, frame),
         { :ok, parser } <- Stompex.Parser.start_link(conn),
          { :ok, frame } <- Stompex.Parser.receive_frame(parser)
    do
      connected_with_frame(frame, %{ state | sock: conn, parser: parser})

    else
      error ->
        { :stop, "Error connecting to stomp server. #{inspect(error)}" }
    end

  end

  defp connected_with_frame(%{ cmd: "CONNECTED", headers: headers, parser: parser }, state) do
    case headers["version"] do
      nil ->
        # No version returned, so we're running on a version 1.0 server
        Logger.debug("STOMP server supplied no version. Reverting to version 1.0")
        Stompex.Parser.set_version(parser, 1.0)
        { :ok, %{ state | version: 1.0 } }

      version ->
        Logger.debug("Stompex using protocol version #{version}")
        Stompex.Parser.set_version(parser, version)
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
  def handle_call({ :subscribe, destination, headers }, _, %{ subscriptions: subscriptions } = state) do
    case Dict.has_key?(subscriptions, destination) do
      true ->
        { :reply, { :error, "You have already subscribed to this destination" }, state }
      false ->
        subscribe_to_destination(destination, headers, state)
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

  def handle_call(:close, from, state) do
    { :disconnect, { :close, from }, state }
  end


  def handle_cast({ :acknowledge, frame }, %{ sock: sock } = state) do
    frame =
      ack_frame()
      |> put_header("message-id", frame.headers["message-id"])
      |> put_header("subscription", frame.headers["subscription"])
      |> to_string
      |> to_char_list

    :gen_tcp.send(sock, frame)

    { :noreply, state }
  end

  def handle_cast({ :nack, _frame }, %{ version: 1.0 } = state ) do
    Logger.warn("'NACK' frame was requested, but is not valid for version 1.0 of the STOMP protocol. Ignoring")
    { :noreply, state }
  end
  def handle_cast({ :nack, frame }, %{ sock: sock } = state ) do
    frame =
      nack_frame()
      |> put_header("message-id", frame.headers["message-id"])
      |> put_header("subscription", frame.headers["subscription"])
      |> to_string
      |> to_char_list

    :gen_tcp.send(sock, frame)
    { :noreply, state }
  end

  def handle_cast({ :send_to_caller, send }, state) do
    { :noreply, %{ state | send_to_caller: send } }
  end


  def handle_info({ :parser, frame }, %{ send_to_caller: true, calling_process: process, parser: parser } = state) do
    dest = frame.headers["destination"]
    send(process, { :stompex, dest, frame })
    Stompex.Parser.next_frame(parser)

    { :noreply, state }
  end

  def handle_info({ :parser, _frame }, %{ send_to_caller: false, callbacks: %{} } = state) do
    Logger.warn("Frame received, but no callbacks registered. Discarding frame")
    { :noreply, state }
  end
  def handle_info({ :parser, frame }, %{ send_to_caller: false, callbacks: callbacks, parser: parser } = state) do
    dest = frame.headers["destination"]
    callbacks
    |> Dict.get(dest, [])
    |> Enum.each(fn(func) -> func.(frame) end)

    Stompex.Parser.next_frame(parser)

    { :noreply, state }
  end





  defp subscribe_to_destination(destination, headers, %{ sock: sock, subscription_id: id, subscriptions: subs } = state) do
    frame =
      subscribe_frame()
      |> put_header("id", headers["id"] || id)
      |> put_header("ack", headers["ack"] || "auto")
      |> put_header("destination", destination)


    state = %{ state | subscription_id: (id + 1) }

    case :gen_tcp.send(sock, to_char_list(to_string(frame))) do
      :ok ->
        # Great we've subscribed. Now keep track of it
        subscription = %{
          id: frame.headers[:id],
          ack: frame.headers[:ack]
        }

        Stompex.Parser.next_frame(state[:parser])

        { :reply, :ok, %{ state | subscriptions: Map.merge(subs, %{ destination => subscription })} }

      { :error, _ } = error ->
        { :noreply, error, error }
    end
  end

  defp unsubscribe_from_destination(destination, %{ sock: sock, subscriptions: subscriptions } = state) do
    subscription = subscriptions[destination]
    frame =
      unsubscribe_frame()
      |> put_header("id", subscription[:id])
      |> to_string
      |> to_char_list

    case :gen_tcp.send(sock, frame) do
      :ok ->
        { :noreply, %{ state | subscriptions: Map.delete(subscriptions, destination)}}

      { :error, _ } = error ->
        { :noreply, error }
    end
  end

end
