# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpOpenRead
        def self.execute(instr, ctx)
          # P2 = root page number, used to find table in schema
          root_page = instr.p2
          table_info = ctx.schema.values.find { |t| t[:root_page] == root_page }
          raise "Table not found for root page: #{root_page}" unless table_info

          ctx.cursors[instr.p1] = VDBE::Cursor.new(
            ctx.btree,
            table_info[:root_page],
            table_info[:columns],
            table_info[:has_rowid_pk]
          )
        end
      end
    end
  end
end
