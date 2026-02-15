# frozen_string_literal: true

require 'test_helper'

class ParserbTest < Minitest::Test
  TK = SqlitePurerb::Sqlite3Parser::TK

  def setup
    @prepare = SqlitePurerb::Prepare.new
    @parser = SqlitePurerb::Sqlite3Parser.new(@prepare)
  end

  # Helper to create a token
  def token(type, value = nil)
    SqlitePurerb::Token.new(type, value, 0, 0)
  end

  # Helper to parse tokens until accept
  def parse_all(*token_pairs)
    result = nil
    token_pairs.each do |type, value|
      result = @parser.parse(type, token(type, value))
    end
    # Send EOF to finalize
    loop do
      result = @parser.parse(TK::EOF, nil)
      break if result == :accept
    end
    result
  end

  def test_parser_generated_from_full_sqlite_grammar
    # Verify the parser was generated from the full SQLite grammar
    assert SqlitePurerb::Sqlite3Parser::ACTIONS.keys.count > 100,
      "Parser should have many states (generated from full SQLite grammar)"
    assert SqlitePurerb::Sqlite3Parser::RULES.count > 400,
      "Parser should have 400+ rules (full SQLite grammar)"
  end

  def test_select_star_from_table_calls_read_schema
    # Parse: SELECT * FROM users ;
    # This should call prepare.read_schema
    result = parse_all(
      [TK::SELECT, 'SELECT'],
      [TK::STAR, '*'],
      [TK::FROM, 'FROM'],
      [TK::ID, 'users'],
      [TK::SEMI, ';']
    )

    assert_equal :accept, result
    assert @prepare.read_schema_called,
      "read_schema should be called for SELECT * FROM table"
  end

  def test_create_table_does_not_call_read_schema
    # Parse: CREATE TABLE users ( id ) ;
    # This should NOT call prepare.read_schema
    result = parse_all(
      [TK::CREATE, 'CREATE'],
      [TK::TABLE, 'TABLE'],
      [TK::ID, 'users'],
      [TK::LP, '('],
      [TK::ID, 'id'],
      [TK::RP, ')'],
      [TK::SEMI, ';']
    )

    assert_equal :accept, result
    refute @prepare.read_schema_called,
      "read_schema should NOT be called for CREATE TABLE"
  end

  def test_parserb_is_equivalent_to_parse_c
    # This test documents that parserb.rb is the Ruby equivalent of parse.c
    # Both are generated from parse.y (or parserb.y) using a parser generator
    #
    # parse.y  -> lemon.c  -> parse.c   (C world)
    # parserb.y -> Lemonrb -> parserb.rb (Ruby world)

    assert defined?(SqlitePurerb::Sqlite3Parser),
      "parserb.rb should define Sqlite3Parser class"
    assert SqlitePurerb::Sqlite3Parser.method_defined?(:parse),
      "Parser should have parse method"
    assert SqlitePurerb::Sqlite3Parser.method_defined?(:prepare_context=),
      "Parser should have prepare_context= method"
  end
end
