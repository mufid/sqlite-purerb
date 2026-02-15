# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpOpenEphemeral
        def self.execute(instr, ctx)
          # P1 = cursor number, P4 = key info
          ctx.cursors[instr.p1] = VDBE::EphemeralTable.new(instr.p4)
        end
      end
    end
  end
end
