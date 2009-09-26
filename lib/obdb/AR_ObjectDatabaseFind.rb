require "singleton"

class ObjectDatabaseFindOptions
	include Singleton

	attr_accessor :remote_object_finder
	def initialize
		remote_object_finder = nil
	end
end

# new line
module ObjectDatabaseFind
	def findx(find_method, options={})
		table_name = self.table_name
		#$TRACE.debug 5, "findx(before): find_method=#{find_method}, options=#{options.inspect}"
		find_method, options = last_store_object_find_mod(find_method, table_name, options)
		#$TRACE.debug 5, "findx(after-last_store_object_find_mod): find_method=#{find_method}, options=#{options.inspect}"
		find_method, options = deleted_objects_find_mod(find_method, table_name, options)
		#$TRACE.debug 5, "findx(after-deleted_objects_find_mod): find_method=#{find_method}, options=#{options.inspect}"
		if $USE_FIND then
			[find_method, options]
		else
			find(find_method, options)
		end
	end

	if $USE_FIND then
	def find(*args)
		#$TRACE.debug 5, "find: #{args.inspect}"
		options = args.last.is_a?(Hash) ? args.pop : {}
		use_original = options.delete(:use_original)
		remote_object_finder = ObjectDatabaseFindOptions.instance.remote_object_finder
		
		if args.first == :all || args.first == :first then
			find_method = args.shift
			if use_original then
				#$TRACE.debug 5, "find: use_original: #{options.inspect}"
				super(find_method, options)
			else
				#$TRACE.debug 5, "find: modified: #{options.inspect}"
				args = findx(find_method, options)
				#$TRACE.debug 5, "find: modified2: #{options.inspect}, #{args.inspect}"
				super(*args)
			end
		else
			#$TRACE.debug 5, "find with ids #{args.inspect}"
			args += [options]
			if args[0].kind_of?(String) && /^0x(\w+)$/.match(args[0]) then
				#$TRACE.debug 5, "remote_object_finder = #{remote_object_finder.inspect}"
				ret = remote_object_finder.find(*args)
			else
				ret = super(*args)
			end
			#$TRACE.debug 5, "find: ret = #{ret.inspect}"
			ret
		end
	end
	end
	
=begin
	def find(*args)
			puts "-- calling super with #{args.inspect}, class = #{self.class}, super class = #{self.superclass}"
#set_trace_func proc { |event, file, line, id, binding, classname|
#	printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
#}
		ret = nil
		begin
			ret = super(args) #, options)
		rescue Exception => e
			puts "-- exception: #{e.message}"
			raise
		end
			#ret = []
			puts "-- ret = #{ret.class}"
		return	ret

puts "find called: #{args.inspect}"
		options = args.last.is_a?(Hash) ? args.pop : {}

		if args.first == :all || args.first == :first then
			find_method = args.shift
			if options[:use_original] then
				super(find_method, options.delete(:use_original))
			else
				super(findx(find_method, options))
			end
		else
			puts "calling super with #{args.inspect}"
			ret = super(args) #, options)
			puts "ret = #{ret.class}"
			ret
		end
	end
=end
end
