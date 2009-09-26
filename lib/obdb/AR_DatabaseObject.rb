gem "activerecord"
require "active_record"
require "obdb/AR_ObjectChange"
require "obdb/AR_MemberChange"
require "obdb/AR_SimpleChange"
require "obdb/AR_Builtins"
require "obdb/AR_ObjectDatabaseFind"

#require "obdb/AR_StoreID"

class ActiveRecord::Errors
	attr_accessor :base
end

class History
	class Ancestor
		attr_reader :obj, :num_versions
		attr_accessor :range
		def initialize(obj, num_versions, range=nil)
			@obj = obj
			@num_versions = num_versions
			@range = range
		end

		def to_s
			"[obj=#{obj},num_versions=#{num_versions},range=#{range}"
		end
	end

	class Ancestry < Array
		def fill_in_ranges
			range_start = 1
			self.each do |ancestor|
				ancestor.range = range_start..(range_start+ancestor.num_versions-1)
				range_start += ancestor.num_versions
			end
			self
		end
	end
	
	attr_reader :creation_time, :member_changes
	
	def initialize(creation_time, member_changes, ancestry)
		@creation_time = creation_time
		@member_changes = member_changes
		@ancestry = ancestry
		$TRACE.debug 5, "member_changes = #{member_changes}"
		$TRACE.debug 5, "object changes = #{member_changes.map{|mc| mc.object_change}.uniq.map{|oc| oc.to_s}.join(',')}"
	end

	def size
		@member_changes.size
	end

	def sort_by_time
		#$TRACE.debug 5, "@changes before sorting = #{@changes.inspect}"
		@member_changes = @member_changes.sort_by{|x| x.change_time}
		self
	end

	def reverse
		@member_changes.reverse!
		self
	end
	
	def[](index)
		@member_changes[index]
	end

	def creationTime
		@creation_time
	end

	def ancestry
		Ancestry.new(@ancestry).fill_in_ranges
	end
	
	def to_s
		"[created: " + @creation_time.strftime("%d/%m/%Y %H:%M:%S") + ", changes: " +  @member_changes.map{|mc| mc.to_s}.join(",") + ", ancestry=#{self.ancestry}]"
	end
end

class DatabaseObject < ActiveRecord::Base
	acts_with_metadata
	#extend ObjectDatabaseFind

	belongs_to :databaseable_object, :polymorphic => true

	# AR_LastDataStoreObjects
	# has_many :store_database_objects, :polymorphic => true
	
	#has_many :store_ids, :class_name => "StoreID"
	has_many	:object_changes
	has_many :member_changes, :through => :object_changes
	acts_as_tree

	class << self
		# 
		# return whether we are tracking changed attributes for all database objects
		#
		def track_changed_attributes
			if @track_changed_attributes.nil? then
				@track_changed_attributes = true
			end
			@track_changed_attributes
		end

		# 
		# change whether we will track changed attributes for all database objects
		#
		def track_changed_attributes=(val)
			@track_changed_attributes = val
		end

		def create_do(klass, id, databaseable_object)
			database_object = DatabaseObject.new(klass, id, databaseable_object)
			#$TRACE.debug 0, "in AR_DatabaseObject:create_do:  id = #{'0x%8.8x' % database_object.object_id}, database_object.databaseable_object_type = #{database_object.databaseable_object_type}, inspect = #{database_object.inspect}"
			database_object
		end

		def find_do(klass, id)
			if $USE_FIND then
			DatabaseObject.find(:first, :conditions => "databaseable_object_type = '#{klass}' and databaseable_object_id = #{id}", :use_original => true)
			else
			DatabaseObject.find(:first, :conditions => "databaseable_object_type = '#{klass}' and databaseable_object_id = #{id}") #, :use_original => true)
			end
		end
	end
	
	def initialize(klass, id=nil, databaseable_object=nil)
		super()

		self.real_creation_time = Time.current
		self.databaseable_object_type = klass.to_s
		self.databaseable_object_type_as_subclass = klass.to_s
		self.databaseable_object_id = id
		self.current_version_num = 0
		@databaseable_object_in_memory = databaseable_object
	end

	def set_unversioned
		@unversioned = true
	end
	
	def ar_object
		#self.databaseable_object || @databaseable_object_in_memory
		if self.databaseable_object_id && (obj = self.databaseable_object_type_as_subclass.constantize.find(self.databaseable_object_id))
			return obj
		else
			@databaseable_object_in_memory
		end
	end
	
	def has_changed_since(ar_database_object, time)
		changes_since_time = ar_database_object.history.sort_by_time.member_changes.select{|mc| mc.change_time > time}
		!changes_since_time.empty?
	end


	# this hack allows pp (pretty print not to die when printing out the contents of this object)
	# the @parent object is created after the ancestors call
	def clear_parent_hack_after_ancestors_call
		@errors.base.clear_parent if $running_unit_tests if @errors
	end
	
	# this allows us the ability to clear the @parent instance variable
	def clear_parent
		@parent = nil
	end
	
	def history(changed_attributes=[])
		$TRACE.debug 3, "history: changed_attributes=#{changed_attributes.inspect}"
		member_changes = all_member_changes(changed_attributes)
		$TRACE.debug 3, "leaf member changes = #{member_changes}, parent=#{self.parent}:v#{self.parent_version_num}"
		root = self
		ancestry = [History::Ancestor.new(self,member_changes.size)]
		self.ancestors.each do |ancestor|
			node_member_changes = ancestor.all_member_changes([], root.parent_version_num)
			$TRACE.debug 3, "node member changes = #{node_member_changes}, parent version num = #{root.parent_version_num}"	
			member_changes = node_member_changes + member_changes
			root = ancestor
			$TRACE.debug 3, "all member changes = #{member_changes}"	
			ancestry.insert(0, History::Ancestor.new(ancestor, node_member_changes.size))
		end

		
		h = History.new(root.real_creation_time, member_changes, ancestry)
		$TRACE.debug 3, "history, ret = #{h}"

		clear_parent_hack_after_ancestors_call

		h
	end

	def all_member_changes(changed_attributes=[], num_changes=-1)

		$TRACE.debug 5, "in all_member_changes, id = #{self.id}"
