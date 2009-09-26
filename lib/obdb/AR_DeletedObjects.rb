class SameTable_DeletedObjects_DO_Mods
	class << self
	def create_database_object_columns(t)
		t.column :ar_object_deleted, :boolean, :default => 0
	end
	end
end

module SameTable_DeletedObjects_ObjectDatabase_object_methods
	extend self
	class << self
		def included(mod)
			#puts "adding 'deleted' column"
			ActiveRecord::Acts::WithMetaData::BUILT_IN_COLUMNS << "deleted"
		end
	end
	
	def create_deleted_objects_add_table_proc
		Proc.new do |action, table_name|
			case action
			when :add_additional_fields
				"t.column 'deleted', :boolean, :default => 0;"
			when :add_additional_tables
				""
			end
		end
	end

	def get_objects(query=Query.new)
		get_objects_internal(query, false)
	end

	def deleted_objects(query=Query.new)
		get_objects_internal(query, true)
	end

	def get_objects_internal(query, is_deleted)
		$TRACE.debug 5, "get_objects_internal(begin)"
		#database_objects = Contact.find(:all, :conditions => "id >= 1 and id <= 300")
		$TRACE.debug 5, "get_objects_internal(begin2)"
		#if $USE_FIND then
		#database_objects = DatabaseObject.find(:all, :conditions =>[ "ar_object_deleted = ?", is_deleted], :use_original => true)	# FIXME: need to use query
		#else
		database_objects = DatabaseObject.find(:all, :conditions =>[ "ar_object_deleted = ?", is_deleted]) #, :use_original => true)	# FIXME: need to use query
		#end
		deleted_objects_classes = database_objects.map{|dobj| dobj.databaseable_object_type_as_subclass}.uniq
		#deleted_objects_classes = ["Contact"]
		deleted_objects = []
		$TRACE.debug 5, "get_objects_internal(mid)"
		deleted_objects_classes.each do |doc|
			$TRACE.debug 5, "get_objects_internal(before): getting objects for class #{doc} where deleted = #{is_deleted}"
			if $USE_FIND then
			new_objects = doc.constantize.find(:all, :conditions => ["deleted = ? and store_id is null", is_deleted], :include => :database_object, :use_original => true)
			else
			new_objects = doc.constantize.find(:all, :conditions => ["deleted = ? and store_id is null", is_deleted], :include => :database_object) #, :use_original => true)
			end
			$TRACE.debug 5,"get_objects_internal(after): got #{new_objects.size} objects for class #{doc}"
			deleted_objects += new_objects
			deleted_objects.each {|obj| $TRACE.debug 9, "deleted object = #{obj}"}
		end
		$TRACE.debug 5,"get_objects_internal(end)"
		return deleted_objects
	end

	def delete(ar_object)
		$TRACE.debug 5, "deleting ar_object: #{ar_object}"
		ar_object.database_object.ar_object_deleted = true
		ar_object.database_object.save
		ar_object.deleted = true
		ar_object.save

		ObjectChange.new(ObjectChange::DELETION, ar_object.database_object).save
	end
end

module SameTable_DeletedObjects_acts_as_do_mods_class_methods
	def deleted_objects_find_mod(find_method, table_name, *args)
		add_query = "#{table_name}.deleted = 'f'"
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

