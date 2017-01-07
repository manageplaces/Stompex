defmodule Stompex.Frame do
  defstruct cmd: nil,
            headers: %{},
            content_type: nil,
            body: nil,
            complete: false,
            headers_complete: false
end
