# frozen_string_literal: true

module SqlitePurerb
  class VDBE
    # EphemeralTable is a sorted bounded collection for ORDER BY + LIMIT (top-N)
    class EphemeralTable
      attr_accessor :seqno

      def initialize(key_info)
        @key_info = key_info
        @records = []
        @position = -1
        @seqno = 0
        parse_key_info(key_info)
      end

      def insert(record)
        @records << record
      end

      def size
        @records.length
      end

      def last_entry
        @records.sort! { |a, b| compare_records(a, b) }
        @position = @records.length - 1
      end

      def current_key_le?(key_values, num_keys)
        return false if @position < 0 || @position >= @records.length
        current = @records[@position]
        num_keys.times do |i|
          cmp = compare_values(current[i], key_values[i])
          dir = @directions[i] || :asc
          cmp = -cmp if dir == :desc
          return true if cmp < 0
          return false if cmp > 0
        end
        true  # equal counts as LE
      end

      def delete_current
        @records.delete_at(@position) if @position >= 0 && @position < @records.length
      end

      def sort!
        @records.sort! { |a, b| compare_records(a, b) }
        @position = 0
      end

      def rewind
        @position = 0
        !@records.empty?
      end

      def empty?
        @records.empty?
      end

      def next_row
        @position += 1
        @position < @records.length
      end

      def column(index)
        return nil if @position < 0 || @position >= @records.length
        @records[@position][index]
      end

      private

      def parse_key_info(info)
        return unless info
        if info =~ /k\((\d+)((?:,-?[A-Z])*)\)/
          @num_keys = $1.to_i
          dirs = $2.split(',').reject(&:empty?)
          @directions = dirs.map { |d| d.start_with?('-') ? :desc : :asc }
        else
          @num_keys = 1
          @directions = [:asc]
        end
      end

      def compare_records(a, b)
        @num_keys.times do |i|
          va = a[i]
          vb = b[i]
          cmp = compare_values(va, vb)
          dir = @directions[i] || :asc
          cmp = -cmp if dir == :desc
          return cmp unless cmp == 0
        end
        0
      end

      def compare_values(a, b)
        return 0 if a.nil? && b.nil?
        return -1 if a.nil?
        return 1 if b.nil?
        a <=> b
      end
    end
  end
end
