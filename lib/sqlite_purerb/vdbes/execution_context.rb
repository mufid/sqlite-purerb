# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    class ExecutionContext
      attr_accessor :pc, :halt
      attr_reader :registers, :cursors, :results, :program, :btree, :schema

      def initialize(program, btree, schema)
        @pc = 0
        @halt = false
        @registers = Array.new(256)
        @cursors = {}
        @results = []
        @program = program
        @btree = btree
        @schema = schema
      end
    end
  end
end
