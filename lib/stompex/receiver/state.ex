defmodule Stompex.Receiver.State do
  use Stompex.Constants

  defstruct caller: nil,
            conn: nil,
            version: @default_version
end
