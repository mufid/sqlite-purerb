# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpOpenRead
        def self.execute(instr, ctx)
          root_page = instr.p2

          # Check if P4 is a key info string (e.g., "k(2,,)") indicating an index cursor
          if instr.p4.is_a?(String) && instr.p4.start_with?('k(')
            # Index cursor: P4 = key info, P5 = flags (e.g., OPFLAG_SEEKEQ=2)
            num_columns = parse_key_columns(instr.p4)
            ctx.cursors[instr.p1] = VDBE::IndexCursor.new(
              ctx.btree,
              root_page,
              num_columns
            )
          else
            # Table cursor: P4 = number of columns
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

        # Parse "k(N,,)" or "k(N,B,B)" to extract N (number of key columns)
        def self.parse_key_columns(key_info)
          if key_info =~ /k\((\d+)/
            $1.to_i
          else
            1
          end
        end
      end
    end
  end
end
