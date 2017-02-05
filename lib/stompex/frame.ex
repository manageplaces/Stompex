defmodule Stompex.Frame do

  @type t :: struct

  defstruct cmd: nil,
            headers: %{},
            content_type: nil,
            body: nil
end
