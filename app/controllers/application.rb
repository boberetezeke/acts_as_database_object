# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
	before_filter :setup_command_history, :setup_remote_object_worker, :setup_context

	def setup_context
		if session[:context] then
			@context_tags = ObjectDatabaseTag.find(*session[:context])
		else
			@context_tags = []
		end
		@all_tags = ObjectDatabaseTag.find(:all).map{|x| x.name}.sort
	end

	def setup_command_history
puts "setup_command_history"
		commands = ObjectDatabaseEnteredCommand.find(:all, :order => "id desc", :limit => 100).map{|x| x.command}.reverse
		@command_history = "[" + commands.map{|x| "'" + escape_quotes(x) + "'"}.join(",\n") + "]"
	end

	def setup_remote_object_worker
		if session[:remote_object_worker_key] then
			remote_object_worker = MiddleMan.get_worker(session[:remote_object_worker_key])
		end
		$TRACE.debug 5, "1: session key = #{session[:remote_object_worker_key]}, remote object worker = #{remote_object_worker}"
		# if we weren't able to get a remote_object_worker either because it has never been saved
		# in the session or the background drb has been restarted
		unless remote_object_worker
			remote_object_worker = MiddleMan.new_worker(:class => "remote_object_worker") 
			session[:remote_object_worker_key] = remote_object_worker
		end
		$TRACE.debug 5, "2: session key = #{session[:remote_object_worker_key]}, remote object worker = #{remote_object_worker}"

		ObjectDatabaseFindOptions.instance.remote_object_finder = remote_object_worker
	end

	private

	def escape_quotes(str)
		#puts "s-before = #{str.x}"
		s = str.gsub(/(.)/m) { "%2.2x" % $1[0] }
		#puts "s = '#{s}'"
		return s
		#str.gsub(/([^\\])("')/, "$1\\$2").gsub(/\r\n/, ';')
	end
end
