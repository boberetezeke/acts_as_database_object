class ObjectDatabaseHelper < ObjectDatabaseSourceCode
	acts_as_database_object
	after_save :write_helper_code


TEMPLATE = <<EOT
module %sHelper
	include ActsWithMetaDataHelper
end
EOT

	class << self
		def new_for_name(name)
			self.new(:content => BigString.new(TEMPLATE % [name]))
		end
	end

	def name_from_content
		/module\s+(\w+)Helper/.match(self.content)[1]
	end
	
	def write_helper_code
		filename = "app/helpers/#{self.name.tableize.singularize}_helper.rb"
		write_source_code(filename)
	end
end
