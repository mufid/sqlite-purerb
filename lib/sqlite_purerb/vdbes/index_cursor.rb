# frozen_string_literal: true

module SqlitePurerb
  class VDBE
    # IndexCursor for iterating over an index B-tree
    class IndexCursor
      attr_reader :root_page, :position

      def initialize(btree, root_page, num_columns)
        @btree = btree
        @root_page = root_page
        @num_columns = num_columns
        @entries = []
        @position = -1
        @deferred_rowid = nil
        load_entries
      end

      # Seek to first entry >= key_values (array of values to compare)
      # Returns true if found, false if all entries are less than key
      def seek_ge(key_values)
        @position = @entries.index { |entry| compare_key(entry, key_values) >= 0 }
        @position = @entries.length unless @position
        @position < @entries.length
      end

      def next_row
        @position += 1
        @position < @entries.length
      end

      def eof?
        @position >= @entries.length || @position < 0
      end

      # Read a column from the current index entry (index columns, not table columns)
      def column(index)
        return nil if eof?
        @entries[@position][index]
      end

      # Extract the rowid (last field) from the current index entry
      def rowid
        return nil if eof?
        @entries[@position].last
      end

      private

      def load_entries
        @btree.scan_index(@root_page) do |values|
          @entries << values
        end
      end

      # Compare index entry against search key
      # Only compares the first key_values.length columns
      def compare_key(entry, key_values)
        key_values.each_with_index do |key_val, i|
          entry_val = entry[i]
          cmp = compare_values(entry_val, key_val)
          return cmp unless cmp == 0
        end
        0
      end

      def compare_values(a, b)
        return 0 if a.nil? && b.nil?
        return -1 if a.nil?
        return 1 if b.nil?
        # SQLite comparison: numbers < strings < blobs
        a_type = sqlite_type_order(a)
        b_type = sqlite_type_order(b)
        return a_type <=> b_type if a_type != b_type
        a <=> b
      end

      def sqlite_type_order(val)
        case val
        when NilClass then 0
        when Integer, Float then 1
        when String
          val.encoding == Encoding::BINARY ? 3 : 2
        else 2
        end
      end
    end
  end
end
