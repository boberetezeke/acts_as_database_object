gem "activerecord"
gem "activesupport"
require "active_record"
require "active_support"
require "acts_with_metadata"
#require "obdb/acts_as_database_object"
require "obdb/AR_SchemaMigrations"
require "observer2"
require "obdb/AR_LastDataStoreObjects"
require "obdb/AR_DeletedObjects"
require "obdb/Query"
require "singleton"


#
# Extend the ActiveSupport Dependencies module so that we can handle acts_with_metadata exceptions
#
module Dependencies
	extend self

	alias :old_require_or_load :require_or_load
	def require_or_load(file_name, const_path = nil)
		begin
			old_require_or_load(file_name, const_path)
		rescue ActiveRecord::Acts::WithMetaData::TableNotFoundError => e
			ObjectDatabase::Loader.instance.handle_exception(e)			
			retry
		rescue ActiveRecord::Acts::WithMetaData::FieldNotFoundError => e
			ObjectDatabase::Loader.instance.handle_exception(e)			
			retry
		end
	end
end

class ObjectDatabase
	include Observable2
	include SameTable_LastDataStoreObjects_ObjectDatabase_object_methods
	include SameTable_DeletedObjects_ObjectDatabase_object_methods

	class Synchronizer
		attr_reader :object_conflicts, :local_changes, :remote_changes
		attr_reader :remote_objects
		attr_reader :store, :query, :object_database
		attr_reader :status, :log

		#
		# This is for errors that occur when interacting with a data store
		#
		class StoreError < StandardError
			attr_reader :message
			def initialize(message)
				@message = "StoreError: " + message
				super(@message)
			end
		end

		#
		# this is for merge conflicts
		#
		class MergeConflict < StandardError
			attr_reader :object_database_synchronizer
			def initialize(object_database_synchronizer)
				super("not all conflicts resolved")
				@object_database_synchronizer = object_database_synchronizer
			end
		end

		class Status
			attr_accessor :percent, :str, :log, :store_status, :store_name
			def initialize(str)
				@str = str
				@percent = 0
				@log = ""
				@store_status = nil
				@store_name = nil
				@aborted = false
				@mutex = Mutex.new
			end

			def aborted?
				aborted = nil
				@mutex.synchronize do 
					aborted = @aborted
				end
				return aborted
			end

			def abort
				@mutex.synchronize do
					@aborted = true
					@log << "aborted\n"
					@status = "aborting"
				end
			end

			def has_conflicts
			end
		end

		include SameTable_LastDataStoreObjects_ObjectDatabaseSynchronize_object_methods

		# directions
		IMPORT = :import
		EXPORT = :export
		ONE_TIME = :one_time
		
		SYNC = [EXPORT, IMPORT]
		IMPORT_ONLY = [IMPORT]
		EXPORT_ONLY = [EXPORT]
		ONE_TIME_IMPORT_EXPORT = [ONE_TIME]
		
		def initialize(store, query, object_database)
			@store, @query, @object_database = store, query, object_database
			@object_conflicts = ObjectConflicts.new
			@status = ObjectDatabase::Synchronizer::Status.new("idle")
			@status.store_name = store.name
			@status.log = ""
			
			$TRACE.debug 1, "ObjectDatabase::Synchronizer.new"
		end

		def setStore(store)
			@store = store
		end

		def setStatus(str)
			@status.str = str
		end
		
		def sync_start(sync_type=SYNC, options=nil)
			@sync_type = sync_type

			if !@store 
				@status.str = "Store Not Set, unable to Start"
				return
			end
			
			@status.str = "synching"
			#@store.getObjects(@query, @status)
			#return
			
			$TRACE.debug 1, "==== Synchronizing at Time #{Time.current}, with store #{@store} and query #{@query} ===="
			
			#@store.connect(options.advancedSettings.address_book_path) if @sync_type == ObjectDatabase::Synchronizer::SYNC
			@store.connect if @sync_type == ObjectDatabase::Synchronizer::SYNC

			# clear local dbIDs for this sync
			@dbIDHash = DbIDHash.new
			
			if @sync_type.include?(EXPORT) then
				# go through local objects of matching this query and compile array of [object ID, change description]
				@status.str = "checking for local changes"
				$TRACE.debug 1, "----- LOCAL CHANGES -----"
				@local_changes = @object_database.get_changes_since_last_sync(@store, @query)
			else
				@local_changes = ObjectChanges.new
			end

			if @sync_type.include?(IMPORT) then
				# go through remote data storage and compile array of [object ID, change description]
				@status.str = "checking for remote changes"
				$TRACE.debug 1, "----- REMOTE CHANGES -----"
				if @store.respond_to?(:get_changes) then
					@remote_changes = @store.get_changes(self, @query, @status)
				else
					@remote_changes, @remote_objects = @object_database.detect_differences(self, @store, @query, @status)
				end
			else
				@remote_changes = ObjectChanges.new
			end

			if @sync_type == ObjectDatabase::Synchronizer::SYNC
				@status.str = "looking for conflicts"
				$TRACE.debug 5, "localChanges = (see next line)\n#{local_changes}"
				$TRACE.debug 5, "remoteChanges = (see next line)\n#{remote_changes}"
				# check for change conflicts
				@commonIDs = local_changes.commonKeys(remote_changes)
				$TRACE.debug 5, "commonIDs = #{@commonIDs.inspect}"
				@commonIDs.each do |gid|
					$TRACE.debug 5, "gid = #{gid.inspect}, local_changes[gid] = #{local_changes[gid].inspect}"
					if conflict = local_changes[gid].conflictsWith(remote_changes[gid]) then
						$TRACE.debug 5, "adding conflict for DatabaseObject: #{gid}"
						@object_conflicts[gid] = conflict
					end
				end
				
				$TRACE.debug 5, "number of conflicts = #{@object_conflicts.size}"
				if !@object_conflicts.all_resolved
					$TRACE.debug 5, "found conflicts"
				end
			end
		end

		def sync_end
			#@status.str = "done"
			#return
			if !@store 
				@status.str = "Store Not Set, unable to continue"
				return
			end

			#print "@objectConflicts = #{@objectConflicts}\n"
			if @sync_type == ObjectDatabase::Synchronizer::SYNC
				if !@object_conflicts.all_resolved
					#raise "Not all conflicts resolved"
					raise MergeConflict.new(self)
					@status.str = "conflicts detected"
				end		

				# for the object changes with a common ID
				$TRACE.debug 1, "----- RESOLVING CONFLICTS -----"
				@status.str = "resolving conflicts"
				@commonIDs.each do |gid|
					# if there is a conflict for this ID 
					if @object_conflicts[gid] then
						$TRACE.debug 5, "conflict for id #{gid}"
						# get the change that resolves this conflict (locally and remotely)
						remote_change, local_change = @object_conflicts[gid].objectChange(@local_changes, @remote_changes)

						$TRACE.debug 5, "resolved conflict, local_change = #{local_change}, remote_change = #{remote_change}"

						if local_change then
							local_changes[gid] = local_change
						else
							local_changes.delete(gid)
						end

						if remote_change then
							remote_changes[gid] = remote_change
						else
							remote_changes.delete(gid)
						end
					end
				end	
			end

			# apply local changes to remote data store
			if @sync_type.include?(EXPORT) then
				@status.str = "applying changes remotely"
				$TRACE.debug 1, "----- APPLY LOCAL CHANGES -----"
				#$TRACE.debug 5, "local_changes = #{@local_changes}"
				$TRACE.debug 1, "----- BEFORE STORE APPLY LOCAL CHANGES -----"
				@store.apply_changes(self, @local_changes, @status)
				$TRACE.debug 1, "----- DONE APPLY LOCAL CHANGES -----"
			end
			
			# apply remote changes to local data store
			if @sync_type.include?(IMPORT) then
				@status.str = "applying changes locally"
				$TRACE.debug 1, "----- APPLY REMOTE CHANGES -----"
				$TRACE.debug 5, "remote_changes = #{@remote_changes}"
				@object_database.apply_changes(self, @remote_changes, @store, @status)
			end
			
			# save the latest objects from the remote store and the time we finished the sync at
			# only save latest remote objects if doing not doing one time imports/exports
			$TRACE.debug 5, "@sync_type = #{@sync_type.inspect}"
			unless @sync_type.include?(ONE_TIME)
				$TRACE.debug 1, "----- SAVE REMOTE STORE OBJECTS -----"
				#apply_changes(@remoteObjects,@localChanges)
				#@objectDatabase.putLastDataStoreObjects(@store, @query, @remoteObjects)
				@object_database.before_put_last_data_store_objects(self)
				if @store.respond_to?(:get_objects) then
					@object_database.put_last_data_store_objects(self, @store, @query, @store.get_objects(self, @query, @status))
				end
				last_sync_time = Time.current + 1
				#last_sync_time = last_sync_time.utc if @object_database.adapter == "mysql"
				@store.last_sync_time = last_sync_time
				@store.save
			end
			
			$TRACE.debug 1, "========= SYNC DONE ==========="
		
			# FIXME Only if there is a need
			#@object_database.save 
			
			@store.disconnect if @sync_type == ObjectDatabase::Synchronizer::SYNC
			
			@status.str = "done"
		end

		def sync(sync_type=SYNC, options = nil)
			sync_start(sync_type, options)
			sync_end
		end

		def sync_error
			@sync_error
		end
		
		def sync_resume
			@sync_mutex.lock do
				@sync_condition.signal
			end
		end

		def sync_in_thread(start_sync_only, *args, &block)
			@sync_error = nil
			@sync_mutex = Mutex.new
			@sync_condition = ConditionVariable.new
			
			Thread.new do
				begin
					puts "before start sync, args = #{args.inspect}"
					@status.log << "before start sync\n"
					sync_start(*args)
					puts "after start sync"
					@status.log << "after start sync\n"
				rescue StoreError => se
					$TRACE.debug 5, "Sync StoreError: #{se.message}"
					@status.log << se.message + "\n"
					return 
				rescue Exception => e
					$TRACE.debug 5, "Sync Exception 1: #{e.message}"
					@status.log << e.message + "\n"
					@status.log << e.backtrace.join("\n") + "\n"
					@status.log << "Done"
					return
				end

				
				begin
					sync_end unless start_sync_only

				rescue MergeConflict => e
					@sync_mutex.lock do
						@sync_error = e
						@sync_condtion.wait
					end
					
					# retry the sync 
					retry if @sync_error.object_database_synchronizer.all_resolved
				rescue Exception => e
					$TRACE.debug 5, "Sync Exception 2: #{e.message}"
					$TRACE.debug 5, "stack-trace = " + e.backtrace.join("\n")

					@status.log << e.message + "<br>"
					@status.log << e.backtrace.join("<br>") + "<br>"
				ensure
					@status.log << "DONE<br>"
					@status.str = "done"
				end
			end
		end
		
