require "obdb/AR_MemberChange"

#
# This simply holds a member and a Conflict sub-class object
# 
class MemberConflict
	attr_reader :member, :conflict
	if $NEW_RESOLVE then
		attr_reader :memberConflicts
	else
		attr_accessor :memberConflicts
	end

	def initialize(member, conflict)
		@member = member
		@conflict = conflict
		@memberConflicts = nil
		if $NEW_RESOLVE then
			$TRACE.debug 9, "self.id = #{self.object_id}, MemberConflict.initialize, @resolved = #{@resolved}"
			@resolved = false
		end

		# let Conflict know its parent
		@conflict.memberConflict = self
	end

	def memberChange
		MemberChange.new(@member, nil, @conflict.change)
	end

	if $NEW_RESOLVE then
		def memberConflicts=(mc)
			@memberConflicts = mc
			$TRACE.debug 9, "self.id = #{self.object_id}, MemberConflict.memberConflicts(#{mc}), @resolved = #{@resolved}"
			if @resolved then
				$TRACE.debug 9, "MemberConflict.memberConflicts=: notifying memberConflicts"
				@memberConflicts.childResolved(self)
			end
		end
	end

	def childResolved
		if $NEW_RESOLVE then
			@resolved = true
			$TRACE.debug 9, "self.id = #{self.object_id}, MemberConflict.childResolved, resolved = #{@resolved}"
			if @memberConflicts then
				$TRACE.debug 9, "MemberConflict.childResolved: notifying memberConflicts"
				@memberConflicts.childResolved(self)
			end
		else
			@memberConflicts.childResolved(self)
		end
	end

	def ==(other)
		if other == nil then
			false
		else
			member == other.member &&
			conflict == other.conflict
		end
	end

	def to_s
		"[member:#{@member}][conflict:#{@conflict}]"
	end
end

#
# MemberConflicts is a specialized array that only holds MemberConflict objects
# that are sorted by member name.
#
class MemberConflicts < Array
	if $NEW_RESOLVE then
		attr_reader :objectConflict
	else
		attr_accessor :objectConflict
	end

	if $NEW_RESOLVE then
		def initialize(total)
			super()

			$TRACE.debug 9, "MemberConflicts.initialize: total = #{total}"

			@total = total
			@resolvedMemberConflicts = []
			@objectConflict = nil
		end
	else
		def initialize
			super
	
			@resolvedMemberConflicts = []
			@objectConflict = nil
		end
	end

	def push(mc)
	$TRACE.debug 9, "self = #{self}"
		raise ArgumentError.new("argument must be a MemberConflict not '#{mc.type}'") if !mc.kind_of?(MemberConflict)
		super

	$TRACE.debug 9, "self = #{self}, mc = #{mc}"
		# let MemberConflict know its parent
		mc.memberConflicts = self

		self.sort! {|x,y| x.member.to_s <=> y.member.to_s}
	end

	if $NEW_RESOLVE then
		def objectConflict=(oc)
			@objectConflict = oc
			$TRACE.debug 9, "MemberConflicts.objectConflict=(#{oc})"
			if @resolvedMemberConflicts.size == @total then
				$TRACE.debug 9, "MemberConflicts.objectConflict=: notifying ObjectConflict"
				@objectConflict.childResolved(self)
			end
		end
	end

	def childResolved(memberConflict)
		$TRACE.debug 9, "MemberConflicts:childResolved(#{memberConflict})"
		if !@resolvedMemberConflicts.index(memberConflict) then
			@resolvedMemberConflicts.push(memberConflict)
		end

		if $NEW_RESOLVE then
			$TRACE.debug 9, "MemberConflicts:childResolved: @resolvedMemberConflicts.size = #{@resolvedMemberConflicts.size}, total = #{@total}"
			if @resolvedMemberConflicts.size == @total then
				if @objectConflict then
					$TRACE.debug 9, "MemberConflicts:childResolved: notifying ObjectConflict"
					@objectConflict.childResolved(self)
				end	
			end
		else
			if @resolvedMemberConflicts.size == size then
				@objectConflict.childResolved(self)
			end
		end
	end

	#
	# This returns the member changes necessary to resolve the conflict
	# Note that they are not resolved at this level, but at one level
	# down in a subclass of Change (eg. SimpleChange or DiffChange)
	#
	def memberChanges
		memberChanges = MemberChanges.new
		$TRACE.debug 5, "MemberConflicts.memberChanges: Adding memberChanges"
		self.each do |memberConflict|
			memberChange = memberConflict.memberChange
			$TRACE.debug 5, "MemberConflicts.memberChanges: adding memberChange #{memberChange}"
			memberChanges.push(memberChange)
		end
		memberChanges
	end

	def to_s
		"[[" + self.map{|a| a.to_s}.join("][") + "]]"
	end
end
		

