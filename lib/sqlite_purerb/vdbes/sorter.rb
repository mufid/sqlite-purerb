# frozen_string_literal: true

module SqlitePurerb
  class VDBE
    # Sorter for ORDER BY - collects records, sorts them, iterates
    class Sorter
      attr_accessor :seqno

      def initialize(key_info)
        @key_info = key_info  # e.g. "k(1,B)" or "k(2,B,B)"
        @records = []
        @position = -1
        @seqno = 0
        parse_key_info(key_info)
      end

      def insert(record)
        @records << record
      end

      def sort!
        @records.sort! { |a, b| compare_records(a, b) }
        @position = 0
      end

      def empty?
        @records.empty?
      end

      def current_data
        return nil if @position < 0 || @position >= @records.length
        @records[@position]
      end

      def next_row
        @position += 1
        @position < @records.length
      end

      def rewind
        @position = 0
        !@records.empty?
      end

      private

      def parse_key_info(info)
        return unless info
        # Parse "k(N,B)" or "k(N,B,B)" format
        # N = number of sort keys, B = sort direction (B=ascending for btree)
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
