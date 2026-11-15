# frozen_string_literal: true

require "json"
require "open3"

module Hls
  # ffprobe -show_entries queries. Array form, so no shell is involved.
  module Probe
    # A missing stream is exit 0 with empty output, left for the caller to judge. A
    # failure is logged here, since the task's rescue can't see these locals.
    def self.run(file, entries, stream: nil, format: "csv=p=0")
      args = ["ffprobe", "-v", "error"]
      args += ["-select_streams", stream] if stream
      args += ["-show_entries", entries, "-of", format, file]
      stdout, stderr, status = Open3.capture3(*args)
      unless status.success?
        puts JSON.dump({msg: "FFprobe output", exit_status: status.exitstatus, stdout: stdout, stderr: stderr})
        raise StandardError, "FFprobe failed (exit #{status.exitstatus}): #{stderr.strip}"
      end
      stdout
    end

    # A single value.
    def self.value(file, entries, stream: nil)
      run(file, entries, stream: stream).lines.first.to_s.strip
    end
  end
end
