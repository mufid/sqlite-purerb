# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    module Read
      module OpDelete
        def self.execute(instr, ctx)
          # Delete current row from cursor P1
          cursor = ctx.cursors[instr.p1]
          cursor.delete_current
        end
      end
    end
  end
end
