defmodule Stompex.Parser.Api do

  defmacro __using__(_opts) do
    quote do

      alias Stompex.Parser.State

      def start_link(conn) do
        GenServer.start_link(__MODULE__, [conn, self()])
      end

      def init([conn, caller]) do
        { :ok, %State{ caller: caller, conn: conn } }
      end

      def next_frame(parser) do
        GenServer.cast(parser, :next_frame)
      end

      def stop_listening(parser) do
        GenServer.cast(parser, :stop_listening)
      end

      def receive_frame(parser) do
        GenServer.call(parser, :receive_frame)
      end

      @doc """
      Specifies what version of the protocol the parser
      process should use.
      """
      @spec set_version(pid, float) :: :ok
      def set_version(parser, version) do
        GenServer.cast(parser, { :set_version, version })
      end

    end
  end

end
