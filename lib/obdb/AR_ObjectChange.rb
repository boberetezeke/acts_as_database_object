gem "activerecord"
require "active_record"
require "active_record/observer"
require "obdb/AR_MemberChange"
require "obdb/AR_ObjectConflict"
#require "obdb/FileObject"  this ends up including FileSystemObject which includes DatabaseObject which may end up including ObjectChange
#require "my/mytrace"
require "SortedHash"
require "obdb/AR_ObjectDatabaseFind"

#
# ObjectChange is a class that holds the type of change that has happened to an 
# object. It is one of three things:
#
# 1. it is a new object
# 2. it is a newly deleted object
# 3. it is an object whose members have changed
#
class ObjectChange < ActiveRecord::Base
	ADDITION = 1
	DELETION = 2
	MEMBER_CHANGES = 3

	CHANGE_MAP = { ADDITION => "ADDITION",
				      DELETION => "DELETION",
				      MEMBER_CHANGES => "MEMBER_CHANGES" }

	acts_with_metadata
	#extend ObjectDatabaseFind
	
	belongs_to	:database_object
	belongs_to	:old_database_object, :class_name => "DatabaseObject", :foreign_key => "old_database_object_id"
	has_many 	:member_changes
	
	#attr_reader :object, :old_object

	#
	# There are three different initialization signatures for ObjectChange objects
	#
	# initialize(ADDITION, newObject)
	# initialize(DELETION, deletedObject)
	# initialize(MEMBER_CHANGES, modifiedDatabaseObject, memberChanges, originalObject)
	#

	def initialize(change_type, *args)
		super()

		self.change_type = change_type
		if change_type == ADDITION || change_type  == DELETION then
			raise ArgumentError.new("Wrong number of arguments  (#{args.size + 1}) for ADDITION/DELETION change type") if args.size != 1
			self.database_object = args.shift
		elsif change_type == MEMBER_CHANGES then
			raise ArgumentError.new("Wrong number of arguments  (#{args.size + 1}) for MEMBER_CHANGES change type") if args.size < 1
			self.database_object = args.shift
			if args.size > 0 then
				self.member_changes = args.shift
				self.old_database_object = args.shift
			end
		else
			raise ArgumentError.new("invalid change_type (#{change_type})")
		end
		
		$TRACE.debug 5, "creating ObjectChange (#{self.object_id}) for object #{self.database_object} with change_type #{self.change_type}"
		#$TRACE.debug 5, "call stack = " + caller.join("\n")

		#@creation_time = Time.current
		self.created_datetime = Time.current
	end

	def before_create
		#self.created_datetime = @creation_time
	end

	def save
#$TRACE.debug 0, "saving an object change (#{self.object_id}) #{CHANGE_MAP[self.change_type]} for #{self.database_object}", true
		super
	end
	
	def to_s
		if self.created_datetime then
			date_time = self.created_datetime.strftime("%m/%d/%Y %H:%M:%S")
		else
			date_time = ""
		end
		"[OC: [#{date_time}] #{CHANGE_MAP[self.change_type]} - DO:#{self.database_object.attributes['id']} - #{self.member_changes}]"
	end

	def gid
		self.database_object_id
	end

	def object
		self.database_object
	end

	def change_typeStr(change_type)
		CHANGE_MAP[change_type]
	end
	
	def conflictsWith(other)
		memberConflict = nil
		objectConflict = nil
		$TRACE.debug 5, "ObjectChange#conflictsWith: [#{CHANGE_MAP[@change_type]}, #{CHANGE_MAP[other.change_type]}]"
		case [change_type, other.change_type]
		when [ADDITION, ADDITION]
			objectConflict = ObjectConflict.new(gid, ObjectConflict::ADDITION, ObjectConflict::ADDITION)
			# if the objects added are identical then auto-resolve it
	   		if @object == other.newObject then
	   			# we don't want the local change applied to remote or vice-versa
					objectConflict.resolve(ObjectConflict::USE_NEITHER)
			end
		when [DELETION, DELETION]
			# no conflict here but only one needs to be recorded
			objectConflict = ObjectConflict.new(gid, ObjectConflict::DELETION, ObjectConflict::DELETION)
			objectConflict.resolve(ObjectConflict::USE_LOCAL)
			
		when [DELETION, MEMBER_CHANGES]
			objectConflict = ObjectConflict.new(gid, ObjectConflict::DELETION, ObjectConflict::CHANGES)
			
		when [MEMBER_CHANGES, DELETION]
			objectConflict = ObjectConflict.new(gid, ObjectConflict::CHANGES, ObjectConflict::DELETION)

		else
			#when [ADDITION, anything else ?Can't happen?
			# we should handle these!
			#when [DELETION, no change]
			#when [no change, DELETION]
			# one or the other contains the old object
			if old_database_object then
				old_object = old_database_object 
			else
				old_object = other.old_database_object
			end
			$TRACE.debug 9, "old_object = #{@old_object}, other.old_object = #{other.old_object}\n"
			$TRACE.debug 9, "old_object.class = #{@old_object.class}, other.old_object.class = #{other.old_object.class}\n"
			#if old_object.class == FileObject then
			#	$TRACE.debug 9, "content.class = #{old_object.content.class}, content.tempfile = '#{old_object.content.tempfile}', content = '#{old_object.content}'\n'"
			#end
			
			memberConflicts = MemberChanges.new(self.member_changes).conflictsWith(MemberChanges.new(other.member_changes), old_object)
			if memberConflicts then
				objectConflict = ObjectConflict.new(self.database_object.attributes["id"], ObjectConflict::CHANGES, ObjectConflict::CHANGES, memberConflicts)
			end
		end

		$TRACE.debug 5, "ObjectChange#conflictsWith: objectConflict = #{objectConflict}, memberConflict = #{memberConflict}"

		return objectConflict
	end
	
	def resolve_references(object_database, store)
		case change_type 
		when ADDITION
