defimpl String.Chars, for: Stompex.Frame do

  def to_string(frame) do
    Enum.join([
      frame.cmd,
      "\n",
      Enum.join(Enum.map(frame.headers, fn {k, v} -> "#{k}:#{v}" end), "\n"),
      "\n\n",
      frame.body
    ])

  end

end
