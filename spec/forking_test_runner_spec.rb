require "spec_helper"
require "tempfile"

describe ForkingTestRunner do
  let(:root) { File.expand_path("../../", __FILE__) }

  def runner(command, options={})
    sh("bundle exec #{root}/bin/forking-test-runner #{command}", options)
  end

  def sh(command, options={})
    gemfile = ENV["BUNDLE_GEMFILE"]
    result = Bundler.with_clean_env do
      ENV["BUNDLE_GEMFILE"] = gemfile
      `#{command} #{"2>&1" unless options[:keep_output]}`
    end
    raise "#{options[:fail] ? "SUCCESS" : "FAIL"} #{command}\n#{result}" if $?.success? == !!options[:fail]
    result
  end

  def with_env(hash)
    env = Bundler::ORIGINAL_ENV
    old = {}
    hash.each { |k,v| old[k], env[k] = env[k], v }
    yield
  ensure
    old.each { |k,v| env[k] = v }
  end

  def assert_correct_runtime(result)
    result.gsub!(/:[\d\.]+/, "")
    result.split("\n").sort.should == [
      "test/another_test.rb",
      "test/no_ar_test.rb",
      "test/pollution_test.rb",
      "test/simple_test.rb"
    ]
  end

  def restoring(file)
    content = File.read(file)
    yield
  ensure
    File.write(file, content)
  end

  around do |test|
    Dir.chdir File.expand_path("../dummy", __FILE__), &test
  end

  it "has a VERSION" do
    ForkingTestRunner::VERSION.should =~ /^[\.\da-z]+$/
  end

  it "runs tests without pollution" do
    result = runner("test")
    result.should include "simple_test.rb"
    result.should include "pollution_test.rb"
    result.should include "9 assertions, 0 errors, 0 failures"
    result.should_not include "0 tests " # minitest was not disabled
    result.should_not include "Time:" # no runtime log -> no time info
  end

  it "fails when a test fails" do
    with_env "FAIL_NOW" => "1" do
      result = runner("test", fail: true)
      result.should include "simple_test.rb ---- OK"
      result.should include "pollution_test.rb ---- Fail"
    end
  end

  it "keeps unrelated args for the test runner" do
    result = runner("test -v")
    result.should include "SimpleTest#test_transaction_0 ="
  end

  it "switches program name so rerun scripts can use the file name" do
    result = runner("test/show_program_name.rb")
    result.should include "PROGRAM IS test/show_program_name.rb YEAH"
  end

  # this test needs internet access
  it "records runtime" do
    with_env "TRAVIS_REPO_SLUG" => "test-slug", "TRAVIS_BUILD_NUMBER" => "build#{rand(999999)}" do
      result = runner("test --record-runtime amend")
      url = result[/curl \S+/] || raise("no command found")
      result = sh "curl --silent #{url}"
      assert_correct_runtime(result)
    end
  end

  it "records simple runtime to disc" do
    restoring "runtime.log" do
      runner("test --record-runtime simple")
      result = File.read("runtime.log")
      assert_correct_runtime(result)
    end
  end

  it "uses recorded runtime" do
    result = runner("test --group 1 --groups 2 --runtime-log runtime.log")
    result.should include "Running tests test/another_test.rb\n" # only runs the 1 big test
    result.should include "Time: expected 1.0, actual 0." # per test time info
    result.should include "diff to expected" # global summary
  end

  it "can run without activerecord" do
    result = runner("test/no_ar_test.rb --helper test/no_ar_helper.rb")
    result.should =~ /1 tests, 1 assertions|1 runs, 1 assertions/
    result.should include "AR IS UNDEFINED"
  end

  it "can keep coverage across forks" do
    result = with_env "COVERAGE" => "1" do
      runner("test/coverage.rb")
    end
    result.should include "preloaded: [1,1,1,1]"
  end

  describe "quiet mode" do
    it "does not print test output" do
      result = runner("test --quiet")
      result.should include ">>>"
      result.should_not include "Finished"
      result.should_not include "<<<"
    end

    it "prints failures" do
      with_env "FAIL_NOW" => "1" do
        result = runner("test --quiet", fail: true)
        result.should include ">>>"
        result.should include "Finished"
        result.should include "<<<"
      end
    end
  end

  describe "rspec" do
    it "can run passing tests" do
      runner("spec/passing --rspec").should include "1 example, 0 failures"
    end

    it "returns a successful status code on passing tests" do
      runner("spec/passing --rspec")
    end

    it "can run failing tests" do
      runner("spec/failing --rspec", { fail: true }).should include "1 example, 1 failure"
    end

    it "runs with arguments" do
      runner("spec/passing --rspec --seed 12345").should include "Randomized with seed 12345"
    end

    it "runs with and groups" do
      runner("spec/passing --rspec --group 1 --groups 1 --seed 12345").should include "Randomized with seed 12345"
    end

    context 'when emitting debug' do
      context 'without --quiet' do
        let(:output_with_debug) { runner("spec/emitting --rspec") }

        it { output_with_debug.should include('Warning: Code Under Test') }
      end

      context 'with --quiet' do
        let(:output_with_debug) { runner("spec/emitting --rspec --quiet") }

        it { output_with_debug.should include('Warning: Code Under Test') }
      end
    end
  end
end
