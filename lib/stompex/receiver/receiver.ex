defmodule Stompex.Receiver do
  use GenServer
  use Stompex.Receiver.Api

  import Stompex.FrameBuilder
  alias Stompex.Connection, as: Con

  @header_regex ~r/^([a-zA-Z0-9\-]*):(.*)$/

  @doc false
  def handle_cast(:next_frame, %{ conn: conn } = state) do
    conn
    |> do_receive
    |> return_to_caller(state)

    { :noreply, state }
  end

  @doc false
  def handle_cast({ :set_version, version }, state) do
    { :noreply, %{ state | version: version } }
  end

  @doc false
  def handle_call(:receive_frame, _from, %{ conn: conn } = state) do
    frame = do_receive(conn)
    { :reply, { :ok, frame }, state }
  end


  defp do_receive(conn) do
    new_frame()
    |> read_command(conn)
    |> read_headers(conn)
    |> read_body(conn)
    |> clean_frame
  end

  defp read_command(frame, conn) do
    { :ok, command } =
      conn
      |> Con.fast_forward("\n")

    frame |> set_command(String.trim_trailing(command))
  end

  defp read_headers(frame, conn), do: read_headers(frame, conn, nil)

  defp read_headers(frame, _conn, "\n"), do: frame

  defp read_headers(frame, conn, _last_line) do
    { :ok, line } =
      conn
      |> Con.read_line("\n")

    read_headers(process_header(line, frame), conn, line)
  end

  defp process_header("\n", frame), do: frame
  defp process_header(line, frame) do
    [ _, key, value ] = Regex.run(@header_regex, line)
    frame |> put_header(key, value)
  end


  #
  # Reads the body of the frame based on a pre-determined
  # content length. This will simply read that number of
  # bytes from the TCP connection and append them to the
  # frames body. Note this will read one aditional byte,
  # to cater for the required null character following
  # the body to mark the end of the frame.
  #
  defp read_body(%{ headers: %{ "content-length" => length } } = frame, conn) when not is_nil(length) and length != "" do
    { :ok, body } =
      conn
      |> Con.read_bytes(length + 1)

    frame |> append_body(body)
  end

  #
  # Reads the body of the frame when there is no
  # pre-determined content length.
  #
  defp read_body(frame, conn) do
    { :ok, body } =
      conn
      |> Con.read_line(<<0>>)

    # Check if the body contains the null char. Even though
    # we've set the line delimeter to the null char, if the
    # body is larger than our receiving buffer, it may still
    # not include it so we may have to keep going until we've
    # got it.
    case String.contains?(body, <<0>>) do
      true ->
        frame
        |> append_body(body)

      false ->
        frame |> append_body(body) |> read_body(conn)
    end
  end

  defp return_to_caller(frame, %{ caller: caller }) do
    send(caller, { :receiver, frame })
  end

end
