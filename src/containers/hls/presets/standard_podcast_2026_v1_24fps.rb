# frozen_string_literal: true

module Presets
  module StandardPodcast2026
    # V1 with every rung normalized to 24fps instead of 30; everything else inherits.
    class V1At24fps < V1
      NAME = "Standard Podcast 2026 v1 24fps"

      FPS = "24"
    end
  end
end
