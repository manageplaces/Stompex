defmodule StompexTest.Messages do

  def full_valid_message() do
    """
    MESSAGE
    message-id:123
    header-2:header-val
    header-3:header-val

    body text
    """ <> <<0>>
  end

  def full_valid_frame() do
    %Stompex.Frame{
      cmd: "MESSAGE",
      headers: %{
        "message-id" => "123",
        "header-2" => "header-val",
        "header-3" => "header-val"
      },
      content_type: nil,
      body: "body text\n",
      complete: true,
      headers_complete: true,
      last_header: "header-3"
    }
  end



  def full_valid_content_length_message() do
    """
    MESSAGE
    message-id:123
    header-2:header-val
    header-3:header-val
    content-length:24

    body text
    #{<<0>>}
    body text
    """ <> <<0>>
  end

  def full_valid_content_length_frame() do
    %Stompex.Frame{
      cmd: "MESSAGE",
      headers: %{
        "message-id" => "123",
        "header-2" => "header-val",
        "header-3" => "header-val",
        "content-length" => "24"
      },
      content_type: nil,
      body: """
      body text
      #{<<0>>}
      body text
      """,
      complete: true,
      headers_complete: true,
      last_header: "content-length"
    }
  end





  def partial_message do
    """
    MESSAGE
    message-id:123
    header-2:header-val
    header-3:header-val

    body text
    """
  end


  def partial_frame do
    %Stompex.Frame{
      cmd: "MESSAGE",
      headers: %{
        "message-id" => "123",
        "header-2" => "header-val",
        "header-3" => "header-val"
      },
      content_type: nil,
      body: """
      body text
      """,
      complete: false,
      headers_complete: true,
      last_header: "header-3"
    }
  end







  def multi_full_message do
    """
    MESSAGE
    message-id:123
    header-2:header-val
    header-3:header-val

    body text
    #{<<0>>}
    MESSAGE
    message-id:123
    header-2:header-val
    header-3:header-val

    body text
    #{<<0>>}
    """
  end

  def multi_full_frames do
    [
      %Stompex.Frame{
        cmd: "MESSAGE",
        headers: %{
          "message-id" => "123",
          "header-2" => "header-val",
          "header-3" => "header-val"
        },
        content_type: nil,
        body: """
        body text
        """,
        complete: true,
        headers_complete: true,
        last_header: "header-3"
      },
      %Stompex.Frame{
        cmd: "MESSAGE",
        headers: %{
          "message-id" => "123",
          "header-2" => "header-val",
          "header-3" => "header-val"
        },
        content_type: nil,
        body: """
        body text
        """,
        complete: true,
        headers_complete: true,
        last_header: "header-3"
      }
    ]
  end






  def multi_mixed_message() do
    """
    MESSAGE
    message-id:123
    header-2:header-val
    header-3:header-val

    body text
    #{<<0>>}
    MESSAGE
    """
  end

  def multi_mixed_frames() do
    [
      %Stompex.Frame{
        cmd: "MESSAGE",
        headers: %{
          "message-id" => "123",
          "header-2" => "header-val",
          "header-3" => "header-val"
        },
        content_type: nil,
        body: """
        body text
        """,
        complete: true,
        headers_complete: true,
        last_header: "header-3"
      },
      %Stompex.Frame{
        cmd: "MESSAGE",
        headers: nil,
        content_type: nil,
        body: nil,
        complete: false,
        headers_complete: false,
        last_header: nil
      }
    ]
  end




  def incomplete_message_1() do
    """
    MESSAGE
    message-id:123
    header-2:header-val
    """
  end

  def incomplete_message_2() do
    """
    header-3:header-val

    body text
    #{<<0>>}
    """
  end

  def incomplete_frame_1() do
    %Stompex.Frame{
      cmd: "MESSAGE",
      headers: %{
        "message-id" => "123",
        "header-2" => "header-val"
      },
      content_type: nil,
      body: nil,
      complete: false,
      headers_complete: false,
      last_header: "header-2"
    }
  end

  def incomplete_final_frame() do
    %Stompex.Frame{
      cmd: "MESSAGE",
      headers: %{
        "message-id" => "123",
        "header-2" => "header-val",
        "header-3" => "header-val"
      },
      content_type: nil,
      body: """
      body text
      """,
      complete: true,
      headers_complete: true,
      last_header: "header-3"
    }
  end



  def heartbeat_frame() do
    %Stompex.Frame{
      cmd: "HEARTBEAT",
      headers: %{},
      content_type: nil,
      body: nil,
      complete: true,
      headers_complete: true,
      last_header: nil
    }
  end
end