=begin
		def apply_changes(objectlist, remoteChangeList, status)
			remoteChangeList.each do |gid, change|
				$TRACE.debug 5, "applying remote changes id = #{gid}, dbID = #{change.object.dbID(store)} change = #{change}"
				case change.changeType
				when ObjectChange::ADDITION
					$TRACE.debug 1, "-- ADDING NEW OBJECT -- (#{change.newObject})"
					objectlist.push(change.newObject)
				when ObjectChange::DELETION
					$TRACE.debug 1, "-- DELETING OBJECT -- [#{gid}]"
					objectlist.delete!(change.object)
					#@objectList.delete_if {|obj| obj.dbID == id }
				when ObjectChange::MEMBER_CHANGES
					$TRACE.debug 1, "-- OBJECT MEMBER CHANGES -- [#{gid}]"
					objectlist.select{|o| o.gid == change.newObject.gid}[0].applyMemberChanges(change.memberChanges, change.old_object)
				end
			end
		end
=end

		def finish
		end

		def to_s
			@status.str
		end
	end

	class Loader
		include Singleton
		def initialize
			@tables = {}
			@new_class_procs = [
				SameTable_DeletedObjects_ObjectDatabase_object_methods.create_deleted_objects_add_table_proc, 	# add in any fields/tables necessary for deleted objects
				SameTable_LastDataStoreObjects_ObjectDatabase_object_methods.create_last_data_store_add_table_proc]		# add in any fields/tables necessary for storing last data store objects
		end

		def handle_exception(e)
			field_type = ActiveRecord::Acts::WithMetaData::Loader.instance.handle_exception(e, @new_class_procs)
			
			if e.class == ActiveRecord::Acts::WithMetaData::TableNotFoundError then
				$TRACE.debug 5, "TableNotFoundError: #{e.table_name}"
				new_table = SchemaTable.new(:name => e.table_name)
				@tables[e.table_name] = new_table
				new_table.save
			elsif e.class == ActiveRecord::Acts::WithMetaData::FieldNotFoundError then
				$TRACE.debug 5, "FieldNotFoundError: #{e.table_name}"
				schema_table = @tables[e.table_name]
				unless schema_table
					if $USE_FIND then
					schema_table = SchemaTable.find(:first, :conditions => "name = '#{e.table_name}'", :use_original => true)
					else
					schema_table = SchemaTable.find(:first, :conditions => "name = '#{e.table_name}'") #, :use_original => true)
					end
					@tables[e.table_name] = schema_table
				end
				SchemaColumn.new(:name => e.field_name.to_s, :column_type => field_type.to_s, :schema_table => schema_table).save
			end
		end
	end

	attr_reader :adapter

	def initialize(database_dir, establish_connection=true, code_dir=database_dir, adapter="sqlite3", host="localhost", username="root", password="", database_name="")
		#puts "database_dir = #{database_dir}"

		@last_store_sync_time = {}
		#ActiveRecord::Base.logger = $TRACE.logger
		#ActiveRecord::Base.default_timezone = :utc
		
		database_exists = false

		db_args = {:adapter => adapter}
		case adapter
		when "sqlite3"
			puts "tables = #{tables.inspect}"
			@database_dir = database_dir
			@database_filename = "#{database_dir}/obj.db"
			
			database_exists = File.exist?(@database_filename)
			db_args.merge!(:database => @database_filename)
		when "mysql"
			tables = ActiveRecord::Base.connection.tables.dup
			puts "tables class = #{tables.class}, inspect = #{tables.inspect}"
			database_exists = tables.include?("database_objects")
			
			db_args.merge(:host => host, :username => username, :password => password, :database => database_name)
		end

		@adapter = adapter