=begin
		DatabaseObject.find(:all).each do |doobj|
			$TRACE.debug 5, "ar #{doobj.databaseable_object_id} do: #{doobj.id}"
		end		
		ObjectChange.find(:all).each do |oc|
			$TRACE.debug 5, "ar #{oc.database_object.databaseable_object_id} do: #{oc.database_object.id} oc: #{oc.id}"
		end
		MemberChange.find(:all).each do |mc|
			$TRACE.debug 5, "ar #{mc.object_change.database_object.databaseable_object_id} do: #{mc.object_change.database_object.id} oc: #{mc.object_change.id}, member: #{mc.member}, change: #{mc.change}"
		end
=end
		#$od.dump_database
		
		# get saved member changes
#		$TRACE.debug 5, "before get member_changes"
#puts caller.join("\n")
#set_trace_func proc { |event, file, line, id, binding, classname|
#	printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
#}
		#mcs = self.member_changes(true)	# this no longer works in active record 1.15.3
		mcs = MemberChanges.new	# start with a fresh array (not a proxied active record array
		self.member_changes(true).each{|mc| mcs.push(mc)} # and push the changes onto it
		mcs.sort!{|a, b| a.id <=> b.id}
		
#set_trace_func nil
		s = member_changes.size
=begin
		$TRACE.debug 5, "all_member_changes: member_changes.size = #{member_changes.size}, object_changes.size = #{object_changes.size}"
		object_changes.each do |oc|
			$TRACE.debug 5, "oc: id: #{oc.id} type: #{oc.change_type}, num_changes: #{oc.member_changes.size}"
			oc.member_changes.each do |mc|
				$TRACE.debug 5, "ar #{mc.object_change.database_object.databaseable_object_id} do: #{mc.object_change.database_object.id} oc: #{mc.object_change.id}, mc: #{mc.id} member: #{mc.member}, change: #{mc.change}"
			end
		end
=end

		# add on unsaved changes
		$TRACE.debug 5, "changed_attributes = #{changed_attributes.inspect}, member_changes = #{mcs.inspect}"
		$TRACE.debug 5, "changed_attributes.size = #{changed_attributes.size}, member_changes.size = #{mcs.size}"
		changed_attributes.each {|ca| mcs.push(MemberChange.new(ca.name, ca.time, SimpleChange.new(ca.old_value, ca.new_value), nil))}
