require "md5"
require "ftools"
require "PersistentTempFile"
require "my/mysystem"
require "tempfile"
require "difffile/DiffChange"

class BigString
	@@max_length_in_memory = 255
	
	class << self
		def from_s(str)
			return BigString.new(str)
		end

		def from_val(val)
			val.to_s
		end

		def set_temp_dir(dir)
			if /^(.*)\/$/.match(dir)
				@@temp_dir = $1
			else
				@@temp_dir = dir
			end
		end

		def set_max_length_in_memory(length)
			@@max_length_in_memory = length
		end
	end


	attr_reader :checksum, :read_only

	#
	# BigString.new(bigString)			 # A Big String
	# BigString.new(string)    		 # A String
	# BigString.new(string, false)    # A String
	# BigString.new(string, true)     # Filename
	#
	def initialize(*args)
		# print "in BigString initialize\n"
		#tf = Tempfile.new("temp", "c:/obdb")
		#tf.close
		#@tempfile = tf.path

		raise "Temporary directory not set for BigString" if !@@temp_dir

		@read_only = false

		#@tempfile = PersistentTempFile.new("#{@@temp_dir}/BigString", "bgs").create
		if args.size == 0 then
			#File.open(@tempfile, "wb").close
			inner_initialize("")
			#return
		#end

		# BigString intializer		
		elsif args.size == 1 &&  args[0].kind_of?(BigString) then
			@read_only = args[0].read_only
			if @read_only then
				inner_initialize(nil, args[0].tempfile)
			else 
				inner_initialize(args[0].to_s)
			end
			#bigString = args[0]
			#File.copy(bigString.tempfile, @tempfile)
			#@checksum = bigString.checksum
			#return
		# String or String, false initializer
		elsif (args.size == 1  &&  args[0].kind_of?(String)) ||
		      (args.size == 2  &&  args[0].kind_of?(String) && args[1].kind_of?(FalseClass))
				inner_initialize(args[0].to_s)
		      #string = args[0]
				#File.open(@tempfile, "wb") do |f|
				#	f.write(string)
				#end
				#@checksum = calc_checksum(string)
				#return			
		# String, true initializer (which means its a filename)
		elsif (args.size == 2 &&  args[0].kind_of?(String) && args[1].kind_of?(TrueClass))
			filename = args[0]
			if FileTest.exist?(filename) then
				inner_initialize(nil, filename)
				#File.copy(filename, @tempfile)
				#update
				#return
			else
				raise ArgumentError.new("Invalid filename initializer - '#{filename}'")
			end
		# String, true initializer (which means it is a filename but we don't want to copy it)
		# third argument (a symbol) indicates how we want to treat it
		#   :read_only - means that we don't ever want to update this
		elsif (args.size == 3 &&  args[0].kind_of?(String) && args[1].kind_of?(TrueClass) && args[2].kind_of?(Symbol))
			case args[2]
			when :read_only
				@read_only = true
			else
				raise ArgumentError.new("Invalid filename option: #{args[2]}")
			end
			
			filename = args[0]
			if FileTest.exist?(filename) then
				inner_initialize(nil, filename)
			else
				raise ArgumentError.new("Invalid filename initializer - '#{filename}'")
			end
		else
			raise ArgumentError.new("Can only create BigString from String and BigString")
		end
	end

	def tempfile
		return @tempfile if @read_only

		if @size > @@max_length_in_memory then
			@tempfile = PersistentTempFile.new("#{@@temp_dir}/BigString", "bgs").create unless @tempfile
			@tempfile
		else
			unless @tempfile && File.exist?(@tempfile)
				tf = Tempfile.new("BigString")
				tf.close
				@tempfile = tf.path
				write_binary(@tempfile, @value)
			end
		end

		@tempfile
	end

	#
	# This should be called if the underlying file has changed
	#
	def update(data=nil)
		temp_file_up_to_date = (data == nil)	# prevent rewrite of data unnecessarily

		# read in the changes to the temp file unless we are updating by data passed in
		data = read_binary(self.tempfile) unless data
		
		had_perm_temp_file = @size > @@max_length_in_memory
		
		@size = data.size
		if @size > @@max_length_in_memory then
			if !@read_only then
				write_binary(self.tempfile, data) unless temp_file_up_to_date
			end
			@value = nil
		else
			File.unlink(@tempfile) if @tempfile
			@value = data			
		end

		@size = data.size
		@checksum = calc_checksum(data)
		self
	end

	
	def dup
		BigString.new(self)
	end

	def ==(other)
		if other.kind_of?(BigString) then
			@checksum == other.checksum
		elsif other.kind_of?(String) then
			@checksum == calc_checksum(other)
		elsif other.kind_of?(NilClass) then
			return false
		elsif other.kind_of?(Fixnum) then
			return false
		else
			raise ArgumentError.new("Can only compare String and BigString to BigString, '#{other.type}' is not supported")
		end
	end

	def generate_changes(other)
		#print "in BigString.generate_changes from '#{self}' to '#{other}'\n"
		if other.checksum != checksum then
			change = DiffChange.new(tempfile, other.tempfile)
		else
			change = nil
		end
		change
	end

	def check_conflict(diffChange)
		return false		# not checking conflicts for now
	end

	def to_str
		return self.to_s
	end

	def method_missing(sym, *args, &block)
		value = self.to_s
		old_value = value.dup
		ret_value = value.send(sym, *args, &block)

		update(value) if value != old_value
		#File.open(@tempfile, "wb") {|f| f.write value} if value != old_value

		ret_value
	end

	def value
		ret = self.to_s
		#puts"AR_BigString: ret = #{ret.inspect}"
		ret 
	end

	def to_s
		return "(uninitialized)" unless @size

		if @size > @@max_length_in_memory then
			return read_binary(@tempfile)
		else
			return @value
		end
	end

	private
	
	def inner_initialize(string, filename=nil)
		@size = 0
		if string then
			update(string)
		else
			if @read_only then
				@tempfile = File.expand_path(filename)
			end
			update(read_binary(filename))
		end
	end

	def read_binary(filename)
		data = nil
		File.open(filename, "rb") {|f| data = f.read }
		data
	end

	def write_binary(filename, data)
		File.open(filename, "wb") {|f| f.write data}
	end

	# 
	# This utility routine calculates a checksum for a string and returns it
	#
	def calc_checksum(str)
		checksum = MD5.new(str).hexdigest	
#		checksum = 0
#		str.each_byte do |c|
#			checksum ^= c
#print "[#{checksum}](#{c})"
#		end
#		print "\nfor str = '#{str}', checksum = #{checksum}\n"
		checksum
	end
end

class String

	$aaa = $aaa || 0
	#$stdout.print "1:in String, #{$aaa}\n"
	if $aaa == 0 then
		alias_method :old_equal, :==
		#$stdout.print "2:in String, #{$aaa}\n"
	
		def ==(other)
			#$stdout.print "3:in String, other class = #{other.class}\n"
			if other.kind_of?(BigString)
				#print "before using BigString equal, BigString = '#{other}', self = '#{self}'\n"
				res = (other == self)
				#print "after using BigString equal, res = #{res.inspect}\n"
				res
			else
				old_equal(other)
			end
		end
		$aaa += 1
	end
	#STDERR.print "2:in String, #{$aaa}\n"
end
