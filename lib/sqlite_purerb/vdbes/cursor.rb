# frozen_string_literal: true

module SqlitePurerb
  class VDBE
    # Cursor for iterating over a table
    class Cursor
      attr_reader :root_page, :rows, :position

      def initialize(btree, root_page, columns, has_rowid_pk)
        @btree = btree
        @root_page = root_page
        @columns = columns
        @has_rowid_pk = has_rowid_pk
        @rows = []
        @position = -1
        load_rows
      end

      def rewind
        @position = 0
        !@rows.empty?
      end

      def next_row
        @position += 1
        @position < @rows.length
      end

      def eof?
        @position >= @rows.length
      end

      def rowid
        return nil if eof?
        @rows[@position][:rowid]
      end

      def column(index)
        return nil if eof?
        @rows[@position][:values][index]
      end

      # Seek to a specific rowid (for DeferredSeek from index)
      def seek_rowid(target_rowid)
        @position = @rows.index { |r| r[:rowid] == target_rowid }
        @position ||= @rows.length
        @position < @rows.length
      end

      private

      def load_rows
        @btree.scan_table(@root_page) do |rowid, values|
          # Handle INTEGER PRIMARY KEY (stored as rowid)
          if @has_rowid_pk && @columns.first&.downcase == 'id'
            values = [rowid] + values[1..]
          end
          @rows << { rowid: rowid, values: values }
        end
      end
    end
  end
end