#		changed_attributes.each do |ca| MemberChange.new(ca.name, ca.time, SimpleChange.new(ca.old_value, ca.new_value), nil)
#			mc = MemberChange.new(ca.name, ca.time, SimpleChange.new(ca.old_value, ca.new_value), nil)
#			oc = ObjectChange.new(ObjectChange::MEMBER_CHANGES, self)
#			oc.member_changes << mc
#			mc.save
#			oc.save
#		end
		$TRACE.debug 5, "after member_changes.size = #{mcs.size}"
		
		mcs[0..(num_changes < 0 ? num_changes : num_changes-1)]
	end

	def save_version(changed_attributes)
		return if @unversioned		# if this is an unversioned object, then we don't save any changes for it
		
		object_change = ObjectChange.new(ObjectChange::MEMBER_CHANGES, self)
		#object_change.save
		mcs = []
		changed_attributes.each do |ca|
			$TRACE.debug 5, "creating member change for '#{ca.name}' at time #{ca.time} from <#{ca.old_value.inspect}> to <#{ca.new_value.inspect}>"
			#mc = MemberChange.new(ca.name, ca.time, SimpleChange.new(ca.old_value, ca.new_value))
			mc = MemberChange.new(ca.name, ca.time, ca.old_value.generate_changes(ca.new_value))
			$TRACE.debug 9, "new member change = #{mc.inspect}"
			#mc = MemberChange.new(ca.name, ca.time, SimpleChange.new(ca.old_value, ca.new_value), object_change)
			##mc = MemberChange.new("name", Time.now, "", object_change)
			#mc.save
			self.current_version_num += 1
			#self.save
			object_change.member_changes << mc
		end
		object_change.save

		self.save
		#MemberChange.find(:all).each do |mc|
		#	$TRACE.debug 5, "ar #{mc.object_change.database_object.databaseable_object_id} do: #{mc.object_change.database_object.id} oc: #{mc.object_change.id}, member: #{mc.member}, change: #{mc.change}"
		#end
	end

	def save_version_on_create(id)
		return if @unversioned		# if this is an unversioned object, then we don't save any changes for it
		return if self.current_version_num != 0 && !self.parent
		
		self.databaseable_object_id = id
		ret = self.save
		$TRACE.debug 5, "after save, ret = #{ret.inspect}, self.databaseable_object_id = #{self.databaseable_object_id}, self.databaseable_object_type = '#{self.databaseable_object_type}'"
		
		# create an entry in object_changes table
		oc = ObjectChange.new(ObjectChange::ADDITION, self)
		oc.save
	end


	#def ar_object
	#	Object.const_get(self.databaseable_object_type).find(self.databaseable_object_id)
	#end
	
	def dup
		new_do_object = DatabaseObject.new(self.databaseable_object_type)
		new_do_object.parent = self
		new_do_object.parent_version_num = self.current_version_num
		$TRACE.debug 3, "(dup): for self=#{self.object_id}:#{self.id}:#{self} - current version num = #{self.current_version_num}"
		new_do_object
	end

	def get_version(ar_object, changed_attributes,*args)
		# get a list of changes in reverse time order
		history = self.history(changed_attributes).sort_by_time.reverse
		cur_version = history.size

		# process the extra arguments either (time) or (version number)
		if args.size == 1 
			arg = args.shift
			if arg.kind_of?(Time) then
				time = arg
			elsif arg.kind_of?(Fixnum) then
				version = arg
				raise ArgumentError.new("zero is not a valid version") if version == 0
				raise ArgumentError.new("#{cur_version} is the latest version") if version > cur_version + 1  # cur_version is zero based
				# positive versions are one based
				#if version > 0 then
				#	version -= 1		# but need to be adjusted for below
				#end
				# negative versions are so many versions backwards
			else
				raise ArgumentError.new("invalid argument type (#{arg.type}), must be Time or Fixnum")
			end
		else
			raise ArgumentError.new("wrong # of arguments")
		end

		# convert negative version into positive version
		if version && version < 0 then
			if cur_version + version < 0 then
				raise "back too many versions, only #{cur_version} versions available not #{-version} versions"
			end
			version = cur_version + version
		end


		# find the ancestor that we want to modify
		ancestor = history.ancestry.select {|a| a.range.include?(version)}.first
		$TRACE.debug 5, "selected ancestor #{ancestor} with version (#{version}) from #{history.ancestry}"
		# if the ancestor is the ar_object
		if ancestor && ancestor.obj != ar_object.database_object then
			$TRACE.debug 5, "starting object(node) = #{ancestor.obj}"
			new_ar_object = ancestor.obj.databaseable_object(true).dup
			history = ancestor.obj.history.sort_by_time.reverse
			cur_version = history.size
		else
			$TRACE.debug 5, "starting object(leaf) = #{self}"
			new_ar_object = ar_object.dup
		end

		$TRACE.debug 5, "-------- changes ------------------"
		history.member_changes.each do |change|
			$TRACE.debug 5, "change = #{change}"
		end
		# if we have no ancestor, then we can un-apply the unsaved changes to self
		# if we have an ancestor, then we just loaded that ancestor off of disk and unsaved changes weren't applied to it
		if !ancestor then
			$TRACE.debug 5, "------- unsaved changes -----------"
			new_ar_object.changed_attributes.each do |ca|
				$TRACE.debug 5, "unsaved change = #{ca}"
			end
		end


		# suspend change recording while we build the older version
		new_ar_object.stop_recording_changes		
		#new_ar_object.clear_changed_attributes

		# gather up changes based on time or version
		changes_processed = 0
		memberChanges = MemberChanges.new
		history.member_changes.each do |mc|
			$TRACE.debug 5, "cur_version = #{cur_version}, version = #{version}\n"
			$TRACE.debug 5, "change = #{mc}"
			break if time && mc.time < time					# if we are constructing by time and we are before the time then break
			break if version && version >= cur_version			# if we are construction by version and we have reached the version we want then break
			memberChanges.push(mc)
			cur_version -= 1
			changes_processed += 1
		end

		# combine the like changes
		$TRACE.debug 5, "before combineLikeChanges = #{memberChanges.size}\n"
		memberChanges.combine_like_changes
		$TRACE.debug 5, "after combineLikeChanges = #{memberChanges.size}\n"

		# apply the changes now
		memberChanges.each do |mc|
			# reverse the change (figure out new_value from old_value and the change)
			member_str = mc.member.to_s
			old_value = new_ar_object.send(member_str)
			new_value = mc.change.reverse_change(old_value)

			# we are going back further into the parent's history
			new_ar_object.database_object.parent_version_num -= 1
			
			# set the change in the new object
			$TRACE.debug 3, "changing #{member_str} from #{old_value.class}:#{old_value} to #{new_value.class}:#{new_value}"
			new_ar_object.send(member_str+"=", new_value)
		end

		# reenable change recording
		new_ar_object.start_recording_changes		

		# no need to do this because the dupped entry won't include history beyond the version it was
		# dupped from the source object
		# take off the history entries that no longer apply to this object
		#new_ar_object.clear_history(changes_processed)

		clear_parent_hack_after_ancestors_call

		$TRACE.debug 5, "versioned object = #{new_ar_object}"
		
		# return the new object
		new_ar_object		
	end

	def generate_member_changes(ar_database_object, other_object)
		ar_database_object.real_object.generate_member_changes(other_object.ar_object)
	end

	#alias :generateMemberChanges :generate_member_changes 

	def apply_member_changes(ar_database_object, member_changes, old_object)
		$TRACE.debug 5, "for object [#{ar_database_object.id}], applying memberChanges: #{member_changes.inspect}"

		# then apply changes
		member_changes.each do |member_change|
			$TRACE.debug 5, "member_change = #{member_change.inspect}"
			if member_change.change.is_differential then
				old_value = old_object.ar_object.send(member_change.member.to_s)
				ar_database_object.send(member_change.member.to_s + "=", member_change.change.apply_change(old_value))
				#new_value = ar_database_object.send(member_change.member.to_s )
			else
				ar_database_object.send(member_change.member.to_s + "=", member_change.change.newValue)
			end
			#notify_observers(self, member_change)
		end
		
		ar_database_object.save		
		return true
	end
	
