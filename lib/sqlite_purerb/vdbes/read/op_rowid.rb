# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpRowid
        def self.execute(instr, ctx)
          cursor = ctx.cursors[instr.p1]
          ctx.registers[instr.p2] = cursor.rowid
        end
      end
    end
  end
end