#puts "db_args = #{db_args.inspect}"
		@connection = ActiveRecord::Base.establish_connection(db_args) if establish_connection
		unless database_exists
			create_database
		end
		Dependencies.load_paths.push(code_dir)

		require "obdb/AR_DatabaseObject"
		require "obdb/AR_Schema"

		#scan_for_classes

		@@od = self

		ActiveRecord::Base.observers = :object_change_observer
		ActiveRecord::Base.instantiate_observers #observe(:object_changes_observer)
	end

	def disconnect
		ActiveRecord::Base.remove_connection(ActiveRecord::Base)
	end
	
	def create_database
		#puts "before migrations"
		#SchemaMigrations_Migration.migrate(:up)
		SchemaTables_Migration.migrate(:up)
		SchemaColumns_Migration.migrate(:up)
		#DataStores_Migration.migrate(:up)
		DatabaseObjects_Migration.migrate(:up)
		ObjectChanges_Migration.migrate(:up)
		MemberChanges_Migration.migrate(:up)
		#StoreIDs_Migration.migrate(:up)
		
=begin
		DBI.connect("DBI:Sqlite3:#{@database_filename}", "", "") do |dbh|
			begin
				# create data stores table
				dbh.do("create table data_stores (" +
													"id integer primary key autoincrement, " +
													"type string, " + 
													"name string," + 
													"status string, " +
													"last_sync_time datetime " +
													")")
			
			rescue DBI::DatabaseError => e
				puts "error: #{e.message}"
			end
		end
