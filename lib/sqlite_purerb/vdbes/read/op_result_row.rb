# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpResultRow
        def self.execute(instr, ctx)
          row = {}
          instr.p2.times do |i|
            col_name = ctx.program.column_names[i] || "column#{i}"
            row[col_name] = ctx.registers[instr.p1 + i]
          end
          ctx.results << row
        end
      end
    end
  end
end
