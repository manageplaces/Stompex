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
  def parse_frames(frame = '\n', existing_frame) do
    [%Frame{
      complete: true,
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

    # If the existing frame already has a body,
    # then we'll continue parsing form the body
    cond do
      existing_frame && (existing_frame.body || "") != "" ->
        parser_state = :body
      existing_frame && (Enum.count(existing_frame.headers) != 0) ->
        parser_state = :header
      true ->
        parser_state = :command
    end

    frame
    |> to_string
    |> String.split("\n")
    |> gather_line_types(parser_state, [])
    |> build_frames(existing_frame, [])
    |> mark_completion()
  end

  defp mark_completion(frames) do
    completion_frames = Enum.map(frames, fn(frame) ->
      expected_length = frame.headers["content-length"]
      case expected_length do
        nil ->
          %{ frame | complete: String.trim_trailing(frame.body) |> String.ends_with?(<<0>>) }
        _ ->
          %{ frame | complete: byte_size(frame.body) == expected_length }
      end
    end)

    completion_frames
  end


  defp build_frames([[type: :body, value: value] | lines], frame, frames) when is_nil(frame) do
    build_frames(lines, frame, frames)
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

  defp build_frames([[type: :body, value: <<0>>] | lines], %Frame{ headers: %{ "content-length" => content_length }} = frame, frames) do
    # Got a null character, and we have content length set so this may be part of the body.
    # Check the content length compared with the frame, and if we've got it all then move
    # on.
    case byte_size(frame.body) do
      content_length ->
        # This frame is finished, but there may be others so keep going
        build_frames(lines, nil, frames ++ [frame])
      _ ->
        # Not finished, just keep moving, it's just a null character
        build_frames(lines, %{ frame | body: (frame.body || "") <> <<0>> }, frames)
    end
  end

  defp build_frames([[type: :body, value: <<0>>] | lines], frame, frames) do
    # Got a null character, but no content length so this MUST be the end of a message
    build_frames(lines, nil, (frames ++ [%{ frame | body: (frame.body || "") <> <<0>> }]))
  end

  defp build_frames([[type: :body, value: value] | lines], %Frame{ headers: headers } = frame, frames) do
    build_frames(lines, %{ frame | body: (frame.body || "") <> value }, frames)
  end

  defp build_frames([[type: :blankline] | lines], frame = %Frame{ headers: headers, cmd: cmd, body: body }, frames) when headers != nil and cmd != nil and body != nil do
    build_frames(lines, %{ frame | body: body <> "\n" }, frames)
  end

  defp build_frames([[type: :blankline] | lines], frame, frames), do: build_frames(lines, frame, frames)

  defp build_frames(lines = [], frame, frames) when is_nil(frame), do: frames
  defp build_frames(lines = [], frame, frames), do: frames ++ [frame]


  defp gather_line_types([line | lines], state, types) do
    line_type =
      case state do
        :command ->
          [ type: :command, cmd: line ]
        :header ->
          match = Regex.run(~r/^([a-zA-Z0-1\-]*):(.*)$/, line)
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
  defp gather_line_types(lines = [], state, types), do: types

  defp next_parser_state(state, line_type) do
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
