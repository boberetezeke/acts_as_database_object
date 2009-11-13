class ObjectDatabaseDataStore < ObjectDatabaseModel
	acts_as_database_object

	link_text {|x,c| "Data Store: #{x.name}"}

TEMPLATE=<<EOT
class XX < DataStore
   acts_as_database_object do

      # add in any fields that are specific to this data store

      #has_field :fieldname
   end

   #
   # return database objects from store objects
   #
   def get_objects(syncer, query, status)		
      # object_list = []
      # #for each object that matches the query
      #   # object = an active record database object that contains the information from the store object
      #   # store_object_id = the object_id of the store object
      #   object.set_dbID(syncer, self, store_object_id)
      #   object_list.push(object)
      # #end
      # return object_list
   end

   # 
   # apply changes to the data store
   #
   def apply_changes(syncer, object_changes, status)
      # object_changes.each do |object_change|
      #   
      #   store_object_id = object_change.deleted_object.ar_object.dbID(sync, self) unless object_change.change_type == ObjectChange::ADDITION
      #
      #   case object_change.change_type
      #   when ObjectChange::ADDITION
      #     # add object from object_change.new_object
      #     # then set dbID for that object with the value store_dbID in the code below
      #     # object_change.new_object.ar_object.set_dbID(syncer, self, store_dbID)
      #   when ObjectChange::DELETION
      #     # delete the object from the data store using store_object_id
      #   when ObjectChange::MEMBER_CHANGES
      #     # get store object based on store_object_id into store_object
      #     object_change.member_changes.each do |member_change|
      #			member_info = object_change.changed_object.ar_object.class.members[member_change.member]
      #			member_value = object_change.changed_object.send(member_change.member)
      #			interfaces = member_info.interfaces	# to access interface hash associated with member
      #     end
      #   end
      # end
      #	
   end

   #
   # return array of classes (as strings) that can be gotten from this store
   #
   def classes
   end
end
EOT

	class << self
		def new_from_template
			ObjectDatabaseModel.new(:content => TEMPLATE)
		end
	end
end
