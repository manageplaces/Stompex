defmodule Stompex.Api do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do

      @connection_timeout 10_000
      @default_stomp_port 61618

      @doc false
      def start_link(host, port, login, passcode, headers, timeout \\ @connection_timeout) do
        Connection.start_link(__MODULE__, { host, port, login, passcode, headers, timeout, self() })
      end

      @doc false
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
          calling_process: calling_process,
          send_to_caller: false,
          receiver: nil,
          version: Stompex.Validator.normalise_version(headers["accept-version"])
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
      @spec connect() :: GenServer.on_start
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
      @spec connect(String.t, integer, String.t, String.t) :: GenServer.on_start
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
      @spec connect(String.t, integer, String.t, String.t, map) :: GenServer.on_start
      def connect(host, port, login, passcode, headers) do
        Stompex.start_link(host, port, login, passcode, headers)
      end


      @doc """
      Disconnect from the remote stomp server. This will
      close the underlying TCP connection, remove all
      registered listeners, and reset Stompex back to its
      original state.
      """
      @spec disconnect(pid) :: term
      def disconnect(conn) do
        Connection.call(conn, :close)
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

      ## Examples

          Stompex.subscribe("/topics/main", conn, %{ "id" => "123" })
          Stompex.subscribe("/topics/main", conn, %{ "ack" => "client" })

      When subscribing, it is also possible to supply options. These
      alter the way in which Stompex will handle incoming frames for
      this subscription.

      - :compressed - Whether or not the incoming frame contains a body
      that is gzip compressed. If set to `true` Stompex will decompress
      the body before passing on the frame. If `false` (default), no
      decompression will be attempted.

      """
      def subscribe(conn, destination) do
        subscribe(conn, destination, [])
      end
      def subscribe(conn, destination, headers_or_opts) when is_list(headers_or_opts) do
        subscribe(conn, destination, %{ "ack" => "auto" }, headers_or_opts)
      end
      def subscribe(conn, destination, headers_or_opts) when is_map(headers_or_opts) do
        subscribe(conn, destination, headers_or_opts, [])
      end
      @spec subscribe(pid, String.t, map, keyword) :: term
      def subscribe(conn, destination, headers, opts) do
        GenServer.call(conn, { :subscribe, destination, headers, opts }, 10_000)
      end

      @doc """
      Unsubscribes from a specific queue or topic. An error will be
      returned if an attempt is made to unsubscribe from a destination
      that was not subscribed in the first place.
      """
      @spec unsubscribe(pid, String.t) :: term
      def unsubscribe(conn, destination) do
        GenServer.call(conn, { :unsubscribe, destination })
      end

      @doc """
      Registers a function to be called whenever a STOMP
      frame is received from the server. This function
      will only be invoked when a message is received from
      the destination specified at the point of registration.

      For example, registering a callback for '/queues/my-queue'
      will not be called when a message is received from
      '/queues/different-queue'.

      The function being registered will be supplied with
      the parsed frame, and needs not return an specific
      value, as it will not be used.

      ## Examples

      **Defining a function explicitly**

          { :ok, conn } = Stompex.connect("host", port, "", "")
          callback = fn (frame) ->
            IO.inspect(frame)
          end

          Stompex.register_callback(conn, "/queue/my-queue", callback)

      **Using a function defined elsewhere**

          { :ok, conn } = Stompex.connect("host", port, "", "")
          Stompex.register_callback(conn, "/queue/my-queue", &IO.inspect/1)

      """
      @spec register_callback(pid, String.t, ((Stompex.Frame.t) -> any)) :: term
      def register_callback(conn, destination, callback) do
        GenServer.call(conn, { :register_callback, destination, callback })
      end

      @doc """
      Removes a callback registered via `register_callback/3`. The
      function supplied must be the same function supplied when it
      was registered, otherwise it will not be removed.
      """
      @spec register_callback(pid, String.t, ((Stompex.Frame.t) -> any)) :: term
      def remove_callback(conn, destination, callback) do
        GenServer.call(conn, { :remove_callback, destination, callback })
      end

      @doc """
      As an alternative to registering a callback function per
      destination, it is possible to have Stompex send frames
      to the calling process instead. This function allows you
      to enable or disable this functionality.

      This is particularly useful if you're using Stompex within
      another process such as a GenServer. When used, your process
      will receive a message containing a tuple with the received
      frame, and the destination that it originated from. It is
      then up to you to manage your processing accordingly.

      ## Example

      Below is a simple example of how this may be used within a
      GenServer. The connection is setup on the initialisation of
      the server, and subscriptions are setup. One initialised,
      the `handle_info/2` function will be called with the frames.

      Here you can pattern match on the destination the frame
      originated from, or simply have a single `handle_info/2`
      function and manage it yourself.

          defmodule MyApp do
            use GenServer

            def init(state) do
              { :ok, conn } = Stompex.connect("host", port, "", "")
              Stompex.send_to_caller(conn, true)
              Stompex.subscribe(conn, "/queue/my-queue")
              Stompex.subscribe(conn, "/queue/my-queue-2")

              { :ok, %{ state | conn: conn } }
            end
            ...

            def handle_info({ :stompex, "/queue/my-queue", frame }, state) do
              IO.inspect(frame)
              { :noreply, state }
            end

            def handle_info({ :stompex, "/queue/my-queue-2", frame }, state) do
              IO.inspect(frame)
              { :noreply, state }
            end

          end
      """
      @spec send_to_caller(pid, boolean) :: :ok
      def send_to_caller(conn, send) do
        GenServer.cast(conn, { :send_to_caller, send })
      end


      @doc """
      Send an acknowledgement of a message back to the server.
      This is not required unless your STOMP server explicitly
      demands it, or you specified when you subscribed that you
      would be acknowledging frames.

      This should be used in your callback function, or `handle_info/2`
      implementation once the frame has been received.

      ## Example

      Below is a simple example of how you can acknowledge a
      frame

        { :ok, conn } = Stompex.connect("host", port, "", "")
        callback = fn (frame) ->
          Stompex.ack(conn, frame)
          IO.inspect(frame)
        end
        Stompex.subscribe(conn, "/queue/my-queue")

      The acknowledgement is performed asynchronously. As such,
      this function will return immediately with `:ok`.

      """
      @spec ack(pid, Stompex.Frame.t) :: :ok
      def ack(conn, frame) do
        GenServer.cast(conn, { :acknowledge, frame })
      end

      @doc """
      NACK messages are the opposite of ACK messages, and inform
      that server that a frame has not been correctly processed.
      What the server does with this information is specific to
      that server, but this function will allow you to send this
      message.
      """
      @spec nack(pid, Stompex.Frame.t) :: :ok
      def nack(conn, frame) do
        GenServer.cast(conn, { :nack, frame })
      end


      @doc """
      Send a message to the specified destination. This function
      will return the raw response of the underlying TCP connection
      write attempt. If this succeeds, it will simply return `:ok`.
      Note that even if this function returns `:ok`, the server
      may still return an error. This will be returned to the
      registered callback for the given destination, or the calling
      process depending on configuration
      """
      @spec send(pid, String.t, String.t) :: :ok | { :error, :gen_tcp.reason }
      def send(conn, destination, message) do
        GenServer.call(conn, { :send, destination, message })
      end

    end
  end

end
