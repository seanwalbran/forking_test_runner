if ENV["COVERAGE"]
  require 'coverage'
  Coverage.start
  puts 'START'
  ForkingTestRunner.restore_coverage = true
  require_relative 'preloaded'
  PreloadedCoverage.generate_coverage
end

require_relative "../setup_test_model"
require_relative "../test/no_ar_helper"
