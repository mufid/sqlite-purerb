# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpColumn
        def self.execute(instr, ctx)
          cursor = ctx.cursors[instr.p1]
          ctx.registers[instr.p3] = cursor.column(instr.p2)
        end
      end
    end
  end
end
