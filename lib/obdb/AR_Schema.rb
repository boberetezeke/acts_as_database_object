#require "obdb/acts_as_database_object"

class SchemaTable < ActiveRecord::Base
	acts_as_database_object do
		has_field :name, :type => :string
		has_many :schema_columns
	end

	link_text {|x,c| x.name}
end

class SchemaColumn < ActiveRecord::Base
	acts_as_database_object do
		belongs_to :schema_table

		has_field :name, :type => :string
		has_field :column_type, :type => :string
	end

	link_text {|x,c| (c.kind_of?(SchemaTable) ? "" : "#{x.schema_table.name}::") + x.name}
end

