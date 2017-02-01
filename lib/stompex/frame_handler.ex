defmodule Stompex.FrameHandler do

  @client_command_regex ~r/^(SEND|SUBSCRIBE|UNSUBSCRIBE|BEGIN|COMMIT|ABORT|ACK|NACK|DISCONNECT|CONNECT|STOMP)$/
  @server_command_regex ~r/^(CONNECTED|MESSAGE|RECEIPT|ERROR)$/

  alias Stompex.Frame

  def receive_frame(sock) do
    case :gen_tcp.recv(sock, 0) do
      { :ok, response } ->
        parse_frames(response, nil) |> List.first
      { :error, _ } = error ->
        { :error, error }
    end
  end

  def send_frame(sock, frame = %Frame{}) do
    :gen_tcp.send(sock, to_char_list(to_string(frame)))
  end


  @doc """
  Parses a frame whose content is simply a new line
  character. This occurrs in the event of a heartbeat
  being sent by the server.
  """
  def parse_frames(frame = "\n", existing_frame) do
    [%Frame{
      complete: true,
      headers_complete: true,
      cmd: "HEARTBEAT"
    }]
  end

  @doc """
  Parses an incoming STOMP frame from the server.
  An existing frame may be provided in the event
  that it was not complete. If provided, this
  function will continue parsing where the previous
  frame left off. This can be repeated until a full
  frame is received.
  """
  def parse_frames(frame, existing_frame) do
    parser_state = nil

    IO.inspect frame, limit: :infinity

    # If the existing frame already has a body,
    # then we'll continue parsing form the body
    parser_state =
      cond do
        existing_frame && ((existing_frame.body || "") != "" || (Enum.count(existing_frame.headers) > 0 && existing_frame.headers_complete)) ->
          :body
        existing_frame && (Enum.count(existing_frame.headers) != 0) ->
          :header
        true ->
          :command
      end

    frame
    |> to_string
    |> String.split("\n")
    |> gather_line_types(parser_state, [])
    |> build_frames(existing_frame, [])
    |> mark_completion()
    |> remove_trailing_chars()
  end

  defp mark_completion(frames) do
    completion_frames = Enum.map(frames, fn(frame) ->
      expected_length = frame.headers["content-length"]
      cond do
        is_nil(frame.body) -> frame
        is_nil(expected_length) || expected_length == "" -> %{ frame | complete: String.trim_trailing(frame.body) |> String.ends_with?(<<0>>) }
        true -> %{ frame | complete: byte_size(frame.body) >= String.to_integer(expected_length) }
      end
    end)

    completion_frames
  end

  defp remove_trailing_chars(frames) do
    cleaned_frames = Enum.map(frames, fn(frame) ->
      cond do
        is_nil(frame.body) -> frame
        frame.complete -> %{ frame | body: (String.replace_trailing(frame.body, "\n", "") |> String.replace_suffix(<<0>>, "")) }
        true -> %{ frame | body: String.replace_suffix(frame.body, "\n", "") }
      end
    end)

    cleaned_frames
  end


  defp build_frames([[type: :body, value: value] | lines], frame, frames) when is_nil(frame) do
    build_frames(lines, frame, frames)
  end

  defp build_frames([[type: :command, cmd: cmd] = command | lines ], frame, frames) when is_nil(frame) do
    build_frames([ command | lines ], %Frame{}, frames)
  end

  defp build_frames(lines, frame, frames) when is_nil(frame) and lines != [] do
    build_frames(lines, %Frame{}, [])
  end

  defp build_frames([[type: :command, cmd: cmd] = command | lines ], frame, frames) do
    case frame.cmd do
      nil ->
        build_frames(lines, %{ frame | cmd: cmd }, frames)
      _ ->
        build_frames(lines, %{ frame | body: (frame.body || "") <> cmd }, frames)
    end
  end

  defp build_frames([[type: :header, key: key, value: value] | lines], frame, frames) do
    build_frames(lines, %{ frame | headers: Map.merge(frame.headers, %{ key => value }) }, frames)
  end

  # We've got a body line, but the headers are not yet complete, so
  # we mark the headers as complete, and continue.
  defp build_frames([[type: :body, value: value] = line | lines], %Frame{ headers: headers, headers_complete: headers_complete } = frame, frames) when headers_complete == false do
    build_frames([ line | lines ], %{ frame | headers_complete: true }, frames)
  end

  defp build_frames([[type: :body, value: value] | lines], %Frame{ headers: headers } = frame, frames) do
    case should_end_frame?(frame.body, headers["content-length"], value) do
      true ->
        build_frames(lines, nil, (frames ++ [%{ frame | body: (frame.body || "") <> value }]))

      false ->
        build_frames(lines, %{ frame | body: (frame.body || "") <> value <> "\n" }, frames)
    end
  end

  defp build_frames([[type: :blankline] | lines], frame = %Frame{ headers: headers, cmd: cmd, body: body }, frames) when headers != nil and cmd != nil and body != nil do
    build_frames(lines, %{ frame | body: body <> "\n" }, frames)
  end

  defp build_frames([[type: :blankline] | lines], frame, frames), do: build_frames(lines, frame, frames)

  defp build_frames(lines = [], frame, frames) when is_nil(frame), do: frames
  defp build_frames(lines = [], frame, frames), do: frames ++ [frame]

  # Determine whether or not the next line to
  # be appended to the frame should be the final
  # line or not.
  defp should_end_frame?(body, "", next_line), do: should_end_frame?(body, nil, next_line)

  defp should_end_frame?(_body, nil, next_line) do
    next_line
    |> String.trim_trailing
    |> String.ends_with?(<<0>>)
  end

  defp should_end_frame?(body, length, next_line) when is_binary(length) do
    should_end_frame?(body, String.to_integer(length), next_line)
  end

  defp should_end_frame?(body, length, next_line) do
    byte_size((body || "") <> next_line) >= length
  end


  def gather_line_types([line | lines], state, types) do
    line_type =
      case state do
        :command ->
          [ type: :command, cmd: line ]
        :header ->
          match = Regex.run(~r/^([a-zA-Z0-9\-]*):(.*)$/, line)
          case match do
            [_, key, value] ->
              [ type: :header, key: key, value: value ]
            _ ->
              [ type: :blankline ]
          end
        :body ->
          case String.match?(line, @server_command_regex) do
            true -> [ type: :command, cmd: line ]
            false -> [ type: :body, value: line ]
          end
      end

    gather_line_types(lines, next_parser_state(state, line_type), types ++ [line_type])
  end
  def gather_line_types(lines = [], state, types), do: types

  def next_parser_state(state, line_type) do
    case line_type do
      [ type: :command, cmd: cmd ] ->
        :header
      [ type: :header, key: key, value: value ] ->
        :header
      [ type: :blankline ] ->
        :body
      [ type: :body, value: value ] = line_type ->
        :body
    end
  end

end
