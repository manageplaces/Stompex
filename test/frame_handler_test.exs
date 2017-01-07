defmodule FrameHandlerTest do
  use ExUnit.Case
  doctest Stompex.FrameHandler

  import StompexTest.Messages
  alias Stompex.FrameHandler, as: FH

  test "parses a valid full frame" do
    frames = FH.parse_frames(full_valid_message(), nil)

    assert Enum.count(frames) == 1
    assert Enum.at(frames, 0) == full_valid_frame()
    assert Enum.at(frames, 0).complete == true
  end

  test "parses frame with null char if content length specified" do
    frames = FH.parse_frames(full_valid_content_length_message(), nil)

    assert Enum.count(frames) == 1
    assert Enum.at(frames, 0) == full_valid_content_length_frame()
    assert Enum.at(frames, 0).complete == true
  end

  test "parses partial frame" do
    frames = FH.parse_frames(partial_message(), nil)

    assert Enum.count(frames) == 1
    assert Enum.at(frames, 0) == partial_frame()
  end

  test "parses multiple complete frames" do
    frames = FH.parse_frames(multi_full_message(), nil)

    assert Enum.count(frames) == 2
    assert frames == multi_full_frames()
  end

  test "parses multiple mixed completion frames" do
    frames = FH.parse_frames(multi_mixed_message(), nil)

    assert Enum.count(frames) == 2
    assert frames = multi_mixed_frames()
  end

  test "completes a previously incomplete frame" do
    frames = FH.parse_frames(incomplete_message_1(), nil)

    assert Enum.count(frames) == 1
    assert Enum.at(frames, 0) == incomplete_frame_1()

    frames = FH.parse_frames(incomplete_message_2(), Enum.at(frames, 0))

    assert Enum.count(frames) == 1
    assert Enum.at(frames, 0) == incomplete_final_frame()
  end

  test "parses a basic heartbeat frame" do
    frames = FH.parse_frames("\n", nil)

    assert Enum.count(frames) == 1
    assert Enum.at(frames, 0) == heartbeat_frame()
  end

end