#			$TRACE.debug 5, "ObjectChange: resolve_references for #{@memberChanges.memberChanges.size} member changes"
#			@object.resolve_references(object_database, store) if @memberChanges
		when MEMBER_CHANGES
			$TRACE.debug 5, "ObjectChange: resolve_references for #{@memberChanges.memberChanges.size} member changes"
			@memberChanges.resolve_references(object_database, store) if @memberChanges
		end
	end

	def new_object
		self.database_object
	end

	def deleted_object
		self.database_object
	end

	def changed_object
		self.database_object
	end

	def old_object
		self.old_database_object
	end

	alias oldObject old_object
	
=begin
	def ==(other)
		return false if other == nil || !other.kind_of?(self.type)
		return false if change_type != other.change_type
		return false if @object != other.object
		return true if change_type != MEMBER_CHANGES 
		return false if @gid != other.gid || @memberChanges != other.memberChanges 
		return true
	end
	
	def to_s
		"[#{CHANGE_MAP[change_type]}]:(OBJ:#{@object})(ID:#{@gid})(MC:#{@memberChanges})"
	end
=end
end


class ObjectChangeObserver < ActiveRecord::Observer
	def after_save(object_change)
		ObjectDatabase.object_change_created(object_change)
	end
end

#
# ObjectChanges is simply a sorted hash that stores ObjectChange objects key'ed by an object id
#
class ObjectChanges < SortedHash
	class << self

		CHANGES_SINCE_DEFAULTS = {
			:classes => []
		}
		def changes_since(last_sync_time, options ={})
			options = CHANGES_SINCE_DEFAULTS.merge(options)
=begin
			#changes = ObjectChange.find(:all, :conditions => "created_datetime > '#{last_sync_time.strftime('%Y-%m-%d %H:%M:%S')}'", :include => :member_changes)
			sql = "select oc.*,do.* from object_changes oc, database_objects do " + 
					"where " + 
						"oc.database_object_id = do.id AND " +
						"oc.created_datetime > '#{last_sync_time.strftime('%Y-%m-%d %H:%M:%S')}' AND " +
						"(" +
							classes.map{|klass| "(do.databaseable_object_type_as_subclass = '#{klass}')"}.join(" OR ") + 
						")"
			$TRACE.debug 5, "changes_since: sql = #{sql.inspect}"
=end
			#$do_call_stack = 10
			
			#changes = ObjectChange.find_by_sql(sql)
puts "************* BEFORE big find **************"
			classes = options[:classes]
			conditions = 
				"object_changes.created_datetime > '#{last_sync_time.strftime('%Y-%m-%d %H:%M:%S')}' " +
				(classes.empty? ? 
					"" : 
					"AND (" +
						classes.map{|klass| "(database_objects.databaseable_object_type_as_subclass = '#{klass}')"}.join(" OR ") + 
					")"
				)
puts "conditions = #{conditions.inspect}"
			changes = ObjectChange.find(
				:all, 
				#:include => [:database_object, :member_changes],
				:include => :database_object,
				:conditions => [conditions]  #,
				#:limit => options[:limit],
				#:order => options[:order]
			)
puts "************* AFTER big find *************** changes = #{changes.first.class}"
puts "change types = #{changes.map{|x| x.change_type}.join(',')}"
			$TRACE.debug 5, "changes_since(#{last_sync_time.strftime('%Y-%m-%d %H:%M:%S')}) = #{changes.size}"
			if changes.size > 0 then
				$TRACE.debug 5, "first change = #{changes.first.attributes.inspect}"
			end

			ocs = ObjectChanges.new
			
			changes.each do |x| 
				#gid = x.database_object.attributes["id"]
				gid = x.attributes["database_object_id"]
				# addition changes replace member changes, member_changes only replace emptiness
				if x.change_type == ObjectChange::ADDITION || !ocs.has_key?(gid) then
					ocs[gid] = x
				end
			end
			#changes.each {|x| ocs[x.id] = x}
change_types = []
ocs.each{|id, x| change_types.push(x.change_type)}
puts "change types = #{change_types.join(',')}"
			ocs
		end
	end
	
	def commonKeys(other)
		(keys & other.keys)
	end

	def resolve_references(object_database, store)
		$TRACE.debug 5, "ObjectChanges: resolve_references for #{values.size} values"
		values.each {|oc| oc.resolve_references(object_database, store)}
	end

	#
	# This returns an array of triplets (the type of change, the time of the change, and the change itself)
	# the changes themselves are either ObjectChange (for object deletions and addtions) or a 
	# MemberChange for changes to an object
	#
	def to_combined_changes
		changes = []
		current_addition = nil
		self.each do |id, oc|
			case oc.change_type
			when ObjectChange::ADDITION
				changes.push([oc.change_type, oc.created_datetime, oc])
				current_addition = oc.database_object
				puts "ADDITION: #{oc.created_datetime}"
			when ObjectChange::DELETION
				changes.push([oc.change_type, oc.deleted_datetime, oc])
			when ObjectChange::MEMBER_CHANGES
				#puts "MEMBER CHANGE: #{oc.database_object.attributes['id']}"
				if current_addition != oc.database_object then
					oc.member_changes.each do |mc|
						changes.push([oc.change_type, mc.change_time, mc])
					end
				end
				current_addition = nil
			end
		end
		changes
	end
	
	def to_s
		str = ""
		each do |gid, objectChange|
			str += "[#{gid} => #{objectChange}]\n"
		end
		str
	end
end

