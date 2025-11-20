require "test_helper"
require "rake"

class Wc3statsRakeTest < ActiveSupport::TestCase
  setup do
    # Load rake tasks
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  teardown do
    # Clear rake tasks to allow re-invocation
    Rake::Task["wc3stats:import"]&.reenable
    Rake::Task["wc3stats:import_recent"]&.reenable
    Rake::Task["wc3stats:stats"]&.reenable
  end

  test "wc3stats:import task exists" do
    assert Rake::Task.task_defined?("wc3stats:import"), "wc3stats:import task should exist"
  end

  test "wc3stats:import_recent task exists" do
    assert Rake::Task.task_defined?("wc3stats:import_recent"), "wc3stats:import_recent task should exist"
  end

  test "wc3stats:stats task exists" do
    assert Rake::Task.task_defined?("wc3stats:stats"), "wc3stats:stats task should exist"
  end

  test "import task is properly defined" do
    task = Rake::Task["wc3stats:import"]
    assert_not_nil task
    assert_equal "wc3stats:import", task.name
  end

  test "import_recent task is properly defined" do
    task = Rake::Task["wc3stats:import_recent"]
    assert_not_nil task
    assert_equal "wc3stats:import_recent", task.name
  end

  test "stats task is properly defined" do
    task = Rake::Task["wc3stats:stats"]
    assert_not_nil task
    assert_equal "wc3stats:stats", task.name
  end
end
