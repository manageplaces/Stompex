defmodule Stompex.FrameBuilder do
  alias Stompex.Frame

  @eol "\n"
  @eof [0]

  def connect_frame(host, headers = %{ "login" => login, "passcode" => passcode }) do
    headers = Map.merge(%{ "host" => host }, headers)
    build_frame("CONNECT", headers)
  end

  def build_frame(cmd, headers, body \\ "") do
    frame = %Frame{
      cmd: cmd,
      headers: headers,
      body: body
    }
  end

end
