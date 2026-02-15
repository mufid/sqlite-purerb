# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpHalt
        def self.execute(_instr, ctx)
          ctx.halt = true
        end
      end
    end
  end
end
