class ObjectDatabaseConfiguration < ActiveRecord::Base
	acts_as_database_object do
		has_field :data_store_path
	end
end
