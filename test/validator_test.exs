defmodule ValidatorTest do
  use ExUnit.Case
  doctest Stompex.Validator

  describe "command validation" do

    test "returns true for all valid commands" do
      valid = ~W(CONNECT SEND SUBSCRIBE UNSUBSCRIBE BEGIN COMMIT ABORT ACK DISCONNECT STOMP NACK)
      Enum.each(valid, fn(cmd) ->
        assert Stompex.Validator.valid_command?(cmd) == true
      end)
    end

    test "returns false for invalid commands" do
      assert Stompex.Validator.valid_command?("INVALID") == false
    end

    test "returns false for version specific commands" do
      assert Stompex.Validator.valid_command?("STOMP", 1.0) == false
      assert Stompex.Validator.valid_command?("STOMP", 1.1) == true
      assert Stompex.Validator.valid_command?("STOMP", 1.2) == true
    end

  end
end
