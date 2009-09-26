module Observable2
	def add_observer(observer)
		$TRACE.debug 7, "adding observer #{observer.class}:#{observer.object_id} to #{self.class}:#{self.object_id}"
		@observers ||= []
		@observers.push(observer)
	end

	def delete_observer(observer)
		@observers.delete(observer) if defined?(@observers)
	end

	def delete_observers
		@observers.clear if defined? @observers
	end

	def get_and_delete_observers
		o = @observers
		@observers = []
		o
	end

	def set_observers(observers)
		@observers = observers
	end

	def notify_observers(*args)
		@observers.each {|v| v.on_observed_change(*args)} if @observers #if defined?(@observers)
	end
end
