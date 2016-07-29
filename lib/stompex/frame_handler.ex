defmodule Stompex.FrameHandler do

  @client_command_regex ~r/^(SEND|SUBSCRIBE|UNSUBSCRIBE|BEGIN|COMMIT|ABORT|ACK|NACK|DISCONNECT|CONNECT|STOMP)$/
  @server_command_regex ~r/^(CONNECTED|MESSAGE|RECEIPT|ERROR)$/

  alias Stompex.Frame

  def receive_frame(sock) do
    case :gen_tcp.recv(sock, 0) do
      { :ok, response } ->
        parse_frame(response, nil)
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
  def parse_frame(frame = '\n', existing_frame) do
    %Frame{
      complete: true,
      cmd: "HEARTBEAT"
    }
  end

  @doc """
  Parses an incoming STOMP frame from the server.
  An existing frame may be provided in the event
  that it was not complete. If provided, this
  function will continue parsing where the previous
  frame left off. This can be repeated until a full
  frame is received.
  """
  def parse_frame(frame, existing_frame) do
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
    |> build_frame(existing_frame)
    |> mark_completion()
  end

  defp mark_completion(frame) do
    expected_length = frame.headers["content-length"]
    case expected_length do
      nil ->
        %{ frame | complete: String.contains?((frame.body || ""), <<0>>) }
      _ ->
        %{ frame | complete: String.length(frame.body) == expected_length }
    end
  end


  defp build_frame(lines, frame) when is_nil(frame), do: build_frame(lines, %Frame{})

  defp build_frame([[type: :command, cmd: cmd] = command | lines ], frame) do
    build_frame(lines, %{ frame | cmd: cmd })
  end

  defp build_frame([[type: :header, key: key, value: value] | lines], frame) do
    build_frame(lines, %{ frame | headers: Map.merge(frame.headers, %{ key => value }) })
  end

  defp build_frame([[type: :body, value: value] | lines], frame) do
    build_frame(lines, %{ frame | body: (frame.body || "") <> value })
  end

  defp build_frame([[type: :blankline] | lines], frame = %Frame{ headers: headers, cmd: cmd, body: body }) when headers != nil and cmd != nil and body != nil do
    build_frame(lines, %{ frame | body: body <> "\n" })
  end

  defp build_frame([[type: :blankline] | lines], frame), do: build_frame(lines, frame)

  defp build_frame(lines = [], frame), do: frame

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
          [ type: :body, value: line ]
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