=begin
	class << self
		def clear_local_dbIDs
			@@local_dbID_hash = nil
		end
		
		def local_dbID(id_str)
			@@local_dbID_hash ||= {}
			obj = @@local_dbID_hash[id_str]
			raise "unable to find object associated with #{id_str}" unless obj
			return obj
		end
	end

	def resolve_dbID()
		# get the dbID from the object_id and then replace its value with the object's database id
		dbID = @@local_dbID_hash.invert[self.object_id]
		@@local_dbID_hash[dbID] = self.attributes["id"]
#begin
		$TRACE.debug 5, "resolve_dbID: store:#{store}, local_dbID_hash:#{@@local_dbID_hash.inspect} for #{self}"
		dbID = @@local_dbID_hash[self.object_id]
		$TRACE.debug 5, "object id = #{self.object_id} and dbID = #{dbID} and id = #{self.attributes['id']}"
		@@local_dbID_hash.delete(self.object_id]
		@@local_dbID_hash[self.attributes["id"]] = dbID
#end
	end

#	def local_dbID(id_str)
#		@@local_dbID_hash ||= {}
#		obj = @@local_dbID_hash[id_str]
#		raise "unable to find object associated with #{id_str}" unless obj
#		return obj
#begin
#		$TRACE.debug 5, "local_dbID: store:#{store}, local_dbID_hash:#{@@local_dbID_hash.inspect} for #{self}"
#		id = self.object_id
#		$TRACE.debug 5, "id = #{id}"
#		if @@local_dbID_hash && @@local_dbID_hash[id] then
#			@@local_dbID_hash[id][store.to_s]
#		else
#			nil
#		end
#		#if @store_ids then
#		#	@store_ids[store.to_s]
#		#else
#		#	nil
#		#end
#end
#	end
	
	def set_local_dbID(id_str)
		@@local_dbID_hash ||= {}
		id = self.attributes["id"] || self.object_id
		@@local_dbID_hash[id_str] = id
		
