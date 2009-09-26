require "SortedHash"
require "obdb/AR_ObjectChange"

#
# An ObjectConflict details how changes to an object conflict with each other.
# An object change can conflict with each other in 5 possible ways (see below):
#
#                    Addition           Deletion           Change
#             +----------------------+-----------------+---------------+
# Addition    | if new objects are   |   N / A         |    N / A      |
#             | not the same         |                 |               |
#             |----------------------+-----------------+---------------+
# Deletion    |       N / A          | No              | Yes           |
#             |                      |                 |               |
#             |----------------------+-----------------+---------------|
# Change      |       N / A          | Yes             | if members    |
#             |                      |                 | conflict      |
#             +----------------------+-----------------+---------------+
#
# The N/A's are because the objects are derived from an original object source
# that are periodically synchronized to, so it is not possible for an object
# in one place to be added (it has to already exist to be compared at all)
# and in another to be changed or deleted.
#
class ObjectConflict
	# this set of constants is for the type of change that occured in one place 
	# (local or remote)
	ADDITION = 1
	DELETION = 2
	CHANGES = 3

	CHANGE_MAP = { ADDITION => "ADDITION", DELETION => "DELETION", CHANGES => "CHANGES" }
	
	# this set of constants is used to determine how the conflict is to be resolved
	#
	USE_LOCAL = 1
	USE_REMOTE = 2
	MEMBER_RESOLUTION = 3
	USE_NEITHER = 4

	RESOLUTION_MAP = { USE_LOCAL => "USE_LOCAL", USE_REMOTE => "USE_REMOTE", MEMBER_RESOLUTION => "MEMBER_RESOLUTION", USE_NEITHER => "USE_NEITHER"}
	
	attr_reader :gid, :localChange, :remoteChange, :memberConflicts
	
	def initialize(gid, localChange, remoteChange, *args)
		@gid, @localChange, @remoteChange = gid, localChange, remoteChange
		@resolution = nil
		
		if localChange == CHANGES && remoteChange == CHANGES then
			if args.size != 1 || (@memberConflicts = args.shift).kind_of?(MemberConflict) then
				raise ArgumentError.new("need one MemberConflict object argument")
			end

			# let the member conflicts know who their parent is
			@memberConflicts.objectConflict = self
		else
			if args.size != 0 then
				raise ArgumentError.new("too many arguments")
			end
		end
	end

	# 
	# This indicates whether the user wants to accept the local or remote
	# changes. This does not apply to conflicts that are at the member level.
	# The only resolutions this is resolving are:
	#
	#   ADDITION, ADDITION
	#   DELETION, CHANGES
	#   CHANGES, DELETION
	#
	def resolve(resolution)
		@resolution = resolution
	end

	# 
	# true if conflict has been resolved
	#
	def resolved
		@resolution
	end

	def childResolved(memberConflicts)
		if memberConflicts == @memberConflicts then
			@resolution = MEMBER_RESOLUTION
		else
			raise "resolved child is not mine!"
		end
	end
	
	#
	# This resolves the conflict based on what was chosen as a resolution.
	# it returns an two member array with an ObjectChange object for the
	# local and remote objects respectively.
	#
	def objectChange(localChanges, remoteChanges)
		case [@localChange, @remoteChange]
		when [ADDITION, ADDITION]
	   	if @resolution == USE_NEITHER then
	   		return [nil, nil]
			elsif @resolution == USE_LOCAL then
				return [localChanges[@gid], localChanges[@gid]]
			else
				localObject = localChanges[@gid].object
				remoteObject = remoteChanges[@gid].object
				remoteToLocalMemberChanges = localObject.generateMemberChanges(remoteObject)
				remoteToLocalObjectChange = ObjectChange.new(ObjectChange::MEMBER_CHANGES, localChanges[@gid].object, @gid, remoteToLocalMemberChanges )
				$TRACE.debug 5, "remoteToLocalMemberChange = #{remoteToLocalMemberChanges}"
				$TRACE.debug 5, "remoteToLocalObjectChange = #{remoteToLocalObjectChange}"
				return [remoteToLocalObjectChange, remoteChanges[@gid]]
			end

		when [DELETION, CHANGES]
			if @resolution == USE_LOCAL then
				$TRACE.trace "resolving with local object"
				return [nil, localChanges[@gid]]
			else
				$TRACE.trace "resolving with remote object"
				newObject = remoteChanges[@gid].object	# need .dup ???
				return [ObjectChange.new(ObjectChange::ADDITION, newObject, @gid), nil]
			end

		when [CHANGES, DELETION]
			if @resolution == USE_LOCAL then
				newObject = localChanges[@gid].object	# need .dup ???
				return [nil, ObjectChange.new(ObjectChange::ADDITION, newObject, @gid)]
			else
				return [remoteChanges[@gid], nil]
			end

		when [DELETION, DELETION]
			if @resolution == USE_LOCAL then
				return [nil, localChanges[@gid]]
			else
				return [remoteChanges[@gid], nil]
			end
		
		# CHANGES, CHANGES
		when [CHANGES, CHANGES]
			objectChanges = ObjectChange.new(ObjectChange::MEMBER_CHANGES, localChanges[@gid].object, @memberConflicts.memberChanges, remoteChanges[@gid].old_object)
			return [objectChanges, objectChanges]

		else
			raise "Bad conflict combination [#{CHANGE_MAP[@localChange]}, #{CHANGE_MAP[@remoteChange]}]"
		end
	end

	def to_s
		"[#{@gid}][local: #{CHANGE_MAP[@localChange]}][remote: #{CHANGE_MAP[@remoteChange]}][resolution: #{RESOLUTION_MAP[@resolution]}][memberConflicts: #{@memberConflicts}]"
	end
end

class ObjectConflicts < SortedHash
	#
	# True if all conflicts have been resolved
	#
	def all_resolved
		if to_a == [] then
			true
		else
			# they are all resolved if the array of not resolved ObjectConflict objects is empty
			to_a.select{|oc| !(oc[1].resolved)} == []
		end
	end

	def to_s
		"[[" + to_a.map{|a,b| b}.to_s + join("][") + "]]"
	end
end

