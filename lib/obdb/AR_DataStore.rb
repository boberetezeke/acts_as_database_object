require "obdb/Query"
require_gem "activerecord"
require "acts_with_metadata"
#require "acts_as_incrementally_versioned"

#
# This is the abstract base class for all store classes
#
class DataStore < ActiveRecord::Base
	class << self
		def get_store_class_from_uri(store_uri)
			stores = {}
			@store_list.each {|s| stores[s.uri_name] = s}
			
			if m = /^(.*):\/\/(.*)(\?(.*))?$/.match(store_uri) then
				uri_name = m[1]
				uri_content = m[2]
				query_string = m[4]
				
				store_class = stores[uri_name]
				raise "Unknown store class" unless store_class

				if query_string then
					query = Query.new_from_string(query_string)
					raise "Invalid query string" unless query
				end
				
				$TRACE.debug 5, "get_store_class_from_uri: uri_name = '#{uri_name}', uri_content = '#{uri_content}', store_class = '#{store_class}'"
				return [store_class,uri_content,query]
			else
				$TRACE.debug 5, "get_store_class_from_uri: no match on '#{store_uri}'"
				return nil
			end
		end

		def inherited(subclass)
			@store_list ||= []
			@store_list.push(subclass)
		end

		def query
			Query.new("")
		end
	end

	acts_with_metadata
	#acts_as_versioned :if_changed => [:status, :last_sync_time]
	
	# data stores are database objects
	#include DatabaseObjectInstance
	#extend DatabaseObjectClass

	has_field :type, :type => :string	# necessary for Single Table Inheritance
	
	# object info - not really needed as DataStore should will never be instatiated
	#object_info ({ :printName => "Data Store (generic)" })

	# the status of the store's sync
	has_field :status, :type => :string, :choices => ["idle", "pending", "syncing"]
	#member_info :status, {
	#	:printName => "Status",
	#	:printFormat => "%s",
	#	:enumValues => [:idle, :pending, :syncing],
	#	:type => Symbol}

	# the last time a sync was done		
	has_field :last_sync_time, :type => :datetime
	#member_info :last_sync_time, {
	#	:printName => "Last Sync Time",
	#	:printFormat => "%s",
	#	:type => String}

	#
	# override this to do any store specific initialization
	#
	def initialize
		super

		self.last_sync_time = nil
		self.status = "idle"
	end
	
	#
	# this should return an array of objects that match the given
	# query
	#
	# in addition object.set_dbID(self, dbID) should be called for
	# each object in the list, where dbID if the data store has a
	# unique id value that is assigned by the store (an auto-generated
	# id field for example)
	#
	def get_objects(syncer, query, status)
		raise "getObjects: Not Implemented"
		
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
	# this should be redefined if the store can be formatted
	#
	def format_symbol
		:format
	end

	# 
	# This should apply changes from the object database to the data store.
	# There are three types of changes:
	#   ObjectChange::MEMBER_CHANGES - changes to a field
	#   ObjectChange::ADDITION - an object is added
	#      the code needs to set the dbID for object.changedObject after it is 
	#      retreived from the store (by using DatabaseObject#set_dbID(self, store_id))
	#   ObjectChange::DELETION - an object is to be deleted
	#
	# Out of data info below
	#
	# There are special considerations when dealing with relationships because
	# relationships need to be translated from gid's to dbID's.  However, dbID's
	# are often not assigned to objects for this store until after additions are 
	# done.
	#
	# So once add dbID's are assigned to newly created store objects, all ObjectID's
	# which are part of Relationship members of new objects and all ObjectID's that
	# are contained in RelationshipDiffs (which are part of 
	# RelationshipChanges, then MemberChange, then MemberChanges, then finally an 
	# ObjectChange) must be resolved by calling ObjectID#resolve_IDs on them.
	#
	def apply_changes(syncer, object_changes, status)
		raise "applyChanges: Not Implemented"

		# change_list.each do |object_change|
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
	# should return a string of the form store_name://specific_store_info
	#
	def to_s
		raise "to_s: Not Implemented"
	end

	#
	# this should return what classes of objects this particular store object can contain as
	# an array of strings of the class names.
	#
	def classes
		raise "classes: Not Implemented"
	end
	
	#
	# This method should be filled out by the store if there is a query
	# specifying a subset of the store's objects
	#
	def query
		Query.new("true")
	end

	#
	# This should be implemented if the data store needs to be
	# connected to.
	#
	def connect
	end

	#
	# This should be implemented if the data store needed to
	# be connected to. It should break the connection.
	# 
	def disconnect
	end

	def start_sync
		@status = :pending if @status == :idle
	end
end

