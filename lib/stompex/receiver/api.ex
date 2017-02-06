defmodule Stompex.Receiver.Api do

  defmacro __using__(_opts) do
    quote do

      alias Stompex.Receiver.State

      def start_link(conn) do
        GenServer.start_link(__MODULE__, [conn, self()])
      end

      def init([conn, caller]) do
        { :ok, %State{ caller: caller, conn: conn } }
      end

      def next_frame(receiver) do
        GenServer.cast(receiver, :next_frame)
      end

      def stop_listening(receiver) do
        GenServer.cast(receiver, :stop_listening)
      end

      def receive_frame(receiver) do
        GenServer.call(receiver, :receive_frame)
      end

      @doc """
      Specifies what version of the protocol the receiver
      process should use.
      """
      @spec set_version(pid, float) :: :ok
      def set_version(receiver, version) do
        GenServer.cast(receiver, { :set_version, version })
      end

    end
  end

end
