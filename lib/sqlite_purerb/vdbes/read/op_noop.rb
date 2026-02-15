# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpNoop
        def self.execute(_instr, _ctx)
          # No operation
        end
      end
    end
  end
end
