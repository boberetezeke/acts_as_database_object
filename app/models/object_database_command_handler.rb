class ObjectDatabaseCommandHandler < ObjectDatabaseSourceCode
	acts_as_database_object

	has_field :prefix

	after_save :write_handler_code

	link_text {|x,c| x.name}

TEMPLATE=<<EOT
class XxHandler < ODRails::CommandHandler
	def handle_command(command_str)
	end
end
EOT

	class << self
		def new_from_template
			ObjectDatabaseCommandHandler.new(:content => TEMPLATE)
		end
	end
	
	def name_from_content
		/class\s+(\w+)Handler </.match(self.content)[1]
	end
	
	def write_handler_code
		filename = "app/command_handlers/#{self.name.tableize.singularize}_handler.rb"
		write_source_code(filename)
	end	
end
