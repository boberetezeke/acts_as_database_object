# Put your code that runs your task inside the do_work method
# it will be run automatically in a thread. You have access to
# all of your rails models if you set load_rails to true in the
# config file. You also get @logger inside of this class by default.

class ActiveRecord::Base
	include DRbUndumped
end

class RemoteObjectWorker < BackgrounDRb::Rails
	def do_work
		puts "RemoteObjectWorker#do_work"
	end

	def find(*object_ids)
		if object_ids.last.kind_of?(Hash) then
			options = object_ids.pop
		end

		puts "RemoteObjectWorker#find(#{object_ids.inspect})"
		objects = object_ids.map do |object_id|
			ObjectSpace._id2ref(object_id.hex)
		end

		puts "objects = #{objects.inspect}"
		if objects.size == 1 then
			return objects.first
		else
			return objects
		end
	end
end
