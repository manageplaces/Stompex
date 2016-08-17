defmodule Stompex do

  use Connection
  alias Stompex.FrameBuilder, as: FB
  alias Stompex.FrameHandler, as: FH

  @connection_timeout 10_000
  @default_stomp_port 61_613

  def start_link(host, port, login, passcode, headers, timeout \\ @connection_timeout) do
    Connection.start_link(__MODULE__, { host, port, login, passcode, headers, timeout, self() })
  end

  def init({ host, port, login, passcode, headers, timeout, calling_process }) do
    headers = Map.merge(%{ "accept-version" => "1.2", "login" => login, "passcode" => passcode }, headers)
    state = %{
      sock: nil,
      host: host,
      port: port,
      headers: headers,
      timeout: timeout,
      callbacks: %{},
      subscriptions: %{},
      subscription_id: 0,
      pending_frame: nil,
      calling_process: calling_process,
      send_to_caller: false
    }

    { :connect, :init, state }
  end

  @doc """
  Connects to a remote STOMP server using the application
  configuration.

  ## Configuration

  In order for this function to work correctly, the
  application must provide the `:stompex` configuration.

  Below is an example of the most basic configuration
  block that is required

      config :stompex,
        host: "host@stompserver.com",
        login: "login",
        passcode: "passcode"

  """
  def connect do
    env       = Application.get_all_env(:stompex)
    host      = env[:host]
    port      = env[:port] || @default_stomp_port
    login     = env[:login] || ""
    passcode  = env[:passcode] || ""
    headers   = env[:headers] || %{}

    Stompex.start_link(host, port, login, passcode, headers)
  end

  @doc """
  Connects to a remote STOMP server using the provided
  credentials and server details.

  ## Example

      Stompex.connect("host@stompserver.com", 61613, "user", "pass")

  Connections made via this function will default to
  STOMP version 1.2, and not have any heartbeat functionality.
  If this is required, the `connect/5` function should be
  used instead.

  """
  def connect(host, port, login, passcode) do
    Stompex.start_link(host, port, login, passcode, %{})
  end

  @doc """
  Connects to a remote STOMP server using the provided
  credentials and server details. This function also
  allows you to supply any headers that your server may
  require on connection.

  ## Examples

      Stompex.connect("host@stompserver.com", 61613, "user", "pass", %{ "accept-version" => 1.2 })
      Stompex.connect("host@stompserver.com", 61613, "user", "pass", %{ "accept-version" => 1.2, "heartbeat" => "100,100" })
      Stompex.connect("host@stompserver.com", 61613, "user", "pass", %{})

  Please note that if the `accept-version` header is not provided,
  it will be set to `1.2` by default.

  """
  def connect(host, port, login, passcode, headers) do
    Stompex.start_link(host, port, login, passcode, headers)
  end

  def reconnect(conn) do
    Connection.call(conn, :reconnect)
  end


  @doc """
  """
  def disconnect(conn) do
    Connection.call(conn, :close)
  end


  @doc """
  Subscribes to a specific queue or topic. Once subscribed,
  any messages received from the server will be sent to the
  handlers if configured.

  This function will default the subscription to not require
  acknowledgements by setting the `ack` header to `auto`. If
  your server requires acknowledgement of messages, use the
  `subscribe/3` function instead.
  """
  def subscribe(conn, destination) do
    Stompex.subscribe(conn, destination, %{ "ack" => "auto" })
  end

  @doc """
  Subscribes to a specific queue or topic. Once subscribed,
  any messages received from the server will be sent to the
  handlers if configured.

  This function allows you to specify any headers that are
  required by your server. By default, the `id` header will
  be automatically generated, but you may specify your own
  if required.

  One important header you may wish to specify is the `ack`
  header which defines whether or not you must explicitly
  acknowledge the receipt of a message. By default, this is
  set to `auto`, but can be set to one of the following
  options:

  - auto
  - client
  - client-individual

  When set to `auto`, you are not required to send an acknowledgement
  back to the server.
  When set to `client` or `client-individual`, you MUST send an acknowledgement back.
  Stompex however will handle this for you.

  ## Examples

      Stompex.subscribe("/topics/main", conn, %{ "id" => "123" })
      Stompex.subscribe("/topics/main", conn, %{ "ack" => "client" })

  """
  def subscribe(conn, destination, headers) do
    GenServer.call(conn, { :subscribe, destination, headers }, 10_000)
  end

  def unsubscribe(conn, destination) do
    GenServer.call(conn, { :unsubscribe, destination })
  end




  @doc """

  """
  def register_callback(conn, destination, callback) do
    GenServer.call(conn, { :register_callback, destination, callback })
  end

  def remove_callback(conn, destination, callback) do
    GenServer.call(conn, { :remove_callback, destination, callback })
  end

  def send_to_caller(conn, send) do
    GenServer.cast(conn, { :send_to_caller, send })
  end


  def ack(conn, frame) do
    GenServer.cast(conn, { :acknowledge, frame })
  end




  @doc """
  """
  def connect(info, %{ sock: nil, host: host, port: port, headers: headers, timeout: timeout } = state) do
    case :gen_tcp.connect(to_char_list(host), port, [:binary, active: false], timeout) do
      { :ok, sock } ->
        case info do
          { :reconnect, from } ->
            Connection.reply(from, :ok)
            perform_stomp_connect(sock, state)
          _ ->
            perform_stomp_connect(sock, state)
        end
      { :error, _ } ->
        { :backoff, 1000, state }
    end
  end

  @doc """
  """
  def disconnect(info, %{ sock: sock } = state) do
    case FH.send_frame(sock, FB.build_frame("DISCONNECT", %{})) do
      :ok ->
        # We won't wait for a receipt. We'll do this some other time
        :ok = :gen_tcp.close(sock)
        { :close, from } = info
        Connection.reply(from, :ok)
        { :reply, :ok, %{ state | sock: nil } }
      { :error, _ } = error ->
        { :stop, error, error }
    end

    { :noconnect, %{ state | sock: nil } }
  end

  defp perform_stomp_connect(sock, state) do
    case FH.send_frame(sock, FB.connect_frame(state[:host], state[:headers])) do
      :ok ->
        frame = FH.receive_frame(sock)
        case frame.cmd do
          "CONNECTED" ->
            :inet.setopts(sock, active: :once)
            { :ok, %{ state | sock: sock } }
          "ERROR" ->
            { :stop, frame.headers["message"] || "Server rejected connection", frame.headers["message"] || "Server rejected connection" }
          _ ->
            { :stop, "Server rejected connection", "Server rejected connection" }
        end
      { :error, _ } = error ->
        { :stop, error, error }
    end
  end


  @doc """
  """
  def handle_call({ :send, data }, _, %{ sock: sock } = state) do
    case :gen_tcp.send(sock, data) do
      :ok ->
        { :reply, :ok, state }
      { :error, _ } = error ->
        { :disconnect, error, error, state }
    end
  end


  def handle_call(:close, from, state) do
    { :disconnect, { :close, from }, state }
  end

  def handle_call(:reconnect, from, state) do
    { :connect, { :reconnect, from }, state}
  end

  @doc """
  Registers a function to be called whenever a
  STOMP frame is received from the server.

  This function should not be called directly.
  Instead, please use the `register_callback/3`
  function.
  """
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

  @doc """
  Subscribes to the specified topic or queue.

  This function should not be called directly.
  Instead, please use the `subscribe/2` or `subscribe/3`
  functions instead.
  """
  def handle_call({ :subscribe, destination, headers }, _, %{ subscriptions: subscriptions } = state) do
    case Dict.has_key?(subscriptions, destination) do
      true ->
        { :noreply, "You have already subscribed to this destination" }
      false ->
        subscribe_to_destination(destination, headers, state)
    end
  end

  defp subscribe_to_destination(destination, headers, %{ sock: sock, subscription_id: id, subscriptions: subs } = state) do
    frame = FB.build_frame("SUBSCRIBE", %{
      id: headers["id"] || id,
      ack: headers["ack"] || "auto",
      destination: destination
    })

    state = %{ state | subscription_id: (id + 1) }

    case FH.send_frame(sock, frame) do
      :ok ->
        # Great we've subscribed. Now keep track of it
        subscription = %{
          id: frame.headers[:id],
          ack: frame.headers[:ack]
        }
        { :reply, :ok, %{ state | subscriptions: Map.merge(subs, %{ destination => subscription })} }
      { :error, _ } = error ->
        { :noreply, error, error }
    end
  end

  def handle_call({ :unsubscribe, destination }, _, %{ sock: sock, subscriptions: subscriptions } = state) do
    case Dict.has_key?(subscriptions, destination) do
      true ->
        unsubscribe_from_destination(destination, state)
      false ->
        { :noreply, "You are not subscribed to this destination" }
    end
  end

  defp unsubscribe_from_destination(destination, %{ sock: sock, subscriptions: subscriptions } = state) do
    subscription = subscriptions[destination]
    frame = FB.build_frame("UNSUBSCRIBE", %{
      id: subscription[:id]
    })

    case FH.send_frame(sock, frame) do
      :ok ->
        { :noreply, %{ state | subscriptions: Map.delete(subscriptions, destination)}}
      { :error, _ } = error ->
        { :noreply, error }
    end
  end



  def handle_cast({ :acknowledge, frame }, %{ sock: sock } = state) do
    ack_frame = FB.build_frame("ACK", %{
      "message-id" => frame.headers["message-id"],
      "subscription" => frame.headers["subscription"]
    })

    FH.send_frame(sock, ack_frame)
    { :noreply, state }
  end

  def handle_cast({ :send_to_caller, send }, state) do
    { :noreply, %{ state | send_to_caller: send } }
  end



  @doc """
  Handles messages from the underlying TCP connection. These
  will be frames from the STOMP server.

  This function should not be invoked directly, as it will
  automatically be called by the TCP connection.
  """
  def handle_info({ :tcp, _, data}, %{ sock: sock, callbacks: callbacks, pending_frame: pending_frame, calling_process: process } = state) do
    frames = FH.parse_frames(data, pending_frame)

    :inet.setopts(sock, active: :once)
    { :noreply, process_parsed_frames(frames, state) }
  end


  defp process_parsed_frames([frame | frames], %{ send_to_caller: stc, calling_process: process, callbacks: callbacks,  } = state) do
    case frame do
      %{ cmd: "HEARTBEAT"} ->
        process_parsed_frames(frames, state)
      %{ cmd: "ERROR" } ->
        state
      %{ complete: false } ->
        process_parsed_frames(frames, %{ state | pending_frame: frame })
      %{ complete: true } ->
        dest = frame.headers["destination"]
        frame = %{ frame | body: String.replace(frame.body, <<0>>, "") }
        case stc do
          true ->
            send(process, { :stompex, dest, frame })
          _ ->
            callbacks
            |> Dict.get(dest, [])
            |> Enum.map(fn(func) -> func.(frame) end)
        end

        process_parsed_frames(frames, %{ state | pending_frame: nil })
    end
  end
  defp process_parsed_frames(frames = [], state), do: state

end
