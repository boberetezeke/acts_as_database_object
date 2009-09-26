class SimpleChange
	attr_accessor :oldValue, :newValue

	def initialize(oldValue, newValue)
		@oldValue = oldValue
		@newValue = newValue
	end
	
	def is_differential
		false
	end
	
	def ==(other)
		if @oldValue == other.oldValue && @newValue == other.newValue then
			return true
		else
			return false
		end
	end

	def reverse_change(newValue)
		@oldValue
	end

	def conflictsWith(other, orig_value)
		if newValue != other.newValue then
			return SimpleConflict.new(oldValue, newValue, other.newValue)
		else
			if $NEW_RESOLVE then
				$TRACE.debug 5, "identical new values: OLD:#{oldValue}, NEW:#{newValue}"
				s = SimpleConflict.new(oldValue, newValue, other.newValue)
				s.resolve(newValue)
				return s
			else
				return nil
			end
		end
	end

	def combine(simpleChange)
		SimpleChange.new(@oldValue, simpleChange.newValue)
	end

	def apply_change(old_value)
		@newValue
	end
	
	def to_s
		"[OLD:#{@oldValue}][NEW:#{@newValue}]"
	end
end

module SimpleChangeMixin
	def generate_changes(other)
		if self != other then
			SimpleChange.new(self, other)
		else
			nil
		end
	end
end


class SimpleConflict
	attr_reader :lastValue, :localValue, :remoteValue, :chosenValue
	if $NEW_RESOLVE then
		attr_reader :memberConflict
	else
		attr_accessor :memberConflict
	end

	def initialize(lastValue, localValue, remoteValue)
		@lastValue, @localValue, @remoteValue = lastValue, localValue, remoteValue
		@memberConflict = nil
		@chosenValue = nil
	end

	if $NEW_RESOLVE then
		def memberConflict=(mc)
			@memberConflict = mc
			$TRACE.debug 9, "SimpleConflict.memberConflict: setting @memberConflict = #{mc}"
			if @chosenValue then
				$TRACE.debug 9, "SimpleConflict.memberConflict: notifying memberConflict about resolution"
				@memberConflict.childResolved
			end			
		end
	end
	
	def resolve(chosenValue)
		@chosenValue = chosenValue
		if $NEW_RESOLVE then
			$TRACE.debug 9, "resolving with value #{chosenValue}"
			if @memberConflict 
				$TRACE.debug 9, "SimpleConflict.resolve: notifying memberConflict about resolution"
				@memberConflict.childResolved
			end
		else		
			@memberConflict.childResolved
		end
	end

	def change
		SimpleChange.new(@lastValue, @chosenValue)
	end

	def ==(other)
		if other == nil then
			false
		else
			other.lastValue == @lastValue &&
			other.localValue == @localValue &&
			other.remoteValue == @remoteValue &&
			other.chosenValue == @chosenValue
		end
	end
	def to_s
		"[lastValue:#{@lastValue}][localValue:#{@localValue}][remoteValue:#{@remoteValue}][chosenValue:#{@chosenValue}]"
	end
end