#begin
#		@store_ids ||= {}
#		@store_ids[store.to_s] = id_str
		id = self.attributes['id'] || self.object_id
		$TRACE.debug 5, "set_dbID: store:#{store}, dbID:#{id_str} for #{id}"
		@@local_dbID_hash ||= {}
		$TRACE.debug 5, "set_dbID: before (#{@@local_dbID_hash.inspect})"
		@@local_dbID_hash[id] ||= {}
		@@local_dbID_hash[id][store.to_s] = id_str
		$TRACE.debug 5, "set_dbID: after (#{@@local_dbID_hash.inspect})"
#end

#begin
		$od.dump_store_ids
		$TRACE.debug 5, "setting dbID for #{self.ar_object}, store=#{store}, id_str=#{id_str}"
		db_ids_for_store = self.store_ids.select{|x| x.name == store.to_s}
		raise "database problem: multiple store_id entries for store '#{store}'" if db_ids_for_store.size > 1
		if db_ids_for_store.empty? then
			$TRACE.debug 5, "no store dbID saved, so create new one"
			new_store_id = StoreID.new(:name => store.to_s, :store_id => id_str)
			#new_store_id.save
			self.store_ids << new_store_id
		else
			$TRACE.debug 5, "update existing store dbID from #{db_ids_for_store.first.store_id} to #{id_str}"
			db_ids_for_store.first.store_id = id_str
			db_ids_for_store.first.save
		end
		$od.dump_store_ids
#end
	end

	def dbID(store)
#begin
		$TRACE.debug 5, "get dbID: store:#{store}, local_dbID_hash:#{@@local_dbID_hash.inspect} for #{self}"
		if @@local_dbID_hash then
			id = self.attributes["id"] || self.object_id
			if @@local_dbID_hash[id] then
				dbID = @@local_dbID_hash[id][store.to_s]
				$TRACE.debug 5, "dbID #{dbID.inspect} by using [#{id}] for local_dbID_hash = #{dbID.inspect}"
				return dbID if dbID
			end
			id = self.object_id
			if @@local_dbID_hash[id] then
				dbID = @@local_dbID_hash[id]
				$TRACE.debug 5, "dbID #{dbID.inspect} by using [#{id}] for local_dbID_hash = #{dbID.inspect}"
				return dbID if dbID
			end
		end
#end

		sql = "select store_id from #{self.databaseable_object_type.tableize} where base_database_object_id=#{self.attributes['id']} and store='#{store.to_s}'"		
		$TRACE.debug 5, "running sql: #{sql}"
		ar_objects = self.databaseable_object_type.constantize.find_by_sql(sql)
		if ar_objects.size == 0 || ar_objects.size > 1 then
			raise "too many or too few objects (#{ar_objects.size}) from #{self.databaseable_object_type.tableize} for id=#{self.attributes['id']} and store=#{store}"
		else
			return ar_objects[0].store_id
		end
#begin
		$TRACE.debug 5, "store ids for self(#{self.id}) is #{self.store_ids.inspect}"
		matching_store_ids = self.store_ids.select{|x| x.name == store.to_s}
		return nil if matching_store_ids.empty?
		matching_store_ids.first.store_id
#end
	end
	#alias :applyMemberChanges :apply_member_changes 
=end

	def to_s
		"#{self.object_id}:#{self.id}#{self.parent ? ':par:' + self.parent_id.to_s + ':pver:'+self.parent_version_num.to_s : ''}:ver:#{self.current_version_num} ::: real: #{self.databaseable_object_type}:#{self.databaseable_object_id}:#{self.ar_object}"
	end
end

=begin
class DatabaseObjectObserver < ActiveRecord::Observer
	def after_save(obj)
	end

	def after_create(obj)
		@added_objects.push(obj)
	end
end
=end

class ActiveRecord::Base
	def duplicate
		new_object = self.class.new
		attributes.each do |attr|
			new_object.write_attribute(attr, read_attribute(attr))
		end

		new_object
	end
end
