class ObjectDatabaseWorker < ObjectDatabaseSourceCode
	acts_as_database_object

	after_save :write_view_code

	link_text {|x,c| "Worker: #{x.name}"}

TEMPLATE=<<EOT
# Put your code that runs your task inside the do_work method
# it will be run automatically in a thread. You have access to
# all of your rails models if you set load_rails to true in the
# config file. You also get @logger inside of this class by default.
class XXWorker < BackgrounDRb::Rails
  
  def do_work(args)
    # This method is called in it's own new thread when you
    # call new worker. args is set to :args
  end
end
EOT

#/

	class << self
		def new_from_template
			ObjectDatabaseView.new(:content => TEMPLATE)
		end
	end

	def name_from_content
		/class\s+(\w+)Worker/.match(self.content)[1]
	end
	
	def write_view_code
		write_source_code("lib/workers/#{self.name}_worker.rb")
	end
end

