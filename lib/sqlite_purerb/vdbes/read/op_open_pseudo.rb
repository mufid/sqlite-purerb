# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpOpenPseudo
        def self.execute(instr, ctx)
          # P1 = cursor number, P2 = register, P3 = num columns
          ctx.cursors[instr.p1] = VDBE::PseudoCursor.new(instr.p2, instr.p3)
        end
      end
    end
  end
end
