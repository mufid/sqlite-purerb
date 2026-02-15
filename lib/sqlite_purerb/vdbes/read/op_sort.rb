# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSort
        def self.execute(instr, ctx)
          # Sort and rewind cursor P1, jump to P2 if empty
          cursor = ctx.cursors[instr.p1]
          cursor.sort!
          ctx.pc = instr.p2 if cursor.empty?
        end
      end
    end
  end
end
