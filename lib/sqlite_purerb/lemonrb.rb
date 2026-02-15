# frozen_string_literal: true

module SqlitePurerb
  # Lemonrb - Ruby implementation of Lemon parser generator
  #
  # Converts a Lemon-format grammar (.y file) into a Ruby parser.
  # This implements the core LALR(1) parser generation algorithm.
  #
  class Lemonrb
    # Symbol types
    module SymbolType
      TERMINAL = :terminal
      NONTERMINAL = :nonterminal
    end

    # Action types
    module ActionType
      SHIFT = :shift
      REDUCE = :reduce
      ACCEPT = :accept
      ERROR = :error
    end

    # Associativity
    module Assoc
      LEFT = :left
      RIGHT = :right
      NONE = :none
    end

    # A grammar symbol (terminal or non-terminal)
    class GSymbol
      attr_accessor :name, :index, :type, :prec, :assoc, :rules, :first_set, :lambda

      def initialize(name, type)
        @name = name
        @type = type
        @index = nil
        @prec = -1
        @assoc = Assoc::NONE
        @rules = []        # Rules where this is the LHS
        @first_set = Set.new
        @lambda = false    # Can derive empty string?
      end

      def terminal?
        @type == SymbolType::TERMINAL
      end

      def nonterminal?
        @type == SymbolType::NONTERMINAL
      end

      def to_s
        @name
      end
    end

    # A grammar rule (production)
    class GRule
      attr_accessor :index, :lhs, :rhs, :code, :prec_sym, :lhs_alias, :rhs_aliases

      def initialize(lhs, rhs, code = nil)
        @index = nil
        @lhs = lhs         # LHS symbol
        @rhs = rhs         # Array of RHS symbols
        @code = code       # Action code
        @prec_sym = nil    # Precedence symbol
        @lhs_alias = nil
        @rhs_aliases = []
      end

      def to_s
        "#{@lhs.name} ::= #{@rhs.map(&:name).join(' ')}"
      end
    end

    # An LR(0) item: a rule with a dot position
    class Item
      attr_accessor :rule, :dot, :lookaheads

      def initialize(rule, dot)
        @rule = rule
        @dot = dot
        @lookaheads = Set.new
      end

      def complete?
        @dot >= @rule.rhs.length
      end

      def next_symbol
        return nil if complete?
        @rule.rhs[@dot]
      end

      def advance
        Item.new(@rule, @dot + 1)
      end

      def ==(other)
        @rule == other.rule && @dot == other.dot
      end

      def eql?(other)
        self == other
      end

      def hash
        [@rule, @dot].hash
      end

      def to_s
        rhs_parts = @rule.rhs.map(&:name)
        rhs_parts.insert(@dot, '•')
        "#{@rule.lhs.name} → #{rhs_parts.join(' ')}"
      end
    end

    # A parser state (set of items)
    class State
      attr_accessor :index, :items, :actions, :gotos, :kernel

      def initialize(kernel_items)
        @index = nil
        @kernel = kernel_items.to_set
        @items = Set.new
        @actions = {}   # terminal -> [action_type, target]
        @gotos = {}     # nonterminal -> state
      end

      def ==(other)
        @kernel == other.kernel
      end

      def eql?(other)
        self == other
      end

      def hash
        @kernel.hash
      end
    end

    # Main instance variables
    attr_reader :symbols, :rules, :states, :start_symbol
    attr_accessor :token_prefix, :parser_name, :extra_context

    def initialize
      @symbols = {}        # name -> GSymbol
      @terminals = []
      @nonterminals = []
      @rules = []
      @states = []
      @start_symbol = nil
      @token_prefix = ''
      @parser_name = 'Parser'
      @extra_context = nil
      @eof_symbol = nil
    end

    # Parse a grammar file and build the parser
    def process(grammar_source)
      # Step 1: Parse the grammar using our existing lemon_parser
      parse_grammar(grammar_source)

      # Step 2: Compute first sets
      compute_first_sets

      # Step 3: Build LR(0) states
      build_states

      # Step 4: Build action and goto tables
      build_tables

      self
    end

    # Generate Ruby parser code
    def generate_ruby_parser(output_path = nil)
      code = generate_parser_code
      if output_path
        File.write(output_path, code)
      end
      code
    end

    private

    # =========================================================================
    # Step 1: Parse the grammar
    # =========================================================================

    def parse_grammar(source)
      # Load the Racc-generated Lemon grammar parser
      grammar_parser_path = File.expand_path('../../grammars/lemon_parser.rb', __dir__)
      require grammar_parser_path

      parser = ::LemonParser.new
      ast = parser.parse(source)

      # Process directives and rules
      ast.each do |node|
        case node.first
        when :directive
          process_directive(node)
        when :directive_list
          process_directive_list(node)
        when :rule
          process_rule(node)
        end
      end

      # Ensure we have an EOF symbol
      @eof_symbol = get_or_create_symbol('$', SymbolType::TERMINAL)

      # Set start symbol if not set
      if @start_symbol.nil? && @nonterminals.any?
        @start_symbol = @nonterminals.first
      end

      # Add augmented start rule: S' -> S $
      if @start_symbol
        augmented_start = get_or_create_symbol("#{@start_symbol.name}'", SymbolType::NONTERMINAL)
        start_rule = GRule.new(augmented_start, [@start_symbol, @eof_symbol])
        start_rule.index = @rules.length
        @rules.unshift(start_rule)
        augmented_start.rules << start_rule

        # Renumber rules
        @rules.each_with_index { |r, i| r.index = i }
      end

      # Assign indices to symbols
      index = 0
      @terminals.each { |s| s.index = index; index += 1 }
      @nonterminals.each { |s| s.index = index; index += 1 }
    end

    def process_directive(node)
      _, name, value = node
      case name
      when 'name'
        # Capitalize first letter for valid Ruby class name
        @parser_name = value.sub(/\A([a-z])/) { $1.upcase }
      when 'token_prefix'
        @token_prefix = value
      when 'start_symbol'
        @start_symbol = get_or_create_symbol(value, SymbolType::NONTERMINAL)
      when 'extra_context'
        @extra_context = value
      end
    end

    def process_directive_list(node)
      _, directive_type, tokens = node
      case directive_type
      when 'token'
        tokens.each do |t|
          next unless t.is_a?(String)
          get_or_create_symbol(t, SymbolType::TERMINAL)
        end
      when 'left', 'right', 'nonassoc'
        prec = @terminals.count { |t| t.prec >= 0 } + 1
        assoc = case directive_type
                when 'left' then Assoc::LEFT
                when 'right' then Assoc::RIGHT
                else Assoc::NONE
                end
        tokens.each do |t|
          next unless t.is_a?(String)
          sym = get_or_create_symbol(t, SymbolType::TERMINAL)
          sym.prec = prec
          sym.assoc = assoc
        end
      end
    end

    def process_rule(node)
      _, lhs_info, rhs_list, code, prec = node
      lhs_name, lhs_alias = lhs_info

      lhs = get_or_create_symbol(lhs_name, SymbolType::NONTERMINAL)

      rhs_symbols = []
      rhs_aliases = []

      rhs_list.each do |item|
        if item.is_a?(Array)
          if item.first == :alt
            # Handle alternation - for now just take first alternative
            item[1].each do |alt_name|
              sym = get_or_create_symbol(alt_name, SymbolType::TERMINAL)
              rhs_symbols << sym
              rhs_aliases << nil
            end
            name, ali = item[2]
            sym = get_or_create_symbol(name, SymbolType::TERMINAL)
            rhs_symbols << sym
            rhs_aliases << ali
          else
            name, ali = item
            # Determine if terminal or non-terminal
            # Convention: ALL_CAPS = terminal, otherwise = nonterminal
            type = name.match?(/^[A-Z_]+$/) ? SymbolType::TERMINAL : SymbolType::NONTERMINAL
            sym = get_or_create_symbol(name, type)
            rhs_symbols << sym
            rhs_aliases << ali
          end
        end
      end

      rule = GRule.new(lhs, rhs_symbols, code)
      rule.index = @rules.length
      rule.lhs_alias = lhs_alias
      rule.rhs_aliases = rhs_aliases
      rule.prec_sym = prec ? get_or_create_symbol(prec, SymbolType::TERMINAL) : nil

      @rules << rule
      lhs.rules << rule
    end

    def get_or_create_symbol(name, type)
      return @symbols[name] if @symbols[name]

      sym = GSymbol.new(name, type)
      @symbols[name] = sym

      if type == SymbolType::TERMINAL
        @terminals << sym
      else
        @nonterminals << sym
      end

      sym
    end

    # =========================================================================
    # Step 2: Compute FIRST sets
    # =========================================================================

    def compute_first_sets
      # For terminals, FIRST(t) = {t}
      @terminals.each do |t|
        t.first_set = Set.new([t])
      end

      # Iteratively compute FIRST sets for nonterminals
      changed = true
      while changed
        changed = false

        @rules.each do |rule|
          lhs = rule.lhs

          # Compute FIRST of RHS
          first_of_rhs = first_of_sequence(rule.rhs)

          # Add to LHS first set
          old_size = lhs.first_set.size
          lhs.first_set.merge(first_of_rhs)

          if lhs.first_set.size > old_size
            changed = true
          end

          # Check if rule can derive empty
          if rule.rhs.empty? || rule.rhs.all? { |s| s.nonterminal? && s.lambda }
            unless lhs.lambda
              lhs.lambda = true
              changed = true
            end
          end
        end
      end
    end

    def first_of_sequence(symbols)
      result = Set.new

      symbols.each do |sym|
        if sym.terminal?
          result.add(sym)
          return result  # Terminal always has itself, stop
        else
          result.merge(sym.first_set)
          return result unless sym.lambda  # Stop if can't derive empty
        end
      end

      result
    end

    # =========================================================================
    # Step 3: Build LR(0) states
    # =========================================================================

    def build_states
      # Start with initial state containing S' -> • S $
      initial_item = Item.new(@rules.first, 0)
      initial_state = State.new([initial_item])
      closure(initial_state)
      initial_state.index = 0
      @states << initial_state

      state_map = { initial_state.kernel => initial_state }

      # Process states until no new states are created
      i = 0
      while i < @states.length
        state = @states[i]

        # Group items by next symbol
        transitions = Hash.new { |h, k| h[k] = [] }

        state.items.each do |item|
          next_sym = item.next_symbol
          next unless next_sym
          transitions[next_sym] << item.advance
        end

        # Create new states for each transition
        transitions.each do |sym, kernel_items|
          kernel_set = kernel_items.to_set

          if state_map[kernel_set]
            next_state = state_map[kernel_set]
          else
            next_state = State.new(kernel_items)
            closure(next_state)
            next_state.index = @states.length
            @states << next_state
            state_map[kernel_set] = next_state
          end

          if sym.terminal?
            state.actions[sym] = [ActionType::SHIFT, next_state]
          else
            state.gotos[sym] = next_state
          end
        end

        i += 1
      end
    end

    def closure(state)
      state.items.merge(state.kernel)

      added = true
      while added
        added = false

        state.items.to_a.each do |item|
          next_sym = item.next_symbol
          next unless next_sym&.nonterminal?

          next_sym.rules.each do |rule|
            new_item = Item.new(rule, 0)
            unless state.items.include?(new_item)
              state.items.add(new_item)
              added = true
            end
          end
        end
      end
    end

    # =========================================================================
    # Step 4: Build action and goto tables
    # =========================================================================

    def build_tables
      @states.each do |state|
        state.items.each do |item|
          if item.complete?
            if item.rule == @rules.first
              # Accept on EOF
              state.actions[@eof_symbol] = [ActionType::ACCEPT, nil]
            else
              # Reduce
              # For SLR: reduce on all terminals in FOLLOW(LHS)
              # For simplicity, reduce on all terminals (may cause conflicts)
              @terminals.each do |t|
                existing = state.actions[t]
                if existing.nil?
                  state.actions[t] = [ActionType::REDUCE, item.rule]
                elsif existing[0] == ActionType::SHIFT
                  # Shift-reduce conflict - prefer shift for now
                  # Could use precedence to resolve
                elsif existing[0] == ActionType::REDUCE && existing[1] != item.rule
                  # Reduce-reduce conflict - prefer earlier rule
                  if item.rule.index < existing[1].index
                    state.actions[t] = [ActionType::REDUCE, item.rule]
                  end
                end
              end
            end
          end
        end
      end
    end

    # =========================================================================
    # Code Generation
    # =========================================================================

    def generate_parser_code
      <<~RUBY
        # frozen_string_literal: true
        # Generated by Lemonrb from grammar file
        # Do not edit manually

        module SqlitePurerb
          class #{@parser_name}
            class ParseError < StandardError; end

            # Token types
            module TK
              #{generate_token_constants}
            end

            # Rule information: [lhs_index, rhs_count]
            RULES = [
              #{generate_rules_array}
            ].freeze

            # Action table: state -> { terminal -> [action, value] }
            ACTIONS = {
              #{generate_actions_hash}
            }.freeze

            # Goto table: state -> { nonterminal -> state }
            GOTOS = {
              #{generate_gotos_hash}
            }.freeze

            attr_accessor :prepare_context

            def initialize(prepare_context = nil)
              @prepare_context = prepare_context
              @stack = [[0, nil]]  # [state, value]
            end

            def parse(token_type, token_value = nil)
              loop do
                state = @stack.last[0]
                action = ACTIONS.dig(state, token_type)

                unless action
                  raise ParseError, "Unexpected token \#{token_type} in state \#{state}"
                end

                case action[0]
                when :shift
                  @stack.push([action[1], token_value])
                  return :continue
                when :reduce
                  rule_index = action[1]
                  lhs, rhs_count = RULES[rule_index]

                  # Pop RHS values
                  values = []
                  rhs_count.times { values.unshift(@stack.pop[1]) }

                  # Execute semantic action
                  result = execute_action(rule_index, values)

                  # Push LHS
                  goto_state = GOTOS.dig(@stack.last[0], lhs)
                  @stack.push([goto_state, result])
                  # Continue parsing same token
                when :accept
                  return :accept
                end
              end
            end

            def parse_tokens(tokens)
              tokens.each do |token|
                result = parse(token.type, token)
                return result if result == :accept
              end
              parse(TK::EOF, nil)  # Signal end of input
            end

            private

            def execute_action(rule_index, values)
              case rule_index
              #{generate_action_cases}
              else
                values.first
              end
            end
          end
        end
      RUBY
    end

    RUBY_RESERVED_KEYWORDS = %w[
      BEGIN END __FILE__ __LINE__ __ENCODING__
      alias and begin break case class def defined? do else elsif end
      ensure false for if in module next nil not or redo rescue retry
      return self super then true undef unless until when while yield
    ].map(&:upcase).freeze

    def generate_token_constants
      lines = []
      lines << "EOF = 0"
      @terminals.each_with_index do |t, i|
        const_name = t.name.gsub(/[^A-Za-z0-9_]/, '_').upcase
        # Escape Ruby reserved keywords by adding underscore suffix
        const_name = "#{const_name}_" if RUBY_RESERVED_KEYWORDS.include?(const_name)
        lines << "#{const_name} = #{i + 1}"
      end
      lines.join("\n      ")
    end

    def generate_rules_array
      @rules.map do |rule|
        lhs_sym = rule.lhs.name.to_sym.inspect
        "[#{lhs_sym}, #{rule.rhs.length}]"
      end.join(",\n        ")
    end

    def generate_actions_hash
      @states.map do |state|
        actions = state.actions.map do |sym, (action_type, value)|
          target = case action_type
                   when ActionType::SHIFT then value.index
                   when ActionType::REDUCE then value.index
                   when ActionType::ACCEPT then nil
                   end
          sym_name = sym.name == '$' ? 'EOF' : sym.name.upcase
          # Escape Ruby reserved keywords by adding underscore suffix
          sym_name = "#{sym_name}_" if RUBY_RESERVED_KEYWORDS.include?(sym_name)
          "TK::#{sym_name} => [:#{action_type}, #{target.inspect}]"
        end.join(", ")
        "#{state.index} => { #{actions} }"
      end.join(",\n        ")
    end

    def generate_gotos_hash
      @states.map do |state|
        next if state.gotos.empty?
        gotos = state.gotos.map do |sym, target_state|
          "#{sym.name.to_sym.inspect} => #{target_state.index}"
        end.join(", ")
        "#{state.index} => { #{gotos} }"
      end.compact.join(",\n        ")
    end

    def generate_action_cases
      @rules.each_with_index.map do |rule, index|
        next unless rule.code && !rule.code.strip.empty?
        code = translate_action_code(rule)
        "when #{index}\n          #{code}"
      end.compact.join("\n        ")
    end

    def translate_action_code(rule)
      code = rule.code.to_s.strip
      return "nil" if code.empty? || code == "# TODO rewrite in Ruby"

      # Replace pParse with @prepare_context
      code = code.gsub(/pParse\./, '@prepare_context.')
      code = code.gsub(/pParse/, '@prepare_context')

      # Replace rule variables (A, X, Y, etc.) with values[index]
      # Build mapping from alias name to index
      alias_to_index = {}
      rule.rhs_aliases.each_with_index do |ali, idx|
        alias_to_index[ali] = idx if ali
      end

      # Also map LHS alias if it refers to first RHS element (common pattern like A ::= ... A ...)
      if rule.lhs_alias && !alias_to_index.key?(rule.lhs_alias)
        # LHS alias typically maps to first RHS element for pass-through
        alias_to_index[rule.lhs_alias] = 0 if rule.rhs_aliases.first == rule.lhs_alias
      end

      # Substitute variable names with values[index]
      # Match whole words only (not inside other identifiers)
      alias_to_index.each do |ali, idx|
        code = code.gsub(/\b#{Regexp.escape(ali)}\b/, "values[#{idx}]")
      end

      code
    end
  end
end
