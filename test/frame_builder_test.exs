defmodule FrameBuilderTest do
  use ExUnit.Case
  doctest Stompex.FrameBuilder

  import Stompex.FrameBuilder
  alias Stompex.Frame

  describe "frame creators" do
    test "returns a new blank frame" do
      assert new_frame() == %Frame{}
    end

    test "returns a send frame" do
      assert send_frame() == %Frame{ cmd: "SEND" }
    end

    test "returns a subscribe frame" do
      assert subscribe_frame() == %Frame{ cmd: "SUBSCRIBE" }
    end

    test "returns an unsubscribe frame" do
      assert unsubscribe_frame() == %Frame{ cmd: "UNSUBSCRIBE" }
    end

    test "returns a begin frame" do
      assert begin_frame() == %Frame{ cmd: "BEGIN" }
    end

    test "returns a commit frame" do
      assert commit_frame() == %Frame{ cmd: "COMMIT" }
    end

    test "returns an abort frame" do
      assert abort_frame() == %Frame{ cmd: "ABORT" }
    end

    test "returns an ack frame" do
      assert ack_frame() == %Frame{ cmd: "ACK" }
    end

    test "returns a nack frame" do
      assert nack_frame() == %Frame{ cmd: "NACK" }
    end

    test "returns a disconnect frame" do
      assert disconnect_frame() == %Frame{ cmd: "DISCONNECT" }
    end

    test "returns a connect frame" do
      assert connect_frame() == %Frame{ cmd: "CONNECT" }
    end

    test "returns a stomp frame" do
      assert stomp_frame() == %Frame{ cmd: "STOMP" }
    end
  end


  describe "content functions" do
    test "sets the command" do
      frame =
        new_frame()
        |> set_command("SUBSCRIBE")

      assert frame == %Frame{ cmd: "SUBSCRIBE" }
    end

    test "doesn't set an invalid command" do
      frame =
        new_frame()
        |> set_command("INVALID")

      assert frame == %Frame{ cmd: nil }
      
    end

    test "adds a new header" do
      frame =
        new_frame()
        |> put_header("key", "value")
        |> put_header("key2", "value2")

      assert frame == %Frame{ headers: %{ "key" => "value", "key2" => "value2" }}
    end

    test "sets the headers" do
      frame =
        new_frame()
        |> put_headers(%{ "key" => "value", "key2" => "value2" })

      assert frame == %Frame{ headers: %{ "key" => "value", "key2" => "value2" }}
    end

    test "sets the body" do
      frame =
        new_frame()
        |> set_body("testing")

      assert frame == %Frame{ body: "testing" }
    end

    test "overwrites the body" do
      frame =
        new_frame()
        |> set_body("testing")
        |> set_body("testing2")

      assert frame == %Frame{ body: "testing2" }
    end

    test "appends body with a new line" do
      frame =
        new_frame()
        |> append_body("testing")

      assert frame == %Frame{ body: "testing\n" }
    end

    test "appends body without a new line" do
      frame =
        new_frame()
        |> append_body("testing", new_line: false)

      assert frame == %Frame{ body: "testing" }
    end

    test "adds a null character and new line" do
      frame =
        new_frame()
        |> set_body("testing")
        |> finish_frame

      assert frame == %Frame{ body: "testing" <> <<0>> <> "\n" }
    end
  end

end
