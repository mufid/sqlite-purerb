# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpDeferredSeek
        def self.execute(instr, ctx)
          # P1 = index cursor
          # P2 = table cursor
          # Extract rowid from index cursor and seek the table cursor to that row
          index_cursor = ctx.cursors[instr.p1]
          table_cursor = ctx.cursors[instr.p2]

          target_rowid = index_cursor.rowid
          table_cursor.seek_rowid(target_rowid)
        end
      end
    end
  end
end
