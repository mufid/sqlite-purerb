# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpNull
        def self.execute(instr, ctx)
          ctx.registers[instr.p2] = nil
        end
      end
    end
  end
end