=end
	end

	def scan_for_classes
		$TRACE.debug 5, "scan_for_classes"
		ActiveRecord::Acts::WithMetaData::Loader.new(@database_dir,Dir[ "#{@database_dir}/*.rb"]).load_files(
			[create_deleted_objects_add_table_proc, 	# add in any fields/tables necessary for deleted objects
			create_last_data_store_add_table_proc]		# add in any fields/tables necessary for storing last data store objects
		)
		
#		while !rb_files.empty?
#			filename = rb_files[0]
#			ActiveRecord::Acts::WithMetaData::Loader.new(filename)
=begin
			case filename
			when /^(.*)store.rb$/i
				store_type = $1.downcase
				unless store_type == "data" 
					#if ds.find(:all, :conditions => "name = '#{$1}'")
					ds = DataStore.new
					ds.name = $1.downcase
					ds.status = "idle"
					ds.save
				end
			when /^(.*)migr.rb$/i
			else
				
			end
=end
#		end
	end

	#	synchronize the changes to a data store and local changes since last synchronization
	def synchronize_with(store, query)
	#FIXME THis is Busted. Steve said it's OK to leave this!store.connect(@sub_folder)
		store.connect
		ObjectDatabase::Synchronizer.new(store, query, self).sync
		store.disconnect
	end

	class << self
		def instance
			@@od
		end
		
		def object_change_created(object_change)
			$TRACE.debug 5, "### object change saved ###: #{object_change}"
			case object_change.change_type
			when ObjectChange::ADDITION, 
				  ObjectChange::DELETION
				@@od.notify_observers(@@od, object_change)
			when ObjectChange::MEMBER_CHANGES
				object_change.member_changes.each do |mc|
					ar_object = object_change.database_object.ar_object
					ar_object.notify_observers(ar_object, mc)
				end
			end
		end
	end
	
	def get_changes_since_last_sync(store, query)
		last_sync_time = get_last_sync_time_for_store(store)
