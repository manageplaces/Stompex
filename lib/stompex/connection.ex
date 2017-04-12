defmodule Stompex.Connection do
  @moduledoc """
  This module provides a number of helpful functions
  for retrieving data from a TCP socket, as well as 
  creating the connection. It will automatically handle
  the different connections between an SSL endpoint and
  a non SSL endpoint.
  """

  use GenServer

  @doc false
  def start_link(host, port, secure, opts, timeout) do
    GenServer.start_link(__MODULE__, { host, port, secure, opts, timeout }, name: Stompex.Connection)
  end

  @doc false
  def init({ host, port, secure, opts, timeout }) do
    mod = connection_module(secure: secure)

    if secure do
      mod.start
    end

    case mod.connect(to_char_list(host), port, opts, timeout) do
      { :ok, sock } ->
        { :ok, %{ sock: sock, secure: secure, mod: mod } }

      { :error, reason } ->
        { :stop, "Error connecting to server - #{inspect(reason)}" }
    end
  end

  @typedoc """
  Reference to a gen_tcp or ssl socket connection
  """
  @type sock :: :gen_tcp.socket | :ssl.socket

  @typedoc """
  pid of a Stompex.Connection GenServer
  """
  @type conn :: pid

  @doc """
  Retrieves the appropriate module for handling connections
  based on whether or not the connection is secure.
  """
  @spec connection_module(keyword) :: :ssl | :gen_tcp
  def connection_module(secure: true), do: :ssl
  def connection_module(secure: false), do: :gen_tcp
  
  @doc """
  Retrieves the appropriate module for changing settings
  for the underlying TCP connection, based on whether or
  not the connection is secure.
  """
  @spec settings_module(keyword) :: :ssl | :inet
  def settings_module(:gen_tcp), do: :inet
  def settings_module(:ssl), do: :ssl

  @doc """
  Sends a stompex frame to the underlying TCP connection.
  """
  @spec send_frame(conn, charlist()) :: :ok | { :error, any() }
  def send_frame(conn, frame) do
    GenServer.call(conn, { :send_frame, frame })
  end

  @doc """
  Closes the TCP connection to the remote server. This will
  also shut down the Connection gen server.
  """
  @spec close(conn) :: any()
  def close(conn) do
    GenServer.call(conn, :close)
  end




  @doc """
  Reads a line from the TCP connection, where a
  line is defined by the specified delimeter. If
  this is not specified, it will default to
  "\n".
  """
  @spec read_line(conn, String.t) :: { :ok, String.t } | { :error, any() }
  def read_line(conn, delim \\ "\n") do
    GenServer.call(conn, { :read_line, delim })
  end

  @doc """
  Keeps reading lines from the TCP connection until
  a non-blank line is found. Similar to `read_line/2`
  the delimeter can be specified.
  """
  @spec fast_forward(conn, String.t) :: { :ok, String.t } | { :error, any() }
  def fast_forward(conn, delim \\ "\n") do
    GenServer.call(conn, { :fast_forward, delim })
  end



  @doc """
  Reads the specified number of bytes from the
  TCP connection. This can be used to retrieve
  the entire body of a stomp frame when the
  headers specify the content size. In this
  scenario, it is not possible to simply read
  until a null character, as the contents may
  contain a null character.
  """
  @spec read_bytes(conn, String.t) :: { :ok, String.t } | { :error, :gen_tcp.reason }
  def read_bytes(conn, length) when is_binary(length) do
    read_bytes(conn, String.to_integer(length))
  end
  @spec read_bytes(conn, integer) :: { :ok, String.t } | { :error, :gen_tcp.reason }
  def read_bytes(conn, length) do
    GenServer.call(conn, { :read_bytes, length })
  end


  # Sets the line delimeter of the specified
  # connection.
  defp set_delimeter(sock, mod, delim) do
    settings_module(mod).setopts(sock, line_delimeter: delim)
    sock
  end

  # Sets the packet type. Used for switching
  # between reading lines at a time, to reading
  # a specific number of bytes
  defp set_packet_type(sock, mod, type) do
    settings_module(mod).setopts(sock, packet: type)
    sock
  end




  @doc false
  def handle_call({ :send_frame, frame }, _from, %{ sock: sock, mod: mod } = state) do
    { :reply, mod.send(sock, frame), state }
  end

  @doc false
  def handle_call(:close, _from, %{ sock: sock, mod: mod, secure: secure } = state) do
    if secure do
      mod.stop
    end

    { :stop, "Connection closed", mod.close(sock), %{ state | sock: nil, mod: nil } }
  end

  @doc false
  def handle_call({ :read_line, delim }, _from, %{ sock: sock, mod: mod } = state) do
    { :reply, do_read_line(sock, mod, delim), state }
  end

  @doc false
  def handle_call({ :fast_forward, delim }, _from, %{ sock: sock, mod: mod } = state) do
    { :reply, do_fast_forward(sock, mod, delim), state }
  end

  @doc false
  def handle_call({ :read_bytes, length }, _from, %{ sock: sock, mod: mod } = state) do
    read =
      sock
      |> set_packet_type(mod, :raw)
      |> mod.recv(length)

    { :reply, read, state }
  end



  defp do_read_line(sock, mod, delim) do
    sock
    |> set_delimeter(mod, delim)
    |> set_packet_type(mod, :line)
    |> mod.recv(0)
  end


  defp do_fast_forward(sock, mod, delim \\ "\n") do
    do_fast_forward(sock, mod, delim, do_read_line(sock, mod, delim))
  end

  defp do_fast_forward(_sock, _mod, _delim, { :error, _reason } = last_line), do: last_line
  defp do_fast_forward(sock, mod, delim, { :ok, line }) when line == delim do
    do_fast_forward(sock, mod, delim, do_read_line(sock, mod, delim))
  end
  defp do_fast_forward(_sock, _mod, _delim, line), do: line

end
