# frozen_string_literal: true

module SqlitePurerb
  class VDBE
    # PseudoCursor reads columns from a record stored in a register
    class PseudoCursor
      attr_reader :register, :num_columns

      def initialize(register, num_columns)
        @register = register
        @num_columns = num_columns
      end

      def column(index)
        @data[index] if @data
      end

      def set_data(data)
        @data = data
      end
    end
  end
end
