# frozen_string_literal: true

require_relative 'test_helper'

class BinaryAllFieldTypesTest < Minitest::Test
  DB_PATH = File.expand_path('../../binary-test/001-all-field-types.sqlite3', __dir__)

  def setup
    @db = SqlitePurerb::Database.new(DB_PATH)
  end

  def teardown
    @db.close
  end

  # -- Schema tests --

  def test_tables
    assert_includes @db.tables, 'all_types'
  end

  def test_column_count
    assert_equal 34, @db.schema['all_types'][:columns].length
  end

  def test_column_names
    expected = %w[
      id
      col_integer col_int col_tinyint col_smallint col_mediumint
      col_bigint col_unsigned_big_int col_int2 col_int4 col_int8
      col_text col_character col_varchar col_varying_character
      col_nchar col_native_character col_nvarchar col_clob
      col_blob col_json_blob col_no_type
      col_real col_double col_double_precision col_float
      col_numeric col_decimal col_boolean col_date col_datetime
      col_timestamp col_json col_jsonb
    ]
    assert_equal expected, @db.schema['all_types'][:columns]
  end

  def test_has_rowid_pk
    assert @db.schema['all_types'][:has_rowid_pk]
  end

  # -- Row count --

  def test_row_count
    rows = @db.execute('SELECT * FROM all_types')
    assert_equal 5, rows.length
  end

  # -- Row 1: typical positive values --

  def test_row1_integers
    row = select_row(1)
    assert_equal 1,             row['id']
    assert_equal 42,            row['col_integer']
    assert_equal 42,            row['col_int']
    assert_equal 7,             row['col_tinyint']
    assert_equal 1000,          row['col_smallint']
    assert_equal 100_000,       row['col_mediumint']
    assert_equal 9_999_999_999_999, row['col_bigint']
    assert_equal 42,            row['col_unsigned_big_int']
    assert_equal 99,            row['col_int2']
    assert_equal 42,            row['col_int4']
    assert_equal 42,            row['col_int8']
  end

  def test_row1_text
    row = select_row(1)
    assert_equal 'hello world',     row['col_text']
    assert_equal 'character val',   row['col_character']
    assert_equal 'varchar value',   row['col_varchar']
    assert_equal 'varying char val', row['col_varying_character']
    assert_equal 'nchar value',     row['col_nchar']
    assert_equal 'native char val', row['col_native_character']
    assert_equal 'nvarchar value',  row['col_nvarchar']
    assert_equal 'clob value',      row['col_clob']
  end

  def test_row1_blob
    row = select_row(1)
    assert_equal "\xDE\xAD\xBE\xEF".b, row['col_blob'].b
  end

  def test_row1_blob_affinity_text
    row = select_row(1)
    # JSON BLOB and no-type columns store text values
    assert_equal '{"key":"blob_json"}', row['col_json_blob']
    assert_equal 'no type value',       row['col_no_type']
  end

  def test_row1_real
    row = select_row(1)
    assert_in_delta 3.14,        row['col_real'].to_f,  1e-10
    assert_in_delta 2.71828,     row['col_double'].to_f, 1e-10
    assert_in_delta 1.23456789,  row['col_double_precision'].to_f, 1e-10
    assert_in_delta 1.5,         row['col_float'].to_f, 1e-10
  end

  def test_row1_numeric
    row = select_row(1)
    assert_equal 12345,          row['col_numeric']
    assert_in_delta 99.99,       row['col_decimal'].to_f, 1e-10
    assert_equal 1,              row['col_boolean']
    assert_equal '2025-06-15',   row['col_date']
    assert_equal '2025-06-15 10:30:00', row['col_datetime']
    assert_equal '2025-06-15 10:30:00', row['col_timestamp']
    assert_equal '{"name":"Alice","age":30}', row['col_json']
    assert_equal '{"name":"Alice"}',          row['col_jsonb']
  end

  # -- Row 2: negative values, zeros, empty strings --

  def test_row2_negative_integers
    row = select_row(2)
    assert_equal(-1,                  row['col_integer'])
    assert_equal(-1,                  row['col_int'])
    assert_equal(-128,                row['col_tinyint'])
    assert_equal(-32_768,             row['col_smallint'])
    assert_equal(-8_388_608,          row['col_mediumint'])
    assert_equal(-140_737_488_355_328, row['col_bigint'])
    assert_equal(-1,                  row['col_unsigned_big_int'])
    assert_equal(-99,                 row['col_int2'])
    assert_equal(-42,                 row['col_int4'])
    assert_equal(-42,                 row['col_int8'])
  end

  def test_row2_empty_strings
    row = select_row(2)
    assert_equal '', row['col_text']
    assert_equal '', row['col_character']
    assert_equal '', row['col_varying_character']
    assert_equal '', row['col_nchar']
    assert_equal '', row['col_native_character']
    assert_equal '', row['col_nvarchar']
    assert_equal '', row['col_clob']
  end

  def test_row2_negative_reals
    row = select_row(2)
    assert_in_delta(-3.14,        row['col_real'].to_f,  1e-10)
    assert_in_delta(-0.001,       row['col_double'].to_f, 1e-10)
    assert_in_delta(-1.23456789,  row['col_double_precision'].to_f, 1e-10)
    # col_float = 0.0 (stored as integer 0 by SQLite optimizer)
    assert_in_delta 0.0,          row['col_float'].to_f, 1e-10
  end

  def test_row2_zero_boolean
    row = select_row(2)
    assert_equal 0, row['col_boolean']
  end

  # -- Row 3: all NULLs --

  def test_row3_all_null
    row = select_row(3)
    # Every column except id should be nil
    row.each do |col, val|
      next if col == 'id'
      assert_nil val, "Expected NULL for #{col}"
    end
  end

  # -- Row 4: integer boundary values (serial types 1-6) --

  def test_row4_int_boundaries
    row = select_row(4)
    assert_equal 127,                   row['col_integer']   # max 1-byte signed
    assert_equal(-128,                  row['col_int'])       # min 1-byte signed
    assert_equal 32_767,                row['col_tinyint']    # max 2-byte signed
    assert_equal(-32_768,               row['col_smallint'])  # min 2-byte signed
    assert_equal 8_388_607,             row['col_mediumint']  # max 3-byte signed
    assert_equal(-8_388_608,            row['col_bigint'])    # min 3-byte signed
    assert_equal 2_147_483_647,         row['col_unsigned_big_int']  # max 4-byte signed
    assert_equal(-2_147_483_648,        row['col_int2'])      # min 4-byte signed
    assert_equal 140_737_488_355_327,   row['col_int4']       # max 6-byte signed
    assert_equal(-140_737_488_355_328,  row['col_int8'])      # min 6-byte signed
  end

  def test_row4_extreme_reals
    row = select_row(4)
    assert_in_delta 1.7976931348623157e+308,  row['col_real'].to_f,  1e+294
    assert_in_delta(-1.7976931348623157e+308, row['col_double'].to_f, 1e+294)
    assert_in_delta 2.2250738585072014e-308,  row['col_double_precision'].to_f, 1e-320
  end

  def test_row4_blob_single_byte
    row = select_row(4)
    assert_equal "\xFF".b, row['col_blob'].b
  end

  def test_row4_blob_multi_byte
    row = select_row(4)
    assert_equal "\x01\x02\x03\x04\x05\x06\x07\x08".b, row['col_no_type'].b
  end

  # -- Row 5: max 64-bit integers, large text --

  def test_row5_max_int64
    row = select_row(5)
    assert_equal 9_223_372_036_854_775_807,  row['col_integer']   # max int64
    assert_equal(-9_223_372_036_854_775_808, row['col_int'])       # min int64
  end

  def test_row5_long_text
    row = select_row(5)
    expected = 'The quick brown fox jumps over the lazy dog. This is a longer text value to test text storage.'
    assert_equal expected, row['col_text']
  end

  def test_row5_large_blob
    row = select_row(5)
    expected = (0x00..0x1F).map(&:chr).join.b
    assert_equal expected, row['col_blob'].b
  end

  def test_row5_cafebabe_blob
    row = select_row(5)
    assert_equal "\xCA\xFE\xBA\xBE".b, row['col_no_type'].b
  end

  def test_row5_zero_reals
    row = select_row(5)
    # SQLite stores 0.0 as integer 0 (serial type 8) for space efficiency
    # Both C and Ruby return value 0 at the storage level
    assert_in_delta 0.0, row['col_real'].to_f,  1e-10
    assert_in_delta 0.0, row['col_double'].to_f, 1e-10
    assert_in_delta 0.0, row['col_double_precision'].to_f, 1e-10
    assert_in_delta 0.0, row['col_float'].to_f, 1e-10
  end

  private

  def select_row(id)
    rows = @db.execute('SELECT * FROM all_types')
    rows.find { |r| r['id'] == id }
  end
end
