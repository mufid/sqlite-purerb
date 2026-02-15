# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpString8
        def self.execute(instr, ctx)
          ctx.registers[instr.p2] = instr.p4
        end
      end
    end
  end
end
