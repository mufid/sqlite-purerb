# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpRealAffinity
        def self.execute(instr, ctx)
          val = ctx.registers[instr.p1]
          ctx.registers[instr.p1] = val.to_f if val.is_a?(Integer)
        end
      end
    end
  end
end
