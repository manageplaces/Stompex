defmodule Stompex.Validator do
  @moduledoc """
  The Validator module can be used for ensuring that
  frames being sent to the STOMP server are valid.
  Primarily, the reason for a frame being invalid is
  due to the version of the protocol being used, as
  you should not really be building frames up directly
  yourself.
  """
  use Stompex.Constants

  @valid_commands_10 ~W(CONNECTED MESSAGE RECEIPT ERROR CONNECT SEND SUBSCRIBE UNSUBSCRIBE BEGIN COMMIT ABORT ACK DISCONNECT)
  @valid_commands_11 ~W(STOMP NACK)

  @doc """
  Check to see whether ot not the supplied command is
  a valid STOMP command.
  """
  @spec valid_command?(String.t, float) :: boolean
  def valid_command?(cmd, version \\ 1.2)
  def valid_command?(cmd, 1.0) do
    cmd in @valid_commands_10
  end
  def valid_command?(cmd, _version) do
    valid_command?(cmd, 1.0) || cmd in @valid_commands_11
  end

  @doc """
  Given a header key and value, this function will
  return a map containing the same key value pair,
  but with the value converted to a different format
  if needed based on the key.

  This applies to all known special headers, such as
  `content-length` which is actually an integer.
  """
  @spec format_header(String.t, String.t) :: map
  def format_header("content-length", value) do
    %{ "content-length" => String.to_integer(value) }
  end
  def format_header("version", value) do
    %{ "value" => String.to_float(value) }
  end
  def format_header(key, value) do
    %{ key => value }
  end


  def normalise_version([]), do: @default_version
  def normalise_version(versions) when is_nil(versions) or versions == "", do: @default_version
  def normalise_version(versions) when is_binary(versions), do: String.to_float(versions)
  def normalise_version(versions) when is_list(versions) do
    versions
    |> Enum.map(fn(v) -> String.to_float(v) end)
    |> Enum.max
  end

end
