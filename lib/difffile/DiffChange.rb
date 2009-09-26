require "difffile/DiffFile"
require "PersistentTempFile"

class DiffChange
	attr_reader :diff_changes, :memberConflict

	class << self
		def set_temp_dir(dir)
			if /^(.*)\/$/.match(dir)
				@@temp_dir = $1
			else
				@@temp_dir = dir
			end
		end
	end

	#
	# new(oldFilename, newFilename)
	#
	# new(diff_changes)
	#
	def initialize(*args)
		if args.size == 1 then
			@diff_changes = args.shift
			if !@diff_changes.kind_of?(Diff::Changes) then
				raise ArgumentError.new("Invalid single argument type: '#{@diff.class}'")
			end
		elsif args.size == 2 then
			oldValue, newValue = args
			if oldValue.kind_of?(String) && newValue.kind_of?(String) then
				$TRACE.debug 5, "oldValue = #{File.data(oldValue).x}, newValue = #{File.data(newValue).x}"
				diffFilename = PersistentTempFile.new("#{@@temp_dir}/Diff", "dif").create
				Diff::generate_diff(oldValue, newValue, diffFilename)
				@diff_changes = Diff::FileChanges.new(diffFilename)
			else
				raise ArgumentError.new("Invalid dual argument types: '#{oldValue.class}', #{newValue.class}'")
			end
		else
			raise ArgumentError.new("Wrong number of arguments: #{args.size}")
		end
	end

	def is_differential
		true
	end
	
	def conflictsWith(other, orig_value)
		newValue = BigString.new
		diffs_conflict = Diff::apply_diff(orig_value.tempfile, [@diff_changes, other.diff_changes], newValue.tempfile, false)
		newValue.update
		diffConflict = DiffConflict.new(orig_value, @diff_changes, other.diff_changes, newValue)
		if !diffs_conflict then
			diffConflict.resolve()
		end

		diffConflict
	end

	def apply_change_internal(oldValue, reverse)
		if oldValue.kind_of?(BigString) then
			newValue = BigString.new
			$TRACE.debug 5, "applying inverted diff_changes = '#{@diff_changes.content.x}' to file '#{File.data(oldValue.tempfile).x}'"
			Diff::apply_diff(oldValue.tempfile, [@diff_changes], newValue.tempfile, reverse)
#raise "exit early error" if $bob
			$TRACE.debug 5, "resulting in  '#{File.data(newValue.tempfile).x}'"
			return newValue.update
		else
			raise "value #{oldValue.kind_of?} must be of type BigString to apply_change"
		end
	end
	
	def apply_change(oldValue)
		apply_change_internal(oldValue, false)
	end
	
	def reverse_change(newValue)
		apply_change_internal(newValue, true)
	end

	def combine(diffChange)
		combined_diff_changes = Diff::ArrayChanges.new
		$TRACE.debug 5, "combining change #{@diff_changes.content.x} and #{diffChange.diff_changes.content.x}"
		Diff::accumulate_2_diffs(@diff_changes, diffChange.diff_changes, combined_diff_changes)
		$TRACE.debug 5, "resulting in changes = #{combined_diff_changes}"

		return DiffChange.new(combined_diff_changes)
	end

	def to_s
		@diff_changes.content
	end

	def ==(other)
		@diff_changes == other.diff_changes
	end
end

class DiffConflict
	attr_reader :orig_value, :new_value
	attr_reader :diff_changes1, :diff_changes2
	attr_reader :memberConflict
	
	def initialize(orig_value, diff_changes1, diff_changes2, new_value)
		@orig_value = orig_value
		@diff_changes1 = diff_changes1
		@diff_changes2 = diff_changes2
		@new_value = new_value
		@resolved = false
	end
	
	def resolve(new_value=nil)
		@resolved = true
		@new_value = new_value if new_value
		$TRACE.debug 5, "in resolve, new_value = '#{new_value.to_s.x}'"
		if @memberConflict then
			@memberConflict.childResolved
		end
	end

	def memberConflict=(memberConflict)
		@memberConflict = memberConflict
		if @resolved then
			@memberConflict.childResolved
		end
	end

	def change
		$TRACE.debug 5, "in change, @new_value = '#{@new_value.to_s.x}'"
		SimpleChange.new(@orig_value, @new_value)
	end

	def ==(other)
		return false if @new_value != other.new_value
		return false if @orig_value != other.orig_value
		return false if @diff_changes1 != other.diff_changes1
		return false if @diff_changes2 != other.diff_changes2

		return true
	end
end

