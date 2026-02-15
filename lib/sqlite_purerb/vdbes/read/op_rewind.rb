# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpRewind
        def self.execute(instr, ctx)
          cursor = ctx.cursors[instr.p1]
          unless cursor.rewind
            ctx.pc = instr.p2
          end
        end
      end
    end
  end
end
