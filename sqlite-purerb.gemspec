lib = File.expand_path('./lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sqlite_purerb/version'

Gem::Specification.new do |spec|
  spec.name          = 'sqlite-purerb'
  spec.version       = SqlitePurerb::VERSION
  spec.authors       = ['Muhammad Mufid Afif']
  spec.email         = ['mufidafif@icloud.com']

  spec.summary       = 'Pure Ruby implementation of SQLite database engine'
  spec.description   = 'A pure Ruby implementation of SQLite file format reader and SQL query engine. No C extensions, no FFI, just Ruby.'
  spec.homepage      = 'https://github.com/mufid/sqlite-purerb'
  spec.licenses      = ['MIT']

  spec.files         = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.0'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rake', '~> 13.0'
end
