gem "activerecord"
require "active_record"
require "SilentMigration"
require "obdb/AR_LastDataStoreObjects"
require "obdb/AR_DeletedObjects"

=begin
class SchemaMigrations_Migration < Silent_Migration
	class << self
	def up
		create_table :schema_migrations do |t|
			t.column	:name, :string
			t.column	:depends_on, :integer
		end
	end
	end
end
=end

class SchemaTables_Migration < Silent_Migration
	class << self
	def up
		create_table :schema_tables do |t|
			t.column	:name, :string
			
			# necessary for deleted objects (FIXME: need to do this automatically)
			t.column :store, :string
			t.column :store_id, :string
			t.column 'deleted', :boolean, :default => 0
		end
	end
	end
end

class SchemaColumns_Migration < Silent_Migration
	class << self
	def up
		create_table :schema_columns do |t|
			t.column	:name, :string
			t.column	:column_type, :string
			t.column	:schema_table_id, :integer

			# necessary for deleted objects (FIXME: need to do this automatically)
			t.column :store, :string
			t.column :store_id, :string
			t.column 'deleted', :boolean, :default => 0
		end
	end
	end
end

=begin
class DataStores_Migration < Silent_Migration
	class << self
	def up
		create_table :data_stores do |t|
			t.column	:name, :string
			t.column	:status, :integer
			t.column	:last_sync_time, :datetime
		end
	end
	end
end
=end

class DatabaseObjects_Migration < Silent_Migration	
	class << self
	def up
		create_table :database_objects do |t|
			t.column :real_creation_time, :datetime
			t.column :last_change_time, :datetime
			t.column :databaseable_object_type, :string
			t.column :databaseable_object_id, :integer
			t.column :databaseable_object_type_as_subclass, :string
			t.column :current_version_num, :integer
			t.column :parent_id, :integer
			t.column :parent_version_num, :integer
			SameTable_LastDataStoreObjects_DO_Mods.create_database_object_columns(t)
			SameTable_DeletedObjects_DO_Mods.create_database_object_columns(t)
		end
	end
	end
end
=begin
class StoreIDs_Migration < Silent_Migration
	class << self
	def up
		create_table :store_ids do |t|
			t.column :database_object_id, :integer
			t.column :name, :string
			t.column :store_id, :string
		end
	end
	end
end
=end

class ObjectChanges_Migration < Silent_Migration
	class << self
	def up
		create_table :object_changes do |t|
			t.column :database_object_id, :integer
			t.column :old_database_object_id, :integer
			t.column :change_type, :integer
			t.column :created_datetime, :datetime
			t.column :deleted_datetime, :datetime
		end
	end
	end
end

class MemberChanges_Migration < Silent_Migration
	class << self
	def up
		create_table :member_changes do |t|
			t.column :object_change_id, :integer
			t.column :member, :string
			t.column :change_time, :datetime
			t.column :change, :text
		end
	end
	end
end
