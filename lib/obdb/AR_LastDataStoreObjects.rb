#
# This file implements how the last objects from a data store are stored
#
# in this case, we store the objects in the ar_object tables themselves
#
# The basic implementation involves storing last data store objects in the same
# table as othe other ar_objects. They have additional columns store, store_id and
# base_database_object_id. They are distinguished from the other objects
# by having the store and store_id columns set (regular ar_objects have them NULL).
# Also they have the base_database_object_id column set to the database object
# that is the basis for the ar_object that they are connected to.
#
# For the ObjectDatabase class we implement
#   get_last_data_store_objects() - implemented by getting objects with store set to the passed in store
#   put_last_data_store_objects() - store them off with the correct store, store_id and the 
#                                   base_database_object_id set to the correct database object.
#   create_last_data_store_add_table_proc() - this adds the store, store_id, and base_database_object_id 
#                                   columns
#
# For ar_object classes (eg. Widget)
#   dbID() - for last data store objects it returns store id, for real ar_objects, it uses SQL to 
#            lookup the id through the ar_object's database object and its last data store objects
#            through the base_database_object_id's.
#   set_dbID() - this sets store_id and store and then saves the dbID -> object relationship for 
#                later use when setting up base_database_object_id's when doing
#                put_last_data_store_objects()
#   #last_store_object_find_mod - this class method modifies find calls to ignore last data store objects
#
# For ObjectDatabase::Synchronizer we implement
#   dbIDHash - which holds the dbID mapper
#   save_remote_object_locally - makes sure the dbID hash gets updated when the database object
#                                gets an ID
# 
#

class SameTable_LastDataStoreObjects_DO_Mods
	class << self
	def create_database_object_columns(t)
	end
	end
end

module SameTable_LastDataStoreObjects_ObjectDatabase_object_methods
	extend self
	
	class << self
		def included(mod)
			#puts "adding 'store' column"
			ActiveRecord::Acts::WithMetaData::BUILT_IN_COLUMNS << "store"  #add_to_built_in_columns("store")
#			ActiveRecord::Acts::WithMetaData::BUILT_IN_COLUMNS << "store_id"  #add_to_built_in_columns("store")
#			ActiveRecord::Acts::WithMetaData::BUILT_IN_COLUMNS << "base_database_object_id"  #add_to_built_in_columns("store")
		end
	end
	
	def create_last_data_store_add_table_proc
		Proc.new do |action, table_name|
			case action
			when :add_additional_fields
				"t.column 'store', :string;" +
				"t.column 'store_id', :string;" +
				"t.column 'base_database_object_id', :integer;"
			when :add_additional_tables
				""
			end
		end
	end

	def get_last_data_store_objects(sync, store, query)
		last_store_objects = []
$TRACE.debug 5, "get_last_data_store_objects: #{store.to_s}, classes = #{store.classes.inspect}"
		# for each class that this store contains
		store.classes.each do |klass|
			# add to the list of last_store_objects that have this store as their store
			if $USE_FIND then
			last_store_objects += klass.constantize.find(:all, :conditions => ["store = ?", store.to_s], :include => :database_object,  :use_original => true)
			else
			last_store_objects += klass.constantize.find(:all, :conditions => ["store = ?", store.to_s], :include => :database_object) # :use_original => true)
			end
		end

		last_store_objects
	end

	def before_put_last_data_store_objects(sync)
		sync.dbIDHash.freeze_hash
	end

	def put_last_data_store_objects	(sync, store, query, objects)
		$TRACE.debug 5, "put_last_data_store_objects: " + objects.map{|o| o.to_s}.join(",")
		
		# get all the old objects in one query
		old_objects = []
		store.classes.each do |klass_str|
			if $USE_FIND then
			old_objects += klass_str.constantize.find(:all, :conditions => ["store = ?", store.to_s], :use_original => true)
			else
			old_objects += klass_str.constantize.find(:all, :conditions => ["store = ?", store.to_s]) #, :use_original => true)
			end
		end
		
		# hash them based on the store_id
		old_objects_hash = {}
		old_objects.each {|oo| old_objects_hash[oo.store_id] = oo}

		# store each new one in turn		
		objects.each do |obj|
			#old_object = obj.class.find(:first, :conditions => ["store = ? and store_id = ?", store.to_s, obj.store_id])
			old_object = old_objects_hash[obj.store_id]
			old_objects_hash.delete(obj.store_id)		# delete that old object from the hash
			
			# no need to store the new object if it is the same as the last stored one
			next if old_object == obj

			$TRACE.debug 5, "for object = #{obj}, before object_changes.clear"

			# get rid of any history for this object			
			obj.database_object.object_changes.clear

			# if there was an old object in the database
			if old_object then
				$TRACE.debug 5, "an old object was stored"
				
				obj.base_database_object = old_object.base_database_object	# get base database object from old one
				old_object.database_object.destroy		# destroy old database object
				old_object.destroy							# destroy old object

			# else this is a new object in the remote store
			else
				$TRACE.debug 5, "a new object for the remote store"
				
				# find it in either the local or remote changes
				#base_do = local_changes.find_object_by_dbID(store, obj.store_id)
				#base_do = remote_changes.find_object_by_dbID(store, obj.store_id) unless base_do
				obj.base_database_object_id = sync.dbIDHash.lookup_object(obj.store_id)
			end
			$TRACE.debug 5, "put_last_data_store_objects: before save"
			obj.database_object.set_unversioned
			obj.save									# save new one
			$TRACE.debug 5, "put_last_data_store_objects: after save"
		end

		# delete any objects 
		old_objects_hash.each_value do |oo|
			$TRACE.debug 5, "deleting last stored object: #{oo}"
			oo.database_object.destroy
			oo.destroy
		end
	end
