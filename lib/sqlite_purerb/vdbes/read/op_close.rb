# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpClose
        def self.execute(instr, ctx)
          ctx.cursors.delete(instr.p1)
        end
      end
    end
  end
end
