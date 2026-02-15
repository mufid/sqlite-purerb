# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpTransaction
        def self.execute(_instr, _ctx)
          # No-op for read-only databases
        end
      end
    end
  end
end
