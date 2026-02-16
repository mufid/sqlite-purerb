# sqlite-purerb

A pure Ruby implementation of the SQLite database file format and SQL query engine. This library can read SQLite 3.x database files and execute SQL queries without any C extensions or FFI bindings.

The status is experimental project.

## Usage

### CLI

An interactive REPL is available at `bin/sqlite-purerb`. It works like the C `sqlite3` shell:

```sh
# Interactive mode
bin/sqlite-purerb path/to/database.sqlite3
sqlite-purerb> .headers on
sqlite-purerb> SELECT * FROM my_table LIMIT 5;

# Piped mode
echo "SELECT * FROM my_table;" | bin/sqlite-purerb path/to/database.sqlite3
```

Supported dot-commands: `.headers on|off`, `.mode list`, `.separator <sep>`, `.quit`, `.exit`.

### REPL (from Ruby code)

`SqlitePurerb::REPL` processes batch SQL input and produces formatted output, matching the C sqlite3 shell's behavior:

```ruby
require 'sqlite_purerb'

repl = SqlitePurerb::REPL.new('path/to/database.sqlite3')

output = repl.process(<<~SQL)
  .headers on
  SELECT * FROM my_table LIMIT 5;
SQL
puts output

repl.close
```

### Direct API

Use `SqlitePurerb::Database` for programmatic access. Queries return an array of hashes keyed by column name:

```ruby
require 'sqlite_purerb'

db = SqlitePurerb::Database.new('path/to/database.sqlite3')

# Execute a query
rows = db.execute('SELECT id, name FROM users')
rows.each { |row| puts row.inspect }
# => {"id"=>1, "name"=>"Alice"}
# => {"id"=>2, "name"=>"Bob"}

# List tables
puts db.tables

# Show EXPLAIN bytecode for a query
puts db.explain('SELECT * FROM users')

db.close
```

## Building

Development and testing require two sibling directories next to `sqlite-purerb`:

```
parent/
├── sqlite-c/       # SQLite C source (obtained via Fossil)
├── sqlite-purerb/  # This project
└── tcl-tk/         # Tcl source code + local install
```

The C sqlite3 binary is used as a reference implementation to validate test output. Tcl is required because SQLite's test suite is written in Tcl, and the C build system depends on it.

### Prerequisites

- A C compiler (gcc or clang)
- make
- Ruby >= 3.0 with Bundler
- [Fossil](https://fossil-scm.org/) version control — refer to the [Fossil download page](https://fossil-scm.org/home/uv/download.html) for installation instructions

### Step 1: Build Tcl from source

SQLite's build system requires a Tcl installation. We build Tcl from source into a local prefix rather than using a system package.

```sh
# From the parent directory
mkdir -p tcl-tk && cd tcl-tk

# Download Tcl source
curl -L -o tcl8.6.17-src.tar.gz https://sourceforge.net/projects/tcl/files/Tcl/8.6.17/tcl8.6.17-src.tar.gz/download
tar xzf tcl8.6.17-src.tar.gz

# Build and install to a local prefix
cd tcl8.6.17/unix
./configure --prefix="$(cd ../.. && pwd)/install"
make
make install
cd ../../..
```

After this, `tcl-tk/install/bin/tclsh8.6` should exist.

### Step 2: Clone and build SQLite from source

SQLite uses [Fossil](https://fossil-scm.org/) for version control. The source repository is at <https://sqlite.org/src>.

```sh
# From the parent directory
mkdir sqlite-c && cd sqlite-c
fossil clone https://sqlite.org/src src.fossil
fossil open src.fossil

# Build in a separate bld/ directory
mkdir -p bld && cd bld
../configure \
  --with-tcl="$(cd ../../tcl-tk/install/lib && pwd)" \
  --with-tclsh="$(cd ../../tcl-tk/install/bin && pwd)/tclsh8.6"
make sqlite3
cd ../..
```

After this, `sqlite-c/bld/sqlite3` should exist.

### Step 3: Set up sqlite-purerb

```sh
cd sqlite-purerb
bundle install
```

### Running tests

```sh
cd sqlite-purerb

# Generate test fixtures from SQLite's Tcl test suite.
# This extracts SQL inputs and expected outputs from sqlite-c/test/ into test-c/.
rake test_c_generate

# Run extracted tests against the C sqlite3 binary (validates the extraction).
rake test_c_c

# Run extracted tests against the Ruby implementation.
rake test_c_rb FAILFAST=yes

# Filter to a single test file.
rake test_c_rb TESTNAME=affinity2 FAILFAST=yes

# Run unit tests.
rake test
```

## Installation

```ruby
gem 'sqlite-purerb'
```

## License

MIT
