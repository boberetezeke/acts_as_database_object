#require "my/mytrace"
require "obdb/AR_MemberConflict"
require "obdb/AR_SimpleChange"
require "acts_with_metadata"
require "obdb/AR_ObjectDatabaseFind"

=begin
class ObjectChange < ActiveRecord::Base
	ADDITION = 1
	DELETION = 2
	MEMBER_CHANGES = 3
	
	acts_with_metadata
	has_many :member_changes
	belongs_to :database_object

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
				old_database_object = args.shift
			end
		else
			raise ArgumentError.new("invalid change_type (#{change_type})")
		end
	end
end

class MemberChange < ActiveRecord::Base
	acts_with_metadata
	belongs_to :object_change
end
=end

#
# MemberChange details a change to an object member. It records the member naem
# (as a string), the time of the change, and the change itself.
#
class MemberChange < ActiveRecord::Base
	#attr_reader :member, :time, :oldValue, :newValue
	#attr_reader :member, :time, :change
	#attr_reader :classname

	acts_with_metadata
	#extend ObjectDatabaseFind
	
	#include ObjectInfoInstance
	#extend  ObjectInfoClass

	display_name "Member Change"
	#object_info ({ :printName => "Member Change" })

	has_field :member
	
	#member_info :member, 	
	#					{ 	:printName => "Member",
	#						:printFormat => "%s",
	#						:type => Symbol
	#					}

	has_field :change_time
	#member_info :time, 	
	#					{ 	:printName => "Change Time",
	#						:printFormat => "%s",
	#						:type => Time
	#					}
if $USE_CHANGE_VALUE then
	has_field :change_value
	serialize :change_value
else
	has_field :change
	serialize :change
end

	#has_field :change
	#member_info :change, 	
	#					{ 	:printName => "Change",
	#						:printFormat => "%s",
	#						:type => SimpleChange
	#					}


	belongs_to :object_change
	
	#
	# initialize(memberChange) - duplicate memberChange
	# initialize(member, time, change) - change happened to member at time
	#
	def initialize(*args)
		super()

		$TRACE.debug 9, "MemberChange::Initialize: #{self.inspect}"
		#@classname = self.class.to_s
		# (member_change)
		if args.size == 1 then
			memberChange = args.shift
			self.member = memberChange.member.dup
			self.time = memberChange.time.dup
			#@oldValue = memberChange.oldValue
			#@newValue = memberChange.newValue
if $USE_CHANGE_VALUE then
			self.change_value = memberChange.change.dup
else
			self.change = memberChange.change.dup
end
		#elsif args.size == 4 then
		
		# (member, time, change, object_change)
		elsif (3..4).include?(args.size) then
			#@member, @time, @oldValue, @newValue = args
			self.member = args.shift.to_s
			self.change_time = args.shift
if $USE_CHANGE_VALUE then
			self.change_value = args.shift
else
			self.change = args.shift
end
			unless args.empty?
				self.object_change = args.shift
			end
			#@member, @time, @change = args
		end

		# if @member is a string, then convert it to a symbol
		# (symbol_string)
		if @member.kind_of?(String) then
			self.member = @member.intern
		end
	end

	def change_value
		# reload the record if the change value was not initially loaded
		unless self.attributes["change_value"]
			self.reload
		end

		return self.attributes["change_value"]
	end

	def to_s
		time_str = self.change_time ? self.change_time.strftime("%m/%d/%Y %H:%M") : "(no time set)"
		
if $USE_CHANGE_VALUE then
		# if the attributes contain change_value
		if self.attributes["change_value"] then
			change_value_class = self.change_value.class
			change_value_str = self.change_value
		else
			change_value_class = "not loaded"
			change_value_str = "not loaded"
		end
		"[MC:#{self.member}: #{time_str} - #{change_value_class}:#{change_value_str}]"
else
		"[MC:#{self.member}: #{time_str} - #{self.change.class}:#{self.change}]"
end
	end
	
	def member
		read_attribute("member").intern
	end

	def member=(m)
		write_attribute(:member, m.to_s)
	end

	def time
		self.change_time
	end
	
	#
	# determine if our change conflicts with other's change
	# return a MemberConflict object if so, nil if not
	#
	def conflictsWith(other, orig_value)
if $USE_CHANGE_VALUE then
		conflict = self.change_value.conflictsWith(other.change_value, orig_value)
else
		conflict = self.change.conflictsWith(other.change, orig_value)
end
		if conflict then
			m =  MemberConflict.new(self.member, conflict)
			# print "MemberChange#conflictsWith: m = #{m.inspect}\n"
			m
		else
			return nil
		end
	end

	#
	# resolve any references if the change requires that
	#
	def resolve_references(object_database, store)
		@change.resolve_references(object_database, store) if @change.respond_to?(:resolve_references)
	end
	
	# duplicate thy self
	def dup
		MemberChange.new(self)
	end

	def ==(other)
		return false if other == nil || !other.kind_of?(self.class)
		return false if self.member != other.member
		return false if self.time != other.time
if $USE_CHANGE_VALUE then
		return false if @change != other.change_value
else
		return false if self.change != other.change
end
		return true
	end

	# combine changes to member letting change object resolve conflicts
	def combine(memberChange)
if $USE_CHANGE_VALUE then
		MemberChange.new(self.member, self.change_time, self.change.combine(memberChange.change), nil)
else
		MemberChange.new(self.member, self.change_time, self.change_value.combine(memberChange.change_value), nil)
end
	end
	
	#def to_s
	#	"[M:#{@member}][T:#{@time}][C:#{change}]"
	#end
