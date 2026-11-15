# frozen_string_literal: true

# Checks that cutting AdBreaks ranges keeps audio and video in sync.
#   ruby test/scripts/av_sync.rb    (set HLS_VIDEO_ENCODER to pick an encoder)
#
# The source flashes and beeps every second, with video starting 2/30s after audio (as
# Big Buck Bunny's does) and 44.1kHz audio, so the cut stage must carry an A/V offset
# and resample. It is packaged with no cuts as a control, then with awkward cuts. Both
# runs pick the same frames on the same grid, so each kept flash must land at its
# control position minus what was removed before it, with its beep just as far away;
# comparing against the control cancels the jitter of a 23.976fps flash onset.
require "json"
require "open3"
require "tmpdir"
require_relative "../harness/task_runner"
require_relative "../../lib/edits"

DURATION = 20
OFFSET = 2.0 / 30
FPS = 30
CUTS = [[0, 0.4], [5.5, 7.25], 10.0].freeze
# Positions are exact frame times in both runs, so only float formatting separates them.
POSITION_TOLERANCE = 0.001
# Audio is cut sample-exactly, but the beep can fall differently across AAC frames once
# its position shifts, so allow one AAC frame of detection difference.
OFFSET_TOLERANCE = 1024.0 / 48000

def sh!(*cmd)
  out, err, status = Open3.capture3(*cmd)
  abort "failed: #{cmd.join(" ")}\n#{err}" unless status.success?
  out + err
end

def make_source(path)
  flash = "drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='lt(mod(t+#{OFFSET},1),0.05)'"
  beep = "aevalsrc='if(lt(mod(t,1),0.02),sin(2*PI*1000*t),0)':s=44100:d=#{DURATION}"
  sh!("ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
    "-itsoffset", OFFSET.to_s, "-f", "lavfi", "-i", "color=black:s=854x480:r=24000/1001:d=#{DURATION},#{flash}",
    "-f", "lavfi", "-i", beep, "-map", "0:v", "-map", "1:a",
    "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", path)
end

# Onset times (absolute pts) of each run of bright frames.
def flash_onsets(ts)
  log = sh!("ffmpeg", "-hide_banner", "-copyts", "-i", ts,
    "-vf", "signalstats,metadata=print:key=lavfi.signalstats.YAVG", "-f", "null", "-")
  frames = log.scan(/pts_time:([\d.]+).*?lavfi\.signalstats\.YAVG=([\d.]+)/m).map { |t, y| [t.to_f, y.to_f] }
  first = frames.first[0]
  onsets = frames.each_cons(2).select { |(_, y0), (_, y1)| y0 <= 128 && y1 > 128 }.map { |_, (t, _)| t }
  onsets.unshift(first) if frames.first[1] > 128
  [onsets, first]
end

# Onset times (absolute pts) of each beep.
def beep_onsets(ts)
  log = sh!("ffmpeg", "-hide_banner", "-copyts", "-i", ts, "-af", "silencedetect=n=-30dB:d=0.005", "-f", "null", "-")
  log.scan(/silence_end: ([\d.]+)/).flatten.map(&:to_f)
end

def package(source, breaks)
  out = Dir.mktmpdir("av-sync-out")
  run = TaskRunner.run(source: source, upload_to: out,
    task: {"Type" => "HLS", "Preset" => "Standard Podcast 2026 v1", "AdBreaks" => breaks})
  abort "task failed: #{run.failure[:cause]}" unless run.ok?
  [out, run]
end

# Each flash as [position in the delivered timeline, beep minus flash], absolute pts
# for the offset since that is what a player syncs on.
def measure(out)
  flashes, video_start = flash_onsets(File.join(out, "480p.ts"))
  beeps = beep_onsets(File.join(out, "audio.ts"))
  flashes.map { |f| [f - video_start, beeps.min_by { |b| (b - f).abs } - f] }
end

# Kept spans laid end to end: [source from, source to, delivered start].
def edited_spans(keep, video_end)
  start = 0
  keep.map do |from, to|
    to ||= video_end
    span = [from.to_f, to.to_f, start.to_f]
    start += to - from
    span
  end
end

# The source second a delivered flash came from, and how much was removed before it.
def source_of(position, spans)
  from, _, start = spans.reverse.find { |_, _, s| s <= position + 1e-6 }
  source = from + (position - start)
  [source.round, from - start]
end

Dir.mktmpdir("av-sync") do |dir|
  source = File.join(dir, "flash-beep.mp4")
  make_source(source)
  encoder = ENV.fetch("HLS_VIDEO_ENCODER", "libx264 (default)")

  control_dir, = package(source, [])
  control = measure(control_dir).to_h { |position, offset| [position.round, [position, offset]] }

  cut_dir, cut_run = package(source, CUTS)
  plan = Hls::Edits.build(Hls::Edits.parse(CUTS), duration: DURATION, fps: FPS.to_s)
  spans = edited_spans(plan.keep, DURATION + OFFSET)
  # Flashes whose second survives the edit; each lasts 0.05s, so test its middle.
  expected = control.keys.select { |k| spans.any? { |from, to, _| (from...to).cover?(k + 0.025) } }

  rows = measure(cut_dir).map do |position, offset|
    k, removed_before = source_of(position, spans)
    c_position, c_offset = control.fetch(k)
    {k: k, position_error: (position - (c_position - removed_before)).abs, offset_change: (offset - c_offset).abs}
  end
  worst = ->(key) { rows.map { |r| r[key] }.max || Float::INFINITY }

  puts "encoder:                 #{encoder}"
  puts "AdBreaks:                #{CUTS.to_json}"
  puts "result AdBreaks:         #{cut_run.task_result["AdBreaks"].to_json}"
  puts "result Trims, Duration:  #{cut_run.task_result["Trims"].to_json}, #{cut_run.task_result["Duration"]}"
  puts "control flashes:         #{control.size} (seconds #{control.keys.minmax.join("-")})"
  puts "cut flashes:             #{rows.size}, from seconds #{rows.map { |r| r[:k] }.inspect}"
  puts "expected seconds:        #{expected.inspect}"
  puts "worst position error:    #{format("%.6f", worst.call(:position_error))} s vs control minus removed (limit #{POSITION_TOLERANCE})"
  puts "worst beep offset change:#{format("%.6f", worst.call(:offset_change))} s vs control (limit #{format("%.6f", OFFSET_TOLERANCE)})"

  ok = rows.map { |r| r[:k] } == expected &&
    worst.call(:position_error) <= POSITION_TOLERANCE &&
    worst.call(:offset_change) <= OFFSET_TOLERANCE
  puts ok ? "PASS" : "FAIL"
  [control_dir, cut_dir].each { |d| FileUtils.remove_entry(d) }
  exit(ok ? 0 : 1)
end