puts "changes since last sync, for store #{store.name}, last_sync_time = #{last_sync_time}, store.inspect = #{store.inspect}"
		changes_since = ObjectChanges.changes_since(last_sync_time, :classes => store.classes)
		changes_since += ObjectDatabase.get_dynamic_objects(:classes => store.classes)
	end

	def get_dynamic_objects(classes)
		return []
		
		objects = DatabaseObject.find(:all, :conditions => "is_dynamic = t and (" + classes.map{|klass| "databaseable_object_class = '#{klass}'"}.join("or") + ")")
		objects.map do |object|
			object.generate_changes(object.last_dynamic_object, object.render)
		end
	end

	def get_last_sync_time_for_store(store)
		if $USE_FIND then
		store = DataStore.find(:first, :conditions => ["name = ?", store.name], :use_original => true)
		else
		store = DataStore.find(:first, :conditions => ["name = ?", store.name]) #, :use_original => true)
		end
		#store = DataStore.find(:first, "name = ?", store.to_s) #, :use_original => true)
		if store && store.last_sync_time then
			$TRACE.debug 5, "getting last sync time (#{store.last_sync_time.strftime('%m/%d/%Y %H:%M:%S')}) for store '#{store.to_s}'"
			store.last_sync_time
		else
			$TRACE.debug 5, "getting default last sync time for store '#{store.to_s}'"
			# use old time 
			Time.local(1980,"jan", 1,1,1,1)
		end
	end

	def detect_differences(sync, store, query, status)
		# Example:
		#   Last Time:   1     3  4  5
		#   * - changed        *  *
		#   This Time:   1  2  3  4     6

		new_object_gid = -1
		
		# Clear out changes list
		allChanges = ObjectChanges.new
		
		# Get list of objects from data store (dsList)
		dsList = store.get_objects(sync, query, status)

		#$TRACE.debug 5, "current data store list -------------------------------------"
		#dsList.each do |obj|
		#	$TRACE.debug 5, "name = #{obj.name.inspect}, notes = #{obj.notes.inspect}"
		#end


		# Get list of last stored objects from data store (ldsList)
		ldsList = get_last_data_store_objects(sync, store, query)

		#$TRACE.debug 5, "last data store list -------------------------------------"
		#ldsList.each do |obj|
		#	$TRACE.debug 5, "name = #{obj.name.inspect}, notes = #{obj.notes.inspect}"
		#end

		$TRACE.debug 5, "before: dsList = #{dsList.map{|x| x.dbID(sync, store)}.join(',')}"
		$TRACE.debug 5, "before: ldsList = #{ldsList.map{|x| x.dbID(sync, store)}.join(',')}"
		
		# Sort both by ID
		dsList.sort! { |o1, o2| o1.dbID(sync, store) <=> o2.dbID(sync, store) }
		ldsList.sort! { |o1, o2| o1.dbID(sync, store) <=> o2.dbID(sync, store) }

		$TRACE.debug 5, "after: dsList = #{dsList.map{|x| x.dbID(sync, store)}.join(',')}"
		$TRACE.debug 5, "after: ldsList = #{ldsList.map{|x| x.dbID(sync, store)}.join(',')}"

		#print "-------------------------------------------\n"	
		#print "dsList  = #{dsList.inspect}\n"		
		#print "ldsList  = #{ldsList.inspect}\n"		
		#print "-------------------------------------------\n"	

		# find the difference in the two lists of objects
		dsIndex = ldsIndex = 0
		dsObject = dsList[dsIndex]
		ldsObject = ldsList[ldsIndex]
		while dsObject != nil || ldsObject != nil

			dbID = nil; dbID = dsObject.dbID(sync, store) if dsObject
			ldbID = nil; ldbID = ldsObject.dbID(sync, store) if ldsObject
			$TRACE.debug 5, "dsList[#{dsIndex}] = dbID(#{dbID}) #{dsObject}"
			$TRACE.debug 5, "ldsList[#{ldsIndex}] = dbID(#{ldbID}) #{ldsObject}"
			
			#
			# There are 5 cases possible
			# 
			# lds  |  ds  |  comparison | meaning
			# -----|-------------------------------
			# X    |   X   |     ==      | check object for field diffences
			# X    |   X   |      >      | object was added to remote data store
			# X    |   X   |      <      | object was deleted from remote data store
			# X    |  nil  |             | object was deleted from remote data store
			# nil  |   X   |             | object was added to remote data store
			#
			# if we have both objects and the ID's are identical
			#
			if dsObject && ldsObject && dbID == ldbID then
				if dsObject != ldsObject then
					$TRACE.debug 1, "-- MEMBER_CHANGES -- (#{dsObject}) != (#{ldsObject})"
					#SAT-OBJ-CHGS
					#allChanges.push(dsObject.dbID, ObjectChange.new(ObjectChange::MEMBER_CHANGES, dsObject, dsObject.dbID, ldsObject.generateMemberChanges(dsObject)))
					#gid = get_gid_from_dbID(dsObject.dbID(store), store)
					gid = ldsObject.base_database_object.attributes["id"]
					#gid = ldsObject.id
					allChanges[gid] =  ObjectChange.new(ObjectChange::MEMBER_CHANGES, dsObject.database_object, ldsObject.generate_member_changes(dsObject), ldsObject.database_object)
				else
					$TRACE.debug 3, "-- IDENTICAL (#{dsObject})"
				end
				dsIndex += 1
				ldsIndex += 1
			else
				# if an object was added
				if (!ldsObject && dsObject) ||
				   (ldsObject && dsObject && ldbID > dbID) then
					# object was added in remote data store
					#SAT-OBJ-CHGS
					#allChanges.push(dsObject.dbID(store), ObjectChange.new(ObjectChange::ADDITION, dsObject))
					#gid = get_next_gid
					gid = new_object_gid
					new_object_gid -= 1
					allChanges[gid] = ObjectChange.new(ObjectChange::ADDITION, dsObject.database_object)
					dsIndex += 1

					$TRACE.debug 1, "-- OBJECT ADDED TO REMOTE DATA STORE -- (#{dsObject})"
					$TRACE.debug 1, "-- database_object = #{dsObject.database_object}"
					#dsObject.database_object.save
					#dsObject.save
					#$TRACE.debug 1, "-- database_object (after save) = #{dsObject.database_object}"
					#$TRACE.debug 1, "-- databaseable_object = #{dsObject.database_object.ar_object}"
		
				else # (ldsObject && !dsObject)  ||  ldsObject.dbID(store) < dsObject.dbID(store) 
					# object was deleted in remote data store
					#SAT-OBJ-CHGS
					# allChanges.push(ldsObject.dbID(store), ObjectChange.new(ObjectChange::DELETION, ldsObject))
					$TRACE.debug 5, "remote object deleted = #{ldsObject}"
					#gid = get_gid_from_dbID(ldsObject.dbID(store), store)
					gid = ldsObject.base_database_object.attributes["id"]
					#gid = dsObject.id
					allChanges[gid] = ObjectChange.new(ObjectChange::DELETION, ldsObject.base_database_object)
					ldsIndex += 1

					$TRACE.debug 1, "-- OBJECT DELETED FROM REMOTE DATA STORE -- (#{ldsObject})"
		   	end
			end

			#print "dsIndex = #{dsIndex}, ldsIndex = #{ldsIndex}\n"
			dsObject = dsList[dsIndex]
			ldsObject = ldsList[ldsIndex]
		end

		return [allChanges, dsList]
	end

	def apply_changes(sync, remoteChangeList, store, status)
		remoteChangeList.each do |gid, change|
			$TRACE.debug 5, "gid = #{gid}, change = #{change.object.class}"
			$TRACE.debug 5, "applying remote changes id = #{gid}, change = #{change}"
			case change.change_type
			when ObjectChange::ADDITION
				$TRACE.debug 1, "-- ADDING NEW OBJECT -- (#{change.new_object})"
				#push(change.newObject)
				sync.save_remote_object_locally(change.new_object.ar_object)
				$TRACE.debug 1, "-- ADDING NEW OBJECT (done) -- (#{change.new_object})"
			when ObjectChange::DELETION
				$TRACE.debug 1, "-- DELETING OBJECT -- [#{gid}][#{change.object.ar_object.dbID(sync, store)}]"
				#change.object.gid = gid
				delete(change.deleted_object.ar_object)
				#@objectList.delete_if {|obj| obj.dbID == id }
			when ObjectChange::MEMBER_CHANGES
				$TRACE.debug 1, "-- OBJECT MEMBER CHANGES -- [#{gid}][#{change.object.ar_object.dbID(sync, store)}][#{change.old_object}]"
				#change.old_object.ar_object.class.find(gid).apply_member_changes(change.member_changes, change.old_object)

				DatabaseObject.find(gid).ar_object.apply_member_changes(change.member_changes, change.old_object)
				change.old_object.save
			end
		end
	end


	def get_gid_from_dbID(dbID, store)
		database_objects = DatabaseObject.find_by_sql( 
			"select do.*,si.* " +
			"from database_objects do, store_ids si " +
			"where do.id = si.database_object_id and si.name='#{store}' and si.store_id='#{dbID}'")

		if database_objects then
			if database_objects.size == 1 then
				database_objects.first.attributes[:id]
			else
				raise "found multiple matches for dbID:#{dbID} and store:#{store} = #{database_objects.inspect}"
			end
		else
			raise "found no matches for dbID:#{dbID} and store:#{store} = #{database_objects.inspect}"
		end
	end
	
	def dump_store_ids(level=5)
		$TRACE.debug level, "---- store id's --------------------"
		#StoreID.find(:all, :use_original => true).each do |store_id|
		StoreID.find(:all).each do |store_id|
			$TRACE.debug level, "-- do_id: #{store_id.database_object_id}, name: #{store_id.name}, store_id: #{store_id.store_id} --"
		end
		$TRACE.debug level, "------------------------------------"
	end

	def dump_database_objects(klasses={},level=5, klasses_to_ignore=[])
		$TRACE.debug level, "---- dumping database objects --------------------"
		#DatabaseObject.find(:all, :use_original => true).each do |dobj|
		#if $USE_FIND then
		#database_objects = DatabaseObject.find(:all, :use_original => true)
		#else
		database_objects = DatabaseObject.find(:all)
		#end
		database_objects.each do |dobj|
			next if klasses_to_ignore.include?(dobj.databaseable_object_type)
			
			$TRACE.debug level, "-- #{dobj} ---"
			klasses[dobj.databaseable_object_type] = dobj.id
			dobj.object_changes.each do |oc|
				$TRACE.debug level, "---- #{oc} --"
				oc.member_changes do |mc|
					if $USE_FIND then
					member_changes = MemberChange.find(:all, :use_original => true)
					else
					member_changes = MemberChange.find(:all)
					end
					#MemberChange.find(:all, :use_original => true).each do |mc|
					member_changes.each do |mc|
						$TRACE.debug level, "------ #{mc} --"
					end
				end
			end
		end
		$TRACE.debug level, "--------------------------------------------------"
		klasses
	end

	def dump_real_objects(klasses, level=5)
		klasses.keys.each do |klass|
			$TRACE.debug level, "---- dumping #{klass} --------------------"
			#klass.constantize.find(:all, :use_original => true).each do |kobj|
			real_objects = nil
			if $USE_FIND then
				real_objects = klass.constantize.find(:all, :use_original => true)
			else
				real_objects = klass.constantize.find(:all)
			end
			real_objects.each do |kobj|
				$TRACE.debug level, "#{kobj.attributes['id']}::#{kobj.attributes['base_database_object_id']} - #{kobj}" + (kobj.kind_of?(DataStore) ? "" : "- store: #{kobj.store}, store_id: #{kobj.store_id} - deleted #{kobj.deleted}")
			end
			$TRACE.debug level, "------------------------------------------"
		end
	end
	
	def dump_database(level=5, klasses_to_ignore=["SchemaTable", "SchemaColumn"])
		$TRACE.debug level, "==== dumping database ===================="
		klasses = dump_database_objects({}, level, klasses_to_ignore)
		#dump_store_ids(level)

		dump_real_objects(klasses, level)		

		$TRACE.debug level, "==========================================="
	end
end

