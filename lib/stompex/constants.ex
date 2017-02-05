defmodule Stompex.Constants do

  defmacro __using__(_) do
    quote do

      # By default, we want to be using the
      # latest version of the STOMP protocol.
      @default_version 1.2

    end
  end

end
