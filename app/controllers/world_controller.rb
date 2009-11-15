

class WorldController < ApplicationController
	helper :object_database_model_superclass

=begin
   def start
		session[:sync_job_key] = MiddleMan.new_worker(:class => "sync_worker")
		MiddleMan.get_worker(session[:sync_job_key]).start_sync
		
   	redirect_to :action => "status"
   end

   def status
		status_str = MiddleMan.get_worker(session[:sync_job_key]).status
		render :text => status_str
   end
=end

	def force_reload
		ActionController::Dispatcher.force_application_cleanup
		redirect_to :action => "main"
	end

	def main
		@model_params = {}
		@model_params[:title] = "Main"
		#redirect_to :action => "show_changes"
	end

	def design
		case params["type"]
		when /^model$/
			@object_model = ObjectDatabaseModel.find(params["id"])
			@object_model_controller = "object_database_model"
		when /^data_store$/
			@object_model = ObjectDatabaseDataStore.find(params["id"])
			@object_model_controller = "object_database_data_store"
		else
			# redirect to error
		end
		@object_controller = ObjectDatabaseController.find(:first, :conditions => ["name = ?", @object_model.name])
		@object_helper = ObjectDatabaseHelper.find(:first, :conditions => ["name = ?", @object_model.name])
		@object_views = ObjectDatabaseView.find(:all, :conditions => ["controller = ?", @object_model.name])
		@model_params = {:title => "#{@object_model.name} Design"}
	end

	def create_view
		ObjectDatabaseView.new(:controller => params["model"]["controller"], :name => params["model"]["view"]).save
		redirect_to :action => "design", :id => params["model"]["id"]
	end
	
	def command
		@model_params = {}
		@model_params[:title] = "Command Prompt"
		@commands = Command.find(:all, :order => "when_created DESC")
	end

	def evaluate_command
		str_result = nil

		command_str = params["command"]
		$TRACE.debug 5, "evaluate_command: #{command_str}"
		matching_handlers = matching_handlers_for_command_str(command_str)
		ObjectDatabaseEnteredCommand.new(:command => command_str).save

		$TRACE.debug 5, "evaluate_command: matching_handlers = #{matching_handlers.inspect}"
		
		if matching_handlers.size == 1 then
			command_handler = matching_handlers.first
			command_handler_class = (command_handler.name + "Handler").constantize
			$TRACE.debug 5, "evaluate_command: command_handler_class = #{command_handler_class}"
			command_handler_instance = command_handler_class.new(self)
			$TRACE.debug 5, "evaluate_command: command_handler_instance = #{command_handler_instance.inspect}"
			partial_command_str = /^#{Regexp.escape(command_handler.prefix)}(.*)$/.match(command_str)[1]
			$TRACE.debug 5, "evaluate_command: partial_command_str = '#{partial_command_str}'"
			command_handler_instance.handle_command(partial_command_str)
		else
			if matching_handlers.empty? then
				flash[:error] = "no command handler matched"
			else
				flash[:error] = "more than one command handler matched from prefixes: [#{matching_handlers.map{|x| x.prefix}.join(',')}]"
			end
			redirect_to({:controller => params["view_controller"], :action => params["view_action"], :id => params["view_id"]})
		end

=begin
		case command			
		when /^\?(.*)$/
			search_string = $1
			
			if /^\?(.*)$/.match(search_string) then
				session[:search_job_key] = MiddleMan.new_worker(:class => "search_worker")
				search_id = MiddleMan.get_worker(session[:search_job_key]).search_all(search_string)
				redirect_to :controller => "object_search", :action => "show", :id => search_id
			else
				redirect_to({:controller => params["view_controller"], :action => params["view_action"], :id => params["view_id"]}.merge(params["view_params"]).merge({:filter_string => search_string}))
			end			
		else
			# nothing to do for now
			command_id = MiddleMan.get_worker(session[:command_job_key]).evaluate(command)
			redirect_to :controller => "command", :action => "show", :id => command_id
		end
=end

=begin
		command = params["command"]
		str_result = nil
		begin
			$evaluator.evaluate(command)
		rescue Exception => e
			str_result = e.message
		end
		unless str_result
			begin
				str_result = InspectParser.new($evaluator.result.inspect, WorldHelper::ActiveRecordProxyConstructor.new).parse.inspect
			rescue Exception => e
				str_result = "ERROR: #{e.message} when parsing inspect of '#{$evaluator.result.inspect}'"
			end
		end

		#str_result = $evaluator.result.inspect unless str_result
		Command.new(:command => params["command"], :when_created => Time.now, :result => str_result, :output => $evaluator.output).save
		redirect_to :action => "command"
=end
	end

	def show_changes
		# Time.local(1980,"jan", 1,1,1,1)
		limit = (params["limit"] || 100).to_i
		@max_entries_per_bucket = (params["max_entries_per_bucket"] || 30).to_i
		
		@model_params = {}
		@model_params[:title] = "Show all changes"
		#@object_changes = ObjectChange.find(:all, :order => "created_datetime DESC", :include => :member_changes, :limit => limit)
		@object_changes = ObjectChanges.changes_since(Time.local(2000,1,1), :order => "created_datetime DESC", :limit => limit)

		changes = @object_changes.to_combined_changes

		@time_buckets = {}
		changes.each do |change_type, change_time, change|
			time_bucket = time_without_mins_and_secs(change_time)
			@time_buckets[time_bucket] ||= []
			@time_buckets[time_bucket].push([change_type, change_time, change])
		end
		# make sure that all time buckets display in reverse chronological order
		@time_buckets.each_key {|key| @time_buckets[key].reverse!}
	end

	def write_rails_files
		@model_params = {}
		@model_params[:title] = "Write Rails Files"
		@files = ObjectDatabaseSourceCode.find(:all, :use_original => true)
		@files.each {|f| f.save}
	end

private
	def time_without_mins_and_secs(time)
		Time.local(time.year, time.month, time.day, time.hour)
	end

	def matching_handlers_for_command_str(command_str)
		command_handlers = ObjectDatabaseCommandHandler.find(:all) #, :select => "id, prefix")
		$TRACE.debug 5, "matching_handlers_for_command_str: command_handlers found = #{command_handlers.inspect}"
		matching_handlers = command_handlers.select { |ch|/^#{Regexp.escape(ch.prefix)}/.match(command_str) }
		$TRACE.debug 5, "matching_handlers_for_command_str: matching_handlers found = #{matching_handlers.inspect}"
		longest_matching_handlers = matching_handlers.inject([]) do|longest_matches, matching_handler| 
			if longest_matches.empty? then
				[matching_handler]	# start the longest_matches list with this one
			else
				# if this handler is longer than the entries in the list
				if matching_handler.prefix.size > longest_matches.first.prefix.size then
					[matching_handler]	# replace the list with this one
				# if this handler is equal or shorter than the entries in the list
				else
					# if this handler is equal to the entries in the list
					if matching_handler.prefix.size == longest_matches.prefix.first.size then
						longest_matches + [matching_handler]	# add this to the list
					else
						longest_matches								# leave the list as it is
					end
				end
			end
		end

		$TRACE.debug 5, "matching_handlers_for_command_str: longest_matching_handlers = #{longest_matching_handlers.inspect}"
		return longest_matching_handlers
	end
end
