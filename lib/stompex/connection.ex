defmodule Stompex.Connection do
  @moduledoc """
  This module provides a number of helpful functions
  for retrieving data from a TCP socket. Primarily
  these are meant for use by the frame receiver but
  can be used elsewhere if needed.
  """

  @doc """
  Reads a line from the TCP connection, where a
  line is defined by the specified delimeter. If
  this is not specified, it will default to
  "\n".
  """
  @spec read_line(:gen_tcp.socket, String.t) :: { :ok, String.t } | { :error, :gen_tcp.reason }
  def read_line(conn, delim \\ "\n") do
    conn
    |> set_delimeter(delim)
    |> set_packet_type(:line)
    |> :gen_tcp.recv(0)
  end

  @doc """
  Keeps reading lines from the TCP connection until
  a non-blank line is found. Similar to `read_line/2`
  the delimeter can be specified.
  """
  @spec fast_forward(:gen_tcp.socket, String.t) :: { :ok, String.t } | { :error, :gen_tcp.reason }
  def fast_forward(conn, delim \\ "\n") do
    fast_forward(conn, delim, read_line(conn, delim))
  end

  defp fast_forward(_conn, _delim, { :error, _reason } = last_line), do: last_line
  defp fast_forward(conn, delim, { :ok, line }) when line == delim do
    fast_forward(conn, delim, read_line(conn, delim))
  end
  defp fast_forward(_conn, _delim, line), do: line




  @doc """
  Reads the specified number of bytes from the
  TCP connection. This can be used to retrieve
  the entire body of a stomp frame when the
  headers specify the content size. In this
  scenario, it is not possible to simply read
  until a null character, as the contents may
  contain a null character.
  """
  @spec read_bytes(:gen_tcp.socket, String.t) :: { :ok, String.t } | { :error, :gen_tcp.reason }
  def read_bytes(conn, length) when is_binary(length) do
    read_bytes(conn, String.to_integer(length))
  end
  @spec read_bytes(:gen_tcp.socket, integer) :: { :ok, String.t } | { :error, :gen_tcp.reason }
  def read_bytes(conn, length) do
    conn
    |> set_packet_type(:raw)
    |> :gen_tcp.recv(length)
  end


  # Sets the line delimeter of the specified
  # connection.
  defp set_delimeter(conn, delim) do
    :inet.setopts(conn, line_delimeter: delim)
    conn
  end

  # Sets the packet type. Used for switching
  # between reading lines at a time, to reading
  # a specific number of bytes
  defp set_packet_type(conn, type) do
    :inet.setopts(conn, packet: type)
    conn
  end

end
