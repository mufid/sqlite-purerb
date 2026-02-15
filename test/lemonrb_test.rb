# frozen_string_literal: true

require 'test_helper'

class LemonrbTest < Minitest::Test
  def setup
    @lemon = SqlitePurerb::Lemonrb.new
  end

  def test_lemonrb_can_be_instantiated
    assert_instance_of SqlitePurerb::Lemonrb, @lemon
  end

  def test_symbol_types_defined
    assert_equal :terminal, SqlitePurerb::Lemonrb::SymbolType::TERMINAL
    assert_equal :nonterminal, SqlitePurerb::Lemonrb::SymbolType::NONTERMINAL
  end

  def test_action_types_defined
    assert_equal :shift, SqlitePurerb::Lemonrb::ActionType::SHIFT
    assert_equal :accept, SqlitePurerb::Lemonrb::ActionType::ACCEPT
    assert_equal :reduce, SqlitePurerb::Lemonrb::ActionType::REDUCE
    assert_equal :error, SqlitePurerb::Lemonrb::ActionType::ERROR
  end

  def test_assoc_types_defined
    assert_equal :left, SqlitePurerb::Lemonrb::Assoc::LEFT
    assert_equal :right, SqlitePurerb::Lemonrb::Assoc::RIGHT
    assert_equal :none, SqlitePurerb::Lemonrb::Assoc::NONE
  end

  def test_gsymbol_can_be_created
    sym = SqlitePurerb::Lemonrb::GSymbol.new('SELECT', SqlitePurerb::Lemonrb::SymbolType::TERMINAL)
    assert_equal 'SELECT', sym.name
    assert_equal SqlitePurerb::Lemonrb::SymbolType::TERMINAL, sym.type
    assert sym.terminal?
    refute sym.nonterminal?
  end

  def test_grule_can_be_created
    lhs = SqlitePurerb::Lemonrb::GSymbol.new('cmd', SqlitePurerb::Lemonrb::SymbolType::NONTERMINAL)
    rule = SqlitePurerb::Lemonrb::GRule.new(lhs, [], '# action code')
    assert_equal lhs, rule.lhs
    assert_equal [], rule.rhs
    assert_equal '# action code', rule.code
  end

  def test_process_parserb_grammar
    grammar = File.read(File.expand_path('../grammars/parserb.y', __dir__))
    @lemon.process(grammar)

    assert @lemon.symbols.count > 300, "Should have 300+ symbols (full SQLite grammar)"
    assert @lemon.rules.count > 400, "Should have 400+ rules (full SQLite grammar)"
    assert @lemon.states.count > 900, "Should have 900+ states"
  end

  def test_generate_ruby_parser
    grammar = File.read(File.expand_path('../grammars/parserb.y', __dir__))
    @lemon.process(grammar)

    code = @lemon.generate_ruby_parser
    assert code.include?('class Sqlite3Parser'), "Should generate Sqlite3Parser class"
    assert code.include?('module TK'), "Should generate token constants"
    assert code.include?('RULES'), "Should generate rules array"
    assert code.include?('ACTIONS'), "Should generate actions table"
    assert code.include?('GOTOS'), "Should generate gotos table"
  end

  def test_generated_parser_has_semantic_action
    grammar = File.read(File.expand_path('../grammars/parserb.y', __dir__))
    @lemon.process(grammar)

    code = @lemon.generate_ruby_parser
    assert code.include?('@prepare_context.finish_select'),
      "Generated parser should call prepare_context.finish_select for SELECT"
  end
end
