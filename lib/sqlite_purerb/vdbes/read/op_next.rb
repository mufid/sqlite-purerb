# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpNext
        def self.execute(instr, ctx)
          cursor = ctx.cursors[instr.p1]
          if cursor.next_row
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
