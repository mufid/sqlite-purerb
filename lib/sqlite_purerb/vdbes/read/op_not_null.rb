# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpNotNull
        def self.execute(instr, ctx)
          ctx.pc = instr.p2 unless ctx.registers[instr.p1].nil?
        end
      end
    end
  end
end
