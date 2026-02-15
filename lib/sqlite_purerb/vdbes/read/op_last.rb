# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpLast
        def self.execute(instr, ctx)
          # Move cursor P1 to last entry
          cursor = ctx.cursors[instr.p1]
          cursor.last_entry
        end
      end
    end
  end
end
