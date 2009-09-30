# Include hook code here
puts "in init.rb ****************************** #{directory}"

Dependencies.load_paths << "c:/projects/ruby_world/app/command_handlers"
$LOAD_PATH << "c:/projects/ruby_world/app/command_handlers"

$LOAD_PATH << File.join(directory, "lib")

%w{ models controllers helpers views workers }.each do |dir|
  path = File.join(directory, 'app', dir)
  $LOAD_PATH << path
  Dependencies.load_paths << path
  Dependencies.load_once_paths.delete(path)
end

# third party libraries
require "acts_as_ferret"

# local requires
require "acts_as_database_object"
require "command_handler"
require "obdb/AR_ObjectDatabase"
require "difffile/DiffChange"
require "obdb/AR_BigString"

DiffChange.set_temp_dir "#{RAILS_ROOT}/db"
BigString.set_temp_dir "#{RAILS_ROOT}/db"
BigString.set_max_length_in_memory(4096)

class ActiveRecord::Base
	def inspect(*args, &block)
		super
	end
end


ObjectDatabase.new("#{RAILS_ROOT}/db", false, "#{RAILS_ROOT}/app/models", "mysql")

ActionController::Base.perform_caching = true

$source_code_has_changed = true

module ::ActionController
	# Dispatches requests to the appropriate controller and takes care of
 	# reloading the app after each request when Dependencies.load? is true.
  	class Dispatcher
  		alias :old_reload_application :reload_application
  		alias :old_cleanup_application :cleanup_application
  		alias :old_initialize :initialize

		class << self
			attr_reader :do_reload_application, :do_cleanup_application
			
			def load_application_initialize
				unless @do_load_initialized
		  			@do_reload_application = true
  					@do_cleanup_application = false
  					
  					@do_load_initialized = true
  				end
  			end
  			
	 		def force_application_cleanup
	 			$TRACE.debug 5, "force_application_cleanup"
 				@do_cleanup_application = true
 			end

 			def after_cleanup_application
 				@do_reload_application = @do_cleanup_application
 				@do_cleanup_application = false
 			end
 		end

  		def initialize(*args, &block)
  			self.class.load_application_initialize
  			old_initialize(*args, &block)
  		end
  		
 		def reload_application 			
 			$TRACE.debug 5,  "in reload_application"
 			if self.class.do_reload_application then
	 			old_reload_application 
				ObjectDatabaseTag		# KLUDGE: force this to be evaluated to initialize tagging behavior
	 			$TRACE.debug 5,  "after old reload"
	 		end
 		end

 		def cleanup_application
 			$TRACE.debug 5,  "in cleanup_application"
 			if self.class.do_cleanup_application then
	 			old_cleanup_application 
	 			$from_models = nil	# KLUDGE: clear out global for ObjectDatabaseTag
	 			$TRACE.debug 5,  "after old cleanup"
			end
			self.class.after_cleanup_application
 		end

 	end
 end

require 'tagging_extensions'
ObjectDatabaseTag		# force this to be evaluated to initialize tagging behavior

