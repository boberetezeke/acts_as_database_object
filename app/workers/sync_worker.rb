# Put your code that runs your task inside the do_work method
# it will be run automatically in a thread. You have access to
# all of your rails models if you set load_rails to true in the
# config file. You also get @logger inside of this class by default.

require "pp"
class TestClass
	attr_reader :test_name

	def initialize(name)
		@test_name = name
	end
end

=begin
class CsvStore < DataStore
	def do_something
		@objs = []
		@objs.push(Widget.find(1))
	end
end
=end

class SyncWorker < BackgrounDRb::Rails
	attr_reader :synchronizer
	attr_reader :test1,:test2

	def do_work(args)
		# This method is called in it's own new thread when you
		# call new worker. args is set to :args
		#@od = ObjectDatabase.new("#{RAILS_ROOT}/db", true, "#{RAILS_ROOT}/app/models")
		@status = ""
		#if !$od then
		#	$od = ObjectDatabase.new("#{RAILS_ROOT}/db", true, "#{RAILS_ROOT}/app/models", "mysql", "localhost", "root", "greplock", "odrails3")
		#end
	end

	SYNC_TYPE_HASH = {
		"import" => ObjectDatabase::Synchronizer::IMPORT_ONLY,
		"export" => ObjectDatabase::Synchronizer::EXPORT_ONLY,
		"sync" => ObjectDatabase::Synchronizer::SYNC
	}
	
	def start_sync(store_id, start_sync_only)
ActionController::Dispatcher.force_application_cleanup
		store = DataStore.find(store_id)
		puts "store = #{store.inspect}"
		@synchronizer = ObjectDatabase::Synchronizer.new(store, Query.new, ObjectDatabase.instance)
		@test1 = "test1_value"
		@test2 = TestClass.new(store)
		pp @test2

		
		@synchronizer.sync_in_thread(start_sync_only, SYNC_TYPE_HASH[store.sync_type])
		#store.get_objects(nil, nil, nil)
		#store.do_something
		#pp @test2
		puts "after thread start"
	end

	def stop_sync
		@synchronizer.status.abort
	end

	def status
		@synchronizer.status
	end

	def local_changes
puts "before getting local changes from #{@synchronizer.class}"
		combined_changes = @synchronizer.local_changes.to_combined_changes
		combined_changes.extend(DRbUndumped)
puts "after getting local changes, class = #{combined_changes.class}, size = #{combined_changes.size}"
		#ret.extend(DRbUndumped)
		combined_changes
	end

	def remote_changes
puts "before getting remote changes from #{@synchronizer.class}"
		combined_changes = @synchronizer.remote_changes.to_combined_changes
		combined_changes.extend(DRbUndumped)
puts "after getting remote changes, class = #{combined_changes.class}, size = #{combined_changes.size}"
		#ret.extend(DRbUndumped)
		combined_changes
	end

=begin
		Thread.new do
			100.times do |i|
				@status += "added line #{i}<br>"
				sleep 1
				puts "in start_sync, i = #{i}"
			end
		end
=end
end
