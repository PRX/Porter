# frozen_string_literal: true

module Hls
  # Exact time arithmetic, so times are quantized and formatted by one rule.
  module Timing
    module_function

    # From the decimal as written, so 0.1 is 1/10 rather than a binary approximation.
    def exact(value) = Rational(value.to_s)

    # Nearest whole frame.
    def quantize(time, fps) = Rational((exact(time) * exact(fps)).round) / exact(fps)

    # How times appear in ffmpeg arguments and error messages.
    def fmt(rational) = format("%.6f", rational)

    # How times appear in the task result.
    def round6(value) = value.to_f.round(6)
  end
end
