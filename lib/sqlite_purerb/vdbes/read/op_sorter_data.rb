# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpSorterData
        def self.execute(instr, ctx)
          # P1 = sorter cursor, P2 = destination register
          sorter = ctx.cursors[instr.p1]
          data = sorter.current_data
          ctx.registers[instr.p2] = data
          # Also update any pseudo cursor that reads from this register
          ctx.cursors.each_value do |c|
            c.set_data(data) if c.is_a?(VDBE::PseudoCursor) && c.register == instr.p2
          end
        end
      end
    end
  end
end
