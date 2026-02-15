# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSorterOpen
        def self.execute(instr, ctx)
          # P1 = cursor number, P4 = key info (e.g. "k(1,B)")
          ctx.cursors[instr.p1] = VDBE::Sorter.new(instr.p4)
        end
      end
    end
  end
end
