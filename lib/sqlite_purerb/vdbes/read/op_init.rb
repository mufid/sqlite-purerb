# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpInit
        def self.execute(instr, ctx)
          ctx.pc = instr.p2
        end
      end
    end
  end
end