end

# 
# MemberChanges contains the creation time of an object, a list of changes (MemberChanges) to an object,
# and possibly the deletion time of an object if it was just deleted. 
#
#module MemberChangesMixin
class MemberChanges < Array
	#attr_accessor :creationTime, :deletionTime
	#attr_reader :memberChanges

	#include ObjectInfoInstance
	#extend ObjectInfoClass

	#object_info ({ :printName => "Member Changes" })

	#member_info :creationTime, 	
	#					{ 	:printName => "Creation Time",
	#						:printFormat => "%s",
	#						:type => Time
	#					}

	#member_info :deletionTime, 	
	#					{ 	:printName => "Deletion Time",
	#						:printFormat => "%s",
	#						:type => Time
	#					}

	#member_info :memberChanges, 	
	#					{ 	:printName => "Member Changes",
	#						:printFormat => "%s",
	#						:type => Array,
	#					}

	#
	# initialize()
	# initialize(MemberChanges)
	#
	#def initialize(*args)
	#	@deletionTime = nil
	#	@creationTime = nil
	#	if args.size == 0 then
	#		@memberChanges = []
	#	elsif args.size == 1 && args[0].kind_of?(MemberChanges) then
	#		mc = args.shift
	#		@creationTime = mc.creationTime
	#		@deletionTime = mc.deletionTime
	#		@memberChanges = mc.memberChanges.dup
	#	else
	#		raise ArgumentError.new("Wrong number of arguments")
	#	end
	#end

	#
	def to_s
		"MCS(#{self.size}): " + self.map{|m| m.to_s}.join(",")
	end

	def +(other)
		MemberChanges.new(super(other))
	end
	
	#
	# combine the changes to the same members so for example
	# if member :a changed from 1 to 2 and then 2 to 3, then
	# after this is done there would only exist a change from
	# 1 to 3.
	#
	def combine_like_changes
		like_changes = {}
		self.sort_by{|x| x.time}.each do |mc|
			if like_changes.has_key?(mc.member) then
				like_changes[mc.member] = like_changes[mc.member].combine(mc)
			else
				like_changes[mc.member] = mc
			end
		end

		self.replace(like_changes.values)
	end
	
	#
	# returns MemberConflicts object if this change conflicts with another MemberChange
	#
	def conflictsWith(other, old_object)
		cm = commonMembers(other)
		if cm == [] then
			return nil
		else
			if $NEW_RESOLVE then
				memberConflicts = MemberConflicts.new(cm.size)
			else
				memberConflicts = MemberConflicts.new
			end
			cm.each do |member|
				mc = memberConflict(member).conflictsWith(other.memberConflict(member), old_object.ar_object.send(member))
				# if the change was not identical
				if mc then
					memberConflicts.push(mc)
				end
			end

			# if there were no real conflicts added to the MemberConflicts object
			if memberConflicts.size == 0 then
				# return no conflict
				return nil
			else
				# return the built up MemberConflicts object
				return memberConflicts
			end
		end
	end

	#
	# Returns members that are common to this object and the other MemberChanges object
	#
	def commonMembers(other)
		self.map{|mc| mc.member} & other.map{|omc| omc.member}
	end

	#
	# Return the member conflict object associated with the passed in member
	#
	def memberConflict(member)
		self.select{|mc| mc.member == member}[0]
	end

	#
	# clear out num_changes changes starting with the latest change
	#
	def clear(num_changes)
		if num_changes == -1 then
			self.clear
		else
			end_index = ((@memberChanges.size-num_changes)-1)
			if end_index == -1 then
				self.clear
			else
				self.replace(self.sort{|a,b| a.time <=> b.time}[0..end_index])
			end
		end
	end

	#
	# for each MemberChange resolve any references contained in it
	#
	def resolve_references(object_database, store)
		self.each {|mc| mc.resolve_references(object_database, store)}
	end
	
=begin
	#
	# add a member change
	#
	def push(memberChange)
		$TRACE.debug 7, "MEMBER_CHANGE:PUSH, memberChange = #{memberChange}"
		@memberChanges.push(memberChange)
		@memberChanges.sort! {|x,y| x.member.to_s <=> y.member.to_s }
	end

	# duplicate thy self
	def dup
		MemberChanges.new(self)
	end

	#
	# yield each MemberChange
	#
	def each
		@memberChanges.each do |m|
			yield m
		end
	end

	# number of MemberChanges
	def size
		@memberChanges.size
	end

	# index the MemberChanges
	def [](index)
		return @memberChanges[index]
	end
	
	def sortByTime
		#print "Before sort\n"
		#@memberChanges.each {|m| print "m.member = #{m.member}, #{m.time}\n"}
		@memberChanges.sort! do	|x,y| 
			if x.time == y.time then
				x.member.to_s <=> y.member.to_s
			else
				x.time <=> y.time
			end
		end

		#print "After sort\n"
		#@memberChanges.each {|m| print "m.member = #{m.member}, #{m.time}\n"}
		self
	end

	def reverse
		@memberChanges.reverse!
		self
	end

	def ==(other)
		return false if other == nil || !other.kind_of?(self.type)
		return false if @creationTime != other.creationTime
		return false if @deletionTime != other.deletionTime
		return false if  @memberChanges == nil
		return false if size != other.size
		for i in 0..size-1
			return false if @memberChanges[i] != other[i]
		end
		return true
	end

	def to_s
		str  = "[C:#{@creationTime}][D:#{@deletionTime}][MC:"
		@memberChanges.each do |mc|
			str += "(#{mc})"
		end
		str += "]"
		str
	end
=end
end

