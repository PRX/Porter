# frozen_string_literal: true

require_relative "timing"

module Hls
  # Turns AdBreaks into an edit.
  #
  # With no ranges, there's no edits - jobs with no breaks or point-only breaks pass through untouched
  module Edits
    # making some data structures to organize the code a bit better (just for this module)
    # Cut is what's passed in
    # Removal is what we calculate from it; one at the head or tail is a trim
    # Point is a break time
    # Request is a break time to ask Boundaries for, with the removed duration
    # Plan is the final result of build()
    # Placed is what BreakReport reads
    Cut = Struct.new(:requested, :start, :stop, :index)
    # A Cut resolved against the source: on the frame grid, with a tail ending at the duration
    Removal = Struct.new(:cut, :from, :to, :head, :tail) do
      def requested = cut.requested

      def removed = to - from

      def trim? = head || tail

      def position = head ? :head : :tail
    end
    # A break time: requested as given, at on the frame grid
    Point = Struct.new(:requested, :at)
    Request = Struct.new(:requested, :boundary_time, :removed)
    # keep: source spans to keep, [start, end] in seconds, end nil for the end; nil when nothing is cut
    Plan = Struct.new(:keep, :duration, :breaks, :trims) do
      def cut? = !keep.nil?

      def removed = trims.sum(&:removed) + breaks.sum { |b| b.removed || 0 }
    end
    # What BreakReport reads: the original request, plus where it landed
    Placed = Struct.new(:requested, :at, :removed)

    # All class methods here, no real state to keep around
    class << self
      include Timing

      # Before the download, so a malformed request fails without fetching anything.
      def parse(raw)
        entries = Array(raw).each_with_index.map do |item, index|
          item.is_a?(Array) ? cut(item, index) : Float(item)
        end
        points = entries.grep(Float)
        unless points.all?(&:finite?) && points.all?(&:positive?)
          raise StandardError, "AdBreaks must be positive numbers of seconds"
        end
        entries
      end

      def build(entries, duration:, fps:)
        cuts = entries.grep(Cut)
        if cuts.empty?
          breaks = entries.map { |t| Request.new(requested: t, boundary_time: t, removed: nil) }
          return Plan.new(keep: nil, duration: duration, breaks: breaks, trims: [])
        end

        fps = exact(fps)
        duration = exact(duration)
        frame = Rational(1) / fps
        removals = cuts.map { |c| removal(c, fps, duration, frame) }.sort_by(&:from)
        points = entries.grep(Float).map { |t| Point.new(requested: t, at: quantize(t, fps)) }

        check_removals(removals, duration)
        check_points(points, removals, duration)

        out = ->(t) { t - removals.select { |r| r.to <= t }.sum(&:removed) }

        trims, inner = removals.partition(&:trim?)
        breaks = points.map { |p| Request.new(requested: p.requested, boundary_time: out.call(p.at), removed: nil) } +
          inner.map { |r| Request.new(requested: r.requested, boundary_time: out.call(r.from), removed: r.removed) }

        Plan.new(keep: keep(removals), duration: duration - removals.sum(&:removed),
          breaks: breaks.sort_by(&:boundary_time), trims: trims)
      end

      # Joins Boundaries' placed breaks back to what was asked for. Boundaries keeps the
      # object it was given as Boundaries::Break#requested, which is our boundary_time.
      def placed(plan, layout)
        by_time = plan.breaks.to_h { |b| [b.boundary_time, b] }
        layout.breaks.map do |lb|
          b = by_time.fetch(lb.requested)
          Placed.new(requested: b.requested, at: lb.at, removed: b.removed)
        end
      end

      private

      def cut(pair, index)
        unless pair.length == 2
          raise StandardError, "AdBreaks[#{index}] #{pair.inspect}: a range is [start, end]"
        end
        start = pair[0].nil? ? 0.0 : seconds(pair[0], index, pair)
        stop = pair[1].nil? ? nil : seconds(pair[1], index, pair)
        if start.negative?
          raise StandardError, "AdBreaks[#{index}] #{pair.inspect}: start can't be negative"
        end
        if stop && stop <= start
          raise StandardError, "AdBreaks[#{index}] #{pair.inspect}: end must be after start"
        end
        Cut.new(requested: [pair[0] && start, stop], start: start, stop: stop, index: index)
      end

      def seconds(value, index, pair)
        f = Float(value)
        raise ArgumentError unless f.finite?
        f
      rescue ArgumentError, TypeError
        raise StandardError, "AdBreaks[#{index}] #{pair.inspect}: start and end must be " \
                             "numbers of seconds (null means the start or the end)"
      end

      # An end within the last frame is a tail trim: nothing usable would be left after it.
      def removal(cut, fps, duration, frame)
        from = quantize(cut.start, fps)
        to = cut.stop.nil? ? nil : quantize(cut.stop, fps)
        label = "AdBreaks[#{cut.index}] #{cut.requested.inspect}"

        if to && to <= from
          raise StandardError, "#{label} is shorter than one frame once rounded to frames"
        end
        if from >= duration
          raise StandardError, "#{label} starts at or after the end of the #{fmt(duration)}s source"
        end

        tail = to.nil? || to > duration - frame
        head = from.zero?
        raise StandardError, "#{label} would remove the whole source" if head && tail

        Removal.new(cut: cut, from: from, to: tail ? duration : to, head: head, tail: tail)
      end

      def check_removals(removals, duration)
        removals.each_cons(2) do |a, b|
          next if a.to < b.from
          raise StandardError, "AdBreaks ranges #{a.requested.inspect} and " \
                               "#{b.requested.inspect} overlap or touch; leave at least a frame between them"
        end
      end

      def check_points(points, removals, duration)
        points.each do |p|
          if p.at >= duration
            raise StandardError, "AdBreaks break #{p.requested} is at or after the end of the #{fmt(duration)}s source"
          end
          inside = removals.find { |r| p.at.between?(r.from, r.to) }
          next unless inside
          raise StandardError, "AdBreaks break #{p.requested} falls inside or on the edge of the removed " \
                               "range #{inside.requested.inspect}"
        end
        points.group_by(&:at).each_value do |same|
          next if same.length < 2
          raise StandardError, "AdBreaks #{same.map(&:requested).join(" and ")} land on the same frame"
        end
      end

      def keep(removals)
        kept = []
        cursor = Rational(0)
        removals.each do |r|
          kept << [cursor, r.from] if r.from > cursor
          cursor = r.to
          return kept if r.tail
        end
        kept << [cursor, nil]
      end
    end
  end
end
