defmodule Stompex.Frame do
  defstruct cmd: nil, headers: %{}, content_type: nil, body: nil, complete: false
end
