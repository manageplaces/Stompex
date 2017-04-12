defmodule Stompex.State do
  @moduledoc """
  A simple struct representing the state used by the
  main Stompex module.
  """

  defstruct conn: nil,
            host: nil,
            port: nil,
            headers: %{},
            timeout: nil,
            callbacks: %{},
            subscriptions: %{},
            subscription_id: 0,
            calling_process: nil,
            send_to_caller: false,
            receiver: nil,
            version: "1.2",
            secure: false,
            ssl_opts: []
end