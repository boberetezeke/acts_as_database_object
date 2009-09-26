class Time
	class << self
		def minSecs(mins)
			mins * 60
		end

		def hourSecs(hours)
			hours * Time.minSecs(60)
		end

		def daySecs(days)
			days * Time.hourSecs(24)
		end

		def monthSecs(months)
			months * Time.daySecs(30)
		end

		def current
			if defined?(@@current) then
				@@current
			else
				Time.now
			end
		end

		def current=(time)
			#puts "setting current to #{time}"
			@@current = time
		end

		def set_current_to_now
			#puts "setting @@current"
			@@current = old_now
			#puts "@@current = #{@@current}"
		end
		
		alias :old_now :now
		def now
			actual_now = old_now
			#puts "caller = #{caller.inspect}"
			#breakpoint
			if defined? @@current then
				imm_caller = caller[0]
				#puts "now called with #{actual_now} from #{imm_caller.class} - #{imm_caller.inspect}"
				if /timestamp\.rb/.match(imm_caller) then
					#puts "returning @@current"
					return @@current
				else
					return actual_now
				end
			else
				return actual_now
			end
		end
	end
end