end

module SameTable_LastDataStoreObjects_acts_as_do_mods_class_methods
	def last_store_object_find_mod(find_method, table_name, *args)
		add_query = "#{table_name}.store is NULL"
		$TRACE.debug 5, "in acts_as_database_object#find(#{find_method}, #{args.inspect})"
		if args[0].kind_of?(Hash) then
			$TRACE.debug 5, "hash is 2nd argument"
			options_hash = args[0]
			conditions = options_hash[:conditions]
			if conditions then
				$TRACE.debug 5, "existing conditions = #{conditions.inspect}"
				if conditions.kind_of?(Array) then
					options_hash[:conditions] = ["(#{conditions.first}) and #{add_query}", *conditions[1..-1]]
				elsif conditions.kind_of?(String) then
					options_hash[:conditions] = "(#{conditions}) and #{add_query}"
				else
					$TRACE.debug 1, "conditions of unknown type: #{conditions.class}"
					raise "Unable to handle conditions of class: #{conditions.class}"
				end
			else
				options_hash[:conditions] = add_query
			end

			$TRACE.debug 5, "final conditions = #{args[0][:conditions].inspect}"
			return [find_method, *args]
		else
			$TRACE.debug 5, "only method, specified, adding conditions"
			return [find_method, {:conditions => add_query}]
		end
	end

end


module SameTable_LastDataStoreObjects_ObjectDatabaseSynchronize_object_methods
	class DbIDHash
		def initialize
			@hash = {}
			@hash_frozen = false
		end

		def set_dbID(dbID, obj)
			return if @hash_frozen
			id = obj.attributes["id"] || obj.object_id
			$TRACE.debug 5, "set_dbID (before): dbID = #{dbID.inspect}, id = #{id.inspect}, @hash = #{@hash.inspect}, "
			@hash[dbID] = id
			$TRACE.debug 5, "set_dbID (after): @hash = #{@hash.inspect}, "
		end

		def resolve_dbID(obj)
			$TRACE.debug 5, "resolve_dbID (before): database object_id = #{obj.object_id}, @hash = #{@hash.inspect}, "
			dbID = @hash.invert[obj.object_id]
			$TRACE.debug 5, "resolve_dbID (mid): dbID = #{dbID.inspect} "
			@hash[dbID] = obj.attributes["id"]
			$TRACE.debug 5, "resolve_dbID (after): @hash = #{@hash.inspect}, "
			@resolve_started = true
		end

		def lookup_object(dbID)
			$TRACE.debug 5, "lookup_object: @hash = #{@hash.inspect}, dbID = #{dbID.inspect}"
			@hash[dbID]
		end

		def freeze_hash
			@hash_frozen = true
		end
	end

	def dbIDHash
		@dbIDHash ||= DbIDHash.new
		@dbIDHash
	end

	def save_remote_object_locally(ar_object)
		ar_object.store = nil
		ar_object.store_id = nil
				$TRACE.debug 1, "-- ADDING NEW OBJECT (1)-- (#{ar_object})"
		ar_object.save
				$TRACE.debug 1, "-- ADDING NEW OBJECT (2)-- (#{ar_object})"
		ar_object.database_object.save
				$TRACE.debug 1, "-- ADDING NEW OBJECT (3)-- (#{ar_object})"
		@dbIDHash.resolve_dbID(ar_object.database_object)
				$TRACE.debug 1, "-- ADDING NEW OBJECT (4)-- (#{ar_object})"
	end
end

module SameTable_LastDataStoreObjects_acts_as_database_object_object_methods
	def set_dbID(sync, store, id_str)
		self.store = store.to_s
		self.store_id = id_str
		sync.dbIDHash.set_dbID(id_str, self.database_object)
		#self.database_object.set_local_dbID(store, id_str)
	end

	def dbID(sync, store)
		# if this is a last data store object then it will contain a store id
		if self.store_id then
			return self.store_id
			
		# else if it is a database object, the dbID can be found by using the database object and finding the
		# last data store object that is linked to it for this store
		else
			database_object = self.database_object
			sql = "select store_id from #{database_object.databaseable_object_type.tableize} where base_database_object_id=#{database_object.attributes['id']} and store='#{store.to_s}'"
			$TRACE.debug 5, "running sql: #{sql}"
			ar_objects = database_object.databaseable_object_type.constantize.find_by_sql(sql)
			if ar_objects.size == 0 || ar_objects.size > 1 then
				raise "too many or too few objects (#{ar_objects.size}) from #{self.database_object.databaseable_object_type.tableize} for id=#{self.attributes['id']} and store=#{store}" +
				     "this is probably because the DataStore object didn't set the dbID in apply_changes::ADDITION"
			else
				return ar_objects.first.store_id
			end
		end
	end
end

