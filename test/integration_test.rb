# frozen_string_literal: true

require 'test_helper'

class IntegrationTest < Minitest::Test
  DATABASE_PATH = File.expand_path('../../development.sqlite3', __dir__)

  def setup
    skip "Database file not found: #{DATABASE_PATH}" unless File.exist?(DATABASE_PATH)
    @db = SqlitePurerb::Database.new(DATABASE_PATH)
  end

  def teardown
    @db&.close
  end

  def test_can_open_database
    assert_instance_of SqlitePurerb::Database, @db
  end

  def test_can_read_page_size
    # SQLite default page size is typically 4096
    assert @db.pager.page_size >= 512
    assert @db.pager.page_size <= 65536
  end

  def test_can_list_tables
    tables = @db.tables
    assert_includes tables, 'clients'
  end

  def test_select_all_from_clients
    rows = @db.execute('SELECT * FROM clients')

    assert_kind_of Array, rows
    assert rows.length >= 1, "Expected at least one client row"

    # Check that we have expected columns
    first_row = rows.first
    assert_kind_of Hash, first_row

    # Based on the schema, we expect these columns
    expected_columns = %w[id name phone email created_at updated_at xero_contact_id]
    expected_columns.each do |col|
      assert first_row.key?(col), "Expected column '#{col}' in result"
    end
  end

  def test_select_all_returns_expected_data
    rows = @db.execute('SELECT * FROM clients')

    # Find Jon Snow
    jon = rows.find { |r| r['name'] == 'Jon Snow' }
    assert jon, "Expected to find Jon Snow in clients"
    assert_equal 'jon@snow.com', jon['email']
    assert_equal '+6512321232', jon['phone']

    # Find Arya Stark
    arya = rows.find { |r| r['name'] == 'Arya Stark' }
    assert arya, "Expected to find Arya Stark in clients"
    assert_equal 'arya@stark.com', arya['email']
  end

  def test_select_all_returns_six_clients
    rows = @db.execute('SELECT * FROM clients')

    # Based on the C SQLite output, there are 6 clients
    assert_equal 6, rows.length

    names = rows.map { |r| r['name'] }
    assert_includes names, 'Jon Snow'
    assert_includes names, 'Arya Stark'
    assert_includes names, 'Sansa Stark'
    assert_includes names, 'Robb Stark'
    assert_includes names, 'Robert Baratheon'
    assert_includes names, 'Danny Targaryen'
  end

  def test_execute_with_semicolon
    rows = @db.execute('SELECT * FROM clients;')
    assert_equal 6, rows.length
  end

  def test_execute_case_insensitive
    rows = @db.execute('select * from CLIENTS')
    assert_equal 6, rows.length
  end

  def test_table_not_found_raises_error
    assert_raises(RuntimeError) do
      @db.execute('SELECT * FROM nonexistent_table')
    end
  end

  # WHERE clause tests
  def test_where_equals_string
    rows = @db.execute("SELECT * FROM clients WHERE name = 'Jon Snow'")
    assert_equal 1, rows.length
    assert_equal 'Jon Snow', rows.first['name']
    assert_equal 'jon@snow.com', rows.first['email']
  end

  def test_where_equals_integer
    rows = @db.execute('SELECT * FROM clients WHERE id = 1')
    assert_equal 1, rows.length
    assert_equal 1, rows.first['id']
  end

  def test_where_no_match
    rows = @db.execute("SELECT * FROM clients WHERE name = 'Nobody'")
    assert_equal 0, rows.length
  end

  def test_where_and
    rows = @db.execute("SELECT * FROM clients WHERE name = 'Jon Snow' AND id = 1")
    assert_equal 1, rows.length
    assert_equal 'Jon Snow', rows.first['name']
  end

  def test_where_or
    rows = @db.execute("SELECT * FROM clients WHERE name = 'Jon Snow' OR name = 'Arya Stark'")
    assert_equal 2, rows.length
    names = rows.map { |r| r['name'] }
    assert_includes names, 'Jon Snow'
    assert_includes names, 'Arya Stark'
  end

  # Column selection tests
  def test_select_specific_columns
    rows = @db.execute('SELECT name, email FROM clients')
    assert_equal 6, rows.length

    first_row = rows.first
    assert first_row.key?('name')
    assert first_row.key?('email')
    refute first_row.key?('phone'), "Should not include unselected columns"
    refute first_row.key?('id'), "Should not include unselected columns"
  end

  def test_select_with_alias
    rows = @db.execute('SELECT name AS client_name FROM clients')
    assert_equal 6, rows.length

    first_row = rows.first
    assert first_row.key?('client_name'), "Expected aliased column name"
    refute first_row.key?('name'), "Original column name should not appear"
  end

  def test_select_with_alias_no_as_keyword
    rows = @db.execute('SELECT name n FROM clients')
    assert_equal 6, rows.length

    first_row = rows.first
    assert first_row.key?('n'), "Expected aliased column name 'n'"
    refute first_row.key?('name'), "Original column name should not appear"
  end

  # Combined WHERE and alias test - the main user requirement
  def test_select_with_alias_and_where_using_alias
    # This is the key test: SELECT name n FROM clients WHERE n='Jon Snow'
    # The WHERE clause uses the alias 'n' to refer to the 'name' column
    rows = @db.execute("SELECT name n FROM clients WHERE n = 'Jon Snow'")

    assert_equal 1, rows.length
    assert_equal 'Jon Snow', rows.first['n']
  end

  def test_select_multiple_columns_with_aliases_and_where
    rows = @db.execute("SELECT name n, email e FROM clients WHERE n = 'Arya Stark'")

    assert_equal 1, rows.length
    assert_equal 'Arya Stark', rows.first['n']
    assert_equal 'arya@stark.com', rows.first['e']
  end

  def test_comparison_operators
    # Greater than
    rows = @db.execute('SELECT * FROM clients WHERE id > 3')
    assert rows.length >= 1
    rows.each { |r| assert r['id'] > 3 }

    # Less than
    rows = @db.execute('SELECT * FROM clients WHERE id < 3')
    assert rows.length >= 1
    rows.each { |r| assert r['id'] < 3 }
  end
end
