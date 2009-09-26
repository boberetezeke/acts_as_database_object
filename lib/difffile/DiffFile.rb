#require "my/mytrace"
require "my/mysystem"
require "my/mystring"
require "my/myFile"

module Diff

def min(a,b)
	(a < b) ? a : b
end

def max(a,b)
	(a < b) ? b : a
end

#
# this returns an array of ranges that indicate sections of the arrays a and b that are not identical
#
def non_identical_parts(a, b)
	nip = []
	index = -1
	matching = true
	minsize = min(a.size, b.size)
	for i in 0..minsize-1
		if matching then
			if a[i] != b[i] then
				matching = false
				index = i
			end
		else
			if a[i] == b[i] then
				nip.push(index.. i-1)
				matching = true
			end
		end
	end
	if !matching && minsize != 0 then
		nip.push(index..max(a.size, b.size)-1)
	end
	nip
end

class ChangeRange < Range
	attr_reader :begin2, :end2
	attr_accessor :has_extent
	
	EQUAL = :equal
	ABOVE = :above
	ADJACENT_ABOVE = :adjacent_above
	OVERLAPS_ABOVE = :overlaps_above
	BELOW = :below
	ADJACENT_BELOW = :adjacent_below
	OVERLAPS_BELOW = :overlaps_below
	CONTAINS = :contains
	CONTAINED_BY = :contained_by

	RELATIONSHIP_HASH = {
		EQUAL => 				"equal",
		ABOVE => 				"above",
		ADJACENT_ABOVE => 	"adjacent above",
		OVERLAPS_ABOVE => 	"overlaps above",
		BELOW => 				"below",
		ADJACENT_BELOW =>		"adjacent below",
		OVERLAPS_BELOW =>		"overlaps below",
		CONTAINS =>				"contains",
		CONTAINED_BY =>		"contained by"
	}
	
	def initialize(begin_, end_, has_extent)
		super(begin_, end_)
		@has_extent = has_extent
		@begin2 = begin_ * 2 + (has_extent ? 0 : 1)
		@end2 = end_ * 2 + (has_extent ? 0 : 1)
	end

	def relationship_to(aRange)
		if self == aRange then
			ret = EQUAL
		elsif self.end2 < aRange.begin2 then
			ret = isadjacent(aRange.begin2, self.end2) ? ADJACENT_ABOVE : ABOVE
		elsif self.begin2 > aRange.end2
			ret = isadjacent(self.begin2, aRange.end2) ? ADJACENT_BELOW : BELOW
		elsif self.contains(aRange) then
			ret = CONTAINS
		elsif aRange.contains(self) then
			ret = CONTAINED_BY
		elsif self.overlaps_below(aRange) then
			ret = OVERLAPS_BELOW
		elsif self.overlaps_above(aRange) then
			ret = OVERLAPS_ABOVE
		else
			raise "Unknown relationship between '#{self}' and '#{aRange}'"
		end

		$TRACE.debug 5, "relationship_to: #{self} is #{RELATIONSHIP_HASH[ret]} #{aRange}"
		return ret
	end

	def ==(other)
		return false unless other.kind_of?(ChangeRange)
		self.begin == other.begin && self.end == other.end && self.has_extent == other.has_extent
	end

	def isadjacent(high, low)
		case (high - low)
		when 1
			return true
		when 2
			if odd(high) && odd(low) then
				return false
			else
				return true
			end
		else
			return false
		end
	end

	def odd(num)
		num % 2 != 0
	end
	
	def contains(aRange)
		self.begin2 <= aRange.begin2 && self.end2 >= aRange.end2
	end

	def overlaps_below(aRange)
		(aRange.begin2 <= self.begin2 && self.begin2 <= aRange.end2)  && (self.end2 > aRange.end2)
	end

	def overlaps_above(aRange)
		aRange.overlaps_below(self)
	end
#=begin
	def length
		if @has_extent then
			self.end - self.begin + 1
		else
			0
		end
	end
#=end

	def size
		self.end - self.begin + 1		
	end
	
	def to_s
		"ChangeRange:[#{self.begin},#{self.end}-#{@begin2},#{@end2}-#{@has_extent?'has extent':'no extent'}]"
	end
end

#
# This is one change in a diff file. It is either a addition/deletion/change
#
class Change
	# change types
	CHANGE = 1
	ADDITION = 2
	DELETION = 3

	# map diff char to constant	
	CHANGE_TYPE_MAP = {
		"c" => CHANGE,
		"a" => ADDITION,
		"d" => DELETION
	}
	

	attr_accessor :addLines, :deleteLines, :src, :dest

	# 
	# This is initialized from the information on each diff change
	# x,y[a|b|d]s,t
	#
	def initialize(srcStart=0, srcEnd=0, destStart=0, destEnd=0, chgType=CHANGE, delLines=[], addLines=[])
		if chgType.kind_of?(String) then
			@chgType = CHANGE_TYPE_MAP[chgType]
		else
			@chgType = chgType
		end

		@src = ChangeRange.new(srcStart, srcEnd, @chgType != ADDITION)
		@dest = ChangeRange.new(destStart, destEnd, @chgType != DELETION)
		
		@addLines = addLines
		@deleteLines = delLines
	end

	def srcStart
		@src.begin
	end

	def srcStart=(num)
		@src = ChangeRange.new(num, @src.end, chgType != ADDITION)
	end
	
	def srcEnd
		@src.end
	end

	def srcEnd=(num)
		@src = ChangeRange.new(@src.begin, num, chgType != ADDITION)
	end

	def srcLength
		@src.length
	end

	def srcLength=(num)
		@src = ChangeRange.new(@src.begin, @src.begin + num - 1, chgType != ADDITION)
	end
	
	def destStart
		@dest.begin
	end

	def destStart=(num)
		@dest = ChangeRange.new(num, @dest.end, chgType != DELETION)
	end

	def destEnd
		@dest.end
	end

	def destEnd=(num)
		@dest = ChangeRange.new(@dest.begin, num, chgType != DELETION)
	end

	def destLength
		@dest.length
	end

	def destLength=(num)
		@dest = ChangeRange.new(@dest.begin, @dest.begin + num - 1, chgType != DELETION)
	end
	

	def chgType
		@chgType
	end
	
	def chgType=(chgType_)
		@chgType = chgType_
		@src.has_extent = (chgType != ADDITION)
		@dest.has_extent = (chgType != DELETION)
	end
	
	#
	# This inverts a change so that if it was applied to the second file of
	# a diff command, it would generate the change in the first.
	#
	def invert!
		destStart, srcStart = self.srcStart, self.destStart
		destEnd, srcEnd = self.srcEnd, self.destEnd

		@src,@dest = @dest,@src
		
		@addLines, @deleteLines = @deleteLines, @addLines
		case @chgType
		when DELETION
			@chgType = ADDITION
		when ADDITION
			@chgType = DELETION
		end
	end

	def dup
		Change.new(self.srcStart, self.srcEnd, self.destStart, self.destEnd, self.chgType, @deleteLines.dup, @addLines.dup)
	end
	
	def ==(other)
		return false if !other.kind_of?(Change)
		
		a = srcStart == other.srcStart
		b = srcEnd == other.srcEnd
		c = destStart == other.destStart
		d = destEnd == other.destEnd
		e = chgType == other.chgType
		f = @addLines == other.addLines
		g = @deleteLines == other.deleteLines

		#print "compare = #{a},#{b},#{c},#{d},#{e},#{f},#{g}\n"
		
		a && b && c && d && e && f && g
	end

	def normalize
		# Set change type
		if @deleteLines.size == 0 && @addLines.size == 0  then
			return nil
		elsif @deleteLines.size > 0  && @addLines.size == 0  then
			self.chgType = DELETION
			self.srcLength = @deleteLines.size
			self.destLength = 1
		elsif @deleteLines.size == 0 && @addLines.size > 0   then
			self.chgType = ADDITION
			self.srcLength = 1
			self.destLength = @addLines.size
		else
			self.chgType = CHANGE
			self.srcLength = @deleteLines.size
			self.destLength = @addLines.size
		end
		$TRACE.debug 5, "addLines size = #{@addLines.size}, deleteLines size = #{@deleteLines.size}, change = #{@chgType}"

		return self
	end

	#
	# This combines this change (self) and a change that is adjacent to it below
	#
	def combine_adjacent_change(change)
		@addLines += change.addLines
		@deleteLines += change.deleteLines
		if @chgType == ADDITION && @deleteLines.size > 0 then
			self.srcStart += 1
		end
		if @chgType = DELETION && @addLines.size > 0 then
			self.destStart += 1
		end
		normalize	
	end

	#
	# This combines this change (self) and a change mad in a subsequent revison. It assumes
	# that the destination of this change and the source of the next change either overlap or
	# are adjacent.
	#
	def combine_successive_change(aDiffChange)
		# set up short hand for left and right changes
		l = self
		r = aDiffChange
		c = Change.new(0,0,0,0, CHANGE)  # all parameters will change below

		$TRACE.debug 5, "left = #{l}, right = #{r}"
		
		# calculate overlaps
		before_overlap = (l.destStart - r.srcStart).abs
		after_overlap = (l.destEnd - r.srcEnd).abs

		if 	((l.chgType == DELETION  &&  r.chgType != ADDITION) ||
		   	(l.chgType != DELETION &&  r.chgType == ADDITION)) then
			before_overlap += 1
		end
		
		# Calculate source and destination line numbers and content
		relationship =dest.relationship_to(aDiffChange.src)
		$TRACE.debug 5, "relationship = #{relationship}, before_overlap = #{before_overlap}, after_overlap = #{after_overlap}"
		case relationship
		when ChangeRange::EQUAL
			c.src = l.src
			c.deleteLines = l.deleteLines
			
			c.dest = r.dest
			c.addLines = r.addLines
			
		when ChangeRange::OVERLAPS_ABOVE
			overlap = (l.destEnd - r.srcStart) + 1

			$TRACE.debug 9, "overlap = #{overlap}, l.srcLength = #{l.srcLength}"
			c.srcStart = l.srcStart + ((l.chgType == ADDITION) ? 1 : 0)
			#c.srcLength = l.deleteLines.size + after_overlap
			c.deleteLines = l.deleteLines + r.deleteLines[-after_overlap, after_overlap]
			
			c.destStart = r.destStart - before_overlap + ((r.chgType == DELETION) ? 1 : 0)
			#c.destLength = r.addLines.size + before_overlap
			c.addLines = l.addLines[0, before_overlap] + r.addLines
			
		when ChangeRange::OVERLAPS_BELOW
			overlap = (r.srcEnd - l.destStart) + 1
			
			c.srcStart = l.srcStart - before_overlap + ((l.chgType == ADDITION) ? 1 : 0)
			#c.srcLength = l.srcLength + before_overlap
			c.deleteLines = r.deleteLines[0, before_overlap] + l.deleteLines
			
			c.destStart = r.destStart + ((r.chgType == DELETION) ? 1 : 0)
			#c.destLength = r.destLength + after_overlap
			c.addLines = r.addLines + l.addLines[-after_overlap, after_overlap]
			
		when ChangeRange::CONTAINS
			c.src = l.src
			c.deleteLines = l.deleteLines

			$TRACE.debug 5, "r.destStart = #{r.destStart}, r.chgType = #{r.chgType}"
			c.destStart = r.destStart - before_overlap + ((r.chgType == DELETION) ? 1 : 0)
			#c.destLength = before_overlap + r.addLines.size + after_overlap
			c.addLines = l.addLines[0, before_overlap] + r.addLines + l.addLines[-after_overlap, after_overlap]
			

		when ChangeRange::CONTAINED_BY
			c.srcStart = l.srcStart - before_overlap + ((l.chgType == ADDITION) ? 1 : 0)
			#c.srcLength = before_overlap + l.deleteLines.size + after_overlap
			$TRACE.debug 9, "c.srcStart = #{c.srcStart}, c.srcLength = #{c.srcLength}, c.srcEnd = #{c.srcEnd}\n"
			c.deleteLines = r.deleteLines[0, before_overlap] + l.deleteLines + r.deleteLines[-after_overlap, after_overlap]
			
			c.dest = r.dest
			c.addLines = r.addLines

		when ChangeRange::ADJACENT_ABOVE
			c.srcStart = l.srcStart + (l.chgType == ADDITION ? 1 : 0)
			c.deleteLines = l.deleteLines + r.deleteLines
			c.destStart = r.destStart - l.destLength + (r.chgType == DELETION ? 1 : 0)
			$TRACE.debug 5, "c.destStart = #{c.destStart}, r.destStart = #{r.destStart}, l.destLength = #{l.destLength}, r.chgType = #{r.chgType}"
			c.addLines = l.addLines + r.addLines
			c.srcStart -= (c.deleteLines.size == 0 ? 1 : 0)
			c.destStart -= (c.addLines.size == 0 ? 1 : 0)
		when ChangeRange::ADJACENT_BELOW
			c.srcStart = l.srcStart() - r.srcLength() + (l.chgType == ADDITION ? 1 : 0)
			$TRACE.debug 5, "c.srcStart = #{c.srcStart}, l.srcStart = #{l.srcStart}, r.srcLength = #{r.srcLength}, l.chgType = #{l.chgType}"
			c.deleteLines = r.deleteLines + l.deleteLines
			c.destStart = r.destStart + (r.chgType == DELETION ? 1 : 0)
			c.addLines = r.addLines  + l.addLines
			c.srcStart -= (c.deleteLines.size == 0 ? 1 : 0)
			c.destStart -= (c.addLines.size == 0 ? 1 : 0)
		end

 		# c.addLines += ["bad line"] - used to make sure test can fail
 		
		if c.addLines.size > 0 && c.deleteLines.size > 0 then
			changes = [c.normalize]
=begin
			changes = []

			$TRACE.debug 5, "deleteLines = #{c.deleteLines.inspect}, addLines = #{c.addLines.inspect}"
			nips = non_identical_parts(c.addLines, c.deleteLines)
			$TRACE.debug 5, "nips = #{nips.inspect}"
			
			case nips.size
			when 0
				return nil
#			when 1
#				return nil if !c.normalize
#				changes.push(c)
			else
				nips.each do |src_range, dest_range|
					d = Change.new
					d.srcStart = c.srcStart + src_range.begin
					d.deleteLines = (src_range.has_extent) ?
						(c.deleteLines[src_range.begin..src_range.end]) : []
					d.destStart = c.destStart + dest_range.begin
					d.deleteLines = (dest_range.has_extent) ?
						(c.addLines[dest_range.begin..dest_range.end]) : []
					
					if d.normalize then
						$TRACE.debug 5, "combined change = #{d}"
						changes.push(d)
					end
				end
			end
=end
		else
			return nil if !c.normalize
			changes = [c]
		end
		
		changes
	end
	
	def split_right(line_num)
		top_lines = line_num - self.destStart
		bottom_lines = @addLines.size - top_lines

		top_change = self.dup
		bottom_change = self.dup

		top_change.addLines = @addLines[0, top_lines]
		top_change.destLength = top_lines
		
		bottom_change.addLines = @addLines[-bottom_lines, bottom_lines]
		bottom_change.destStart = self.destStart + top_lines
		bottom_change.destLength = bottom_lines
		if @chgType == CHANGE then
			bottom_change.srcStart += @deleteLines.size-1
		end
		bottom_change.deleteLines = []
		bottom_change.chgType = Change::ADDITION

		return [top_change, bottom_change]
	end

	def split_left(line_num)
		top_lines = line_num - self.srcStart
		bottom_lines = @deleteLines.size - top_lines

		top_change = self.dup
		bottom_change = self.dup

		top_change.deleteLines = @deleteLines[0, top_lines]
		top_change.srcLength = top_lines
		
		bottom_change.deleteLines = @deleteLines[-bottom_lines, bottom_lines]
		bottom_change.srcStart = self.srcStart + top_lines
		bottom_change.srcLength = bottom_lines
		if @chgType == CHANGE then
			bottom_change.destStart += @addLines.size-1
		end
		bottom_change.addLines = []
		bottom_change.chgType = Change::DELETION

		return [top_change, bottom_change]
	end
	
	#
	# tells if this change contains the given source line number
	#
	def src_contains(lineNum)
		@src.begin <= lineNum && lineNum <= @src.end
	end

	def description
		if @src.size == 1 then
			srcStr = srcStart.to_s
		else
			srcStr = "#{srcStart},#{srcEnd}"
		end
		if @dest.size == 1 then
			destStr = destStart.to_s
		else
			destStr = "#{destStart},#{destEnd}"
		end
		return srcStr + CHANGE_TYPE_MAP.invert[@chgType] + destStr
	end

	def put(file)
		file.print description, "\n"
		deleteLines.each do |line|
			file.print "< #{line}\n"
		end
		file.print "---\n" if chgType == Change::CHANGE
		addLines.each do |line|
			file.print "> #{line}\n"
		end
	end
	
	def to_s
		deleteLinesStr = @deleteLines.join(", ")
		addLinesStr = @addLines.join(", ")
		"Change:[#{srcStart},#{srcEnd}#{CHANGE_TYPE_MAP.invert[@chgType]}#{destStart},#{destEnd}][#{deleteLinesStr}][#{addLinesStr}][#{@src},#{@dest}]"
	end
end

class DiffFileChanges < Array
	def lowest_start
		self.sort{|a,b|a.srcStart <=> b.srcStart}[0]
	end

	def highest_end
		self.sort{|a,b|b.srcEnd <=> a.srcEnd}[0]
	end
end

#
# This keeps track of the a particular DiffFile object and the current change for it,
# and the current set of changes in this file that are part of a conflicting set.
#
class ApplyDiffFile
	attr_reader :curChange, :conflicts, :diffFile, :eof
	
	def initialize(diffFile, invertChanges)
		@diffFile = diffFile
		@curChange = nil
		@conflicts = []
		@eof = false
		@invertChanges = invertChanges
		@diffFile.open("r")
	end

	def update
		if !@eof && !@curChange then
			@curChange = @diffFile.get_change
			@curChange.invert! if @curChange && @invertChanges
			@eof = (@curChange == nil)
		end
	end

	def get_change(isConflict=false)
		@conflicts.push(@curChange) if isConflict
		curChange = @curChange
		@curChange = nil
		curChange
	end

	def clear_conflicts
		@conflicts = []
	end

	def to_s
		#"[diffFile:#{@diffFile}]"
		"ApplyDiffFile:[curChange:#{@curChange}][conflicts:(" + @conflicts.join(")(") + ")]"
	end

	def close
		@diffFile.close
	end
end

#
# This is a list of the ApplyDiffFile objects
#
class ApplyDiffFiles < Array
	def initialize(changes_array, invertChanges)
		super()
		changes_array.each {|changes| self.push(ApplyDiffFile.new(changes, invertChanges))}
	end

	#
	# get an array of the next changes. 
	# 
	# - If there is one in the list then it is the next change to process.
	# - If there is more than one, then the list contains next set of changes that all overlap.
	#
	def get_changes
		update									# get the current change from each diffFile
		$TRACE.debug 5, "applyDiffFiles at beginning = #{self}"
		changes = DiffFileChanges.new

		# if there are any changes left
		if lowest_adf = lowest_start then
			changes.push(lowest_adf.get_change)		# get lowest change
			$TRACE.debug 5, "changes at beginning = #{changes}"
			while true
				update												# get current change from each diffFile
				$TRACE.debug 5, "applyDiffFiles in loop = #{self}"
				$TRACE.debug 5, "lowest_start in loop = #{lowest_start}"
				if change_conflicts(lowest_start, changes) then
					# if this is the first time we have a conflict
					if changes.size == 1 then
						# push the first lowest one
						lowest_adf.conflicts.push(changes[0])
					end
					changes.push(lowest_start.get_change(true))
				else
					break
				end
				$TRACE.debug 5, "changes in loop = #{changes}"
			end
		end
		changes
	end

	#
	# make sure all the applyDiffFile objects contain their latest change
	#
	def update
		self.each{|adf| adf.update}
	end

	#
	# tell if the change conflicts with current set of overlapped changes
	#
	def change_conflicts(anApplyDiffChange, changes)
		return false unless anApplyDiffChange && anApplyDiffChange.curChange
		conflicts = changes.select {|chg| chg.src_contains(anApplyDiffChange.curChange.srcStart)} != []
		$TRACE.debug 5, "conflicts = #{conflicts.inspect}"
		conflicts
	end

	#
	# returns the lowest starting change in the given set of changes
	#
	def lowest_start
		self.dup.select{|c| c.curChange != nil}.sort{|a,b| a.curChange.srcStart <=> b.curChange.srcStart}[0]
	end

	def highest_end
		self.dup.select{|c| c.curChange != nil}.sort{|a,b| b.curChange.srcEnd <=> a.curChange.srcEnd}[0]
	end
	
	def to_s
		"ApplyDiffFiles:[" + self.join(")(") + "]"
	end

	def eof
		# eof is true only if all ApplyDiffFile objects are at eof
		self.select{|adf| adf.eof}.size == self.size
	end
	
	def close
		self.each{|c| c.close}
	end
end

class Accumulator
	LEFT = 0
	RIGHT = 1
	NONE = 2

	SRC_OFFSET = 0
	DEST_OFFSET = 1
	
	def initialize()
		@offsets = [0,0]
		@changes = [nil, nil]
		@cur_split = NONE
		@last_split = NONE
		@split_done = false
		@split_offset = [0,0]
	end

	#
	# this returns the offset amount based on the current change
	# and which type it is (LEFT or RIGHT)
	# 
	def change_offset(changeConst)
		change = @changes[changeConst]
		if change then
			$TRACE.debug 5, "change_offset, found change, add lines=#{change.addLines.size}, delete lines=#{change.deleteLines.size}"
			if changeConst == LEFT
				return change.addLines.size - change.deleteLines.size
			else
				return change.deleteLines.size - change.addLines.size
			end
		else
			$TRACE.debug 5, "change_offset, return 0"
			return 0
		end
	end

	# 
	# This lets the accumulator know that when the next change
	# on changeConst side is set, that it is either a split
	# change or not.
	#
	def set_cur_split(changeConst)
		# if we are going from no split to some side splitting
		if @cur_split == NONE && changeConst != NONE then
			# save the offset for when the splitting is finished
			@split_offset[changeConst] = change_offset(changeConst)			
		# else if we are going form splitting to no split or other side split
		elsif @cur_split != NONE && changeConst != @cur_split then
			# set this so that adjust_offset knows we are finishing up a split
			@last_split = @cur_split
			#@split_done = true
		end
		@cur_split = changeConst
	end

	#
	# This adjusts the source and destination offsets based on 
	# whether a split is proceeding or not
	#
	def adjust_offset(changeConst, offsetConst)
		$TRACE.debug 5, "adjust_offset: cur_split = #{@cur_split}, last_split = #{@last_split}, changeConst = #{changeConst}"
		# if this side is not involved in a split change
		if @last_split == changeConst then
			# clear the split
			# get the split offset and apply it now
			offset = @split_offset[changeConst]

			@last_split = @cur_split
			$TRACE.debug 5, "adjust_offset: split offset = #{offset}"
		elsif @cur_split == changeConst then
			$TRACE.debug 5, "adjust_offset: no adjust"
			# so do nothing
			return
		else
			# take the offset from the current change being replaced
			offset = change_offset(changeConst)
			$TRACE.debug 5, "adjust_offset: offset = #{offset}"
		end
=begin
		$TRACE.debug 5, "adjust_offset: cur_split = #{@cur_split}, changeConst = #{changeConst}"
		# if this side is not involved in a split change
		if @cur_split != changeConst then
			# take the offset from the current change being replaced
			offset = change_offset(changeConst)
			$TRACE.debug 5, "adjust_offset: offset = #{offset}"
		else
			# if this new change is passed the last split
			#if @split_done then
			if @last_split == changeConst then
				# clear the split
				#@cur_split = NONE
				# get the split offset and apply it now
				offset = @split_offset

				@last_split = @cur_split
				$TRACE.debug 5, "adjust_offset: split offset = #{offset}"
			# else we are in the middle of a split
			else
				$TRACE.debug 5, "adjust_offset: no adjust"
				# so do nothing
				return
			end
		end
=end
		# if there was a previous change
		if @changes[changeConst] then
			# apply the offset from the previous change
			@offsets[offsetConst] += offset
			$TRACE.debug 5, "adjust_offset: setting @offsets[#{offsetConst}] = #{@offsets[offsetConst]}"
		end
	end

	# 
	# This is a common routine used by left_change and right_change.
	# It adjusts the offsets if necessary and then saves the new change
	#
	def set_change(changeConst, newChange)
		# adjust the offsets first
		adjust_offset(changeConst, (changeConst == LEFT) ? SRC_OFFSET : DEST_OFFSET)
		# save over the previous change
		@changes[changeConst] = newChange
	end

	def left_change=(change)
		set_change(LEFT, change)
	end

	def right_change=(change)
		set_change(RIGHT, change)
	end

	def left_change()
		return @changes[LEFT]
	end

	def right_change()
		return @changes[RIGHT]
	end

	def src_offset()
		return @offsets[SRC_OFFSET]
	end

	def dest_offset
		return @offsets[DEST_OFFSET]
	end
end

class Changes
	#
	# put a change by possibly combining it with the last change put if they
	# are adjacent.
	#
	def put_change(change)
		if @last_put_change then
			# if this change can be combined with the last change
			if change then
				relationship = @last_put_change.src.relationship_to(change.src)
				$TRACE.debug 5, "put_change: relationship is #{relationship} between last=#{@last_put_change} and cur=#{change}"
			end
			
			if change && [ChangeRange::ADJACENT_ABOVE, ChangeRange::EQUAL].include?(relationship) then
				# combine with last change
				@last_put_change.combine_adjacent_change(change)
				$TRACE.debug 5, "put_change: new combined change: #{@last_put_change}"
			else
				$TRACE.debug 5, "put_change: putting change: #{@last_put_change}"
				real_put_change(@last_put_change)
				@last_put_change = change
			end
		else
			@last_put_change = change
			$TRACE.debug 5, "put_change: save change: #{@last_put_change}"
		end
	end

	def ==(other)
		return false if !other.kind_of?(Changes)
		return false if self.mode != other.mode
		return true if self.mode == "w"

		is_equal = true
		self.open("r")
		other.open("r")
		while true
			change1 = self.get_change
			change2 = other.get_change
			if change1 == change2 then
				break if !change1 
			else
				is_equal = false
				break
			end
		end
		self.close
		other.close

		return is_equal
	end
end

class ArrayChanges < Changes
	attr_reader :mode
	
	def initialize()
		@changes = []
	end

	#
	# for an ArrayChange, an open does nothing
	#
	def open(mode)
		@mode = mode
		if mode == "w" then
			@changes = []
		end
		@change_index = 0
	end
	
	def real_put_change(change)
		@changes.push(change)
	end

	def get_change
		$TRACE.debug 5, "get change: #{@change_index}, #{@changes.size}\n"
		if @change_index < @changes.size then
			change = @changes[@change_index]
			@change_index += 1
			change
		else
			return nil
		end
	end
	
	def each
		@changes.each do |c|
			yield c
		end
	end

	def content
		@changes.map{|c| c.to_s}.join("\n")
	end
	
	def close
		if mode == "w" then
			put_change(nil)	# flush out last change
		end
	end

	def to_s
		"[ArrayChanges:#{@changes.size} elements][Index:#{@change_index}]"
	end
end

#
# This class represents a file that is the output of the unix diff command
#
class FileChanges < Changes
	
	# Parse States
	WAIT_CHG_DESC = 1
	GET_RIGHT = 2
	GET_LEFT = 3
	GET_SEPARATOR = 4

	# Match patterns
	CHANGE_PATTERN = /(\d+)(,(\d+))?([acd])(\d+)(,(\d+))?/
	LEFT_PATTERN = /^<\s(.*)$/
	RIGHT_PATTERN = /^>\s(.*)$/
	MID_PATTERN = /^---$/
	NO_NEWLINE = /No newline at end of file$/

	attr_reader :filename, :mode
	
	def initialize(filename)
		@filename = filename
		@last_put_change = nil
	end

	def open(mode)
		@mode = mode
		@file = File.new(filename, @mode)
	end
	
	def real_put_change(change)
		change.put(@file)
	end
	
	#
	# get the next change (a Change object) from the diff file
	#
	def get_change
		state = WAIT_CHG_DESC
		numLines = nil
		diffChange = nil
		while s = @file.gets
			$TRACE.debug 3,"state = #{state}, line = '#{s.chop}'"
			case state
			when WAIT_CHG_DESC
				if CHANGE_PATTERN.match(s) then
					$TRACE.debug 5, "match = $1='#{$1}', $2='#{$2}', $3='#{$3}', $4='#{$4}', $5='#{$5}', $6='#{$6}', $7='#{$7}'"
					diffChange = Change.new($1.to_i, ($2 ? $3.to_i : $1.to_i), $5.to_i, ($6 ? $7.to_i : $5.to_i), $4)
					$TRACE.debug 7, "diffChange = #{diffChange.inspect}"
					if diffChange.chgType == Change::ADDITION
						$TRACE.debug 7, "destEnd = #{diffChange.destEnd}, destStart = #{diffChange.destStart}"
						numLines = diffChange.destEnd - diffChange.destStart + 1
						$TRACE.debug 3,  "RIGHT START:num lines = #{numLines}"
						state = GET_RIGHT
					else
						$TRACE.debug 7,  "srcEnd = #{diffChange.srcEnd}, srcStart = #{diffChange.srcStart}"
						numLines = diffChange.srcEnd - diffChange.srcStart + 1
						$TRACE.debug 3,  "LEFT START:num lines = #{numLines}"
						state = GET_LEFT
					end
					
				elsif NO_NEWLINE.match(s) then
					# stay in this state and ignore this line
				else
					raise "Change description expected, got '#{s.chop}'"
				end

			when GET_LEFT
				if LEFT_PATTERN.match(s) then
					numLines -= 1
					diffChange.deleteLines.push($1)
					$TRACE.debug 3,  "LEFT: numLines = #{numLines}"
					if numLines == 0 then
						if diffChange.chgType == Change::DELETION then
							$TRACE.debug 7,  "returning diffChange = #{diffChange.inspect}"
							return diffChange
						else
							state = GET_SEPARATOR
						end
					end
				else
					raise "Left line expected, got '#{s.chop}'"
				end
				
			when GET_RIGHT
				if RIGHT_PATTERN.match(s) then
					numLines -= 1
					$TRACE.debug 3, "RIGHT: numLines = #{numLines}"
					diffChange.addLines.push($1)
					if numLines == 0 then
						$TRACE.debug 7,  "returning diffChange = #{diffChange.inspect}"
						return diffChange
					end
				else
					raise "Right line expected, got '#{s.chop}'"
				end

			when GET_SEPARATOR
				if MID_PATTERN.match(s) then
					state = GET_RIGHT
					numLines = diffChange.destEnd - diffChange.destStart + 1
					$TRACE.debug 3,  "SEP: numLines = #{numLines}"
				elsif NO_NEWLINE.match(s) then
					# stay in this state and ignore this line
				else
					raise "Mid line expected, got '#{s.chop}'"
				end
			end
		end

		diffChange
	end

	def each
		while diffChange = get_change
			yield diffChange
		end
	end

	def close
		# if we are writing a diff file
		if @mode == "w" then
			put_change(nil)	# flush out last change
		end
		@file.close
	end

	def content
		File.data(@filename).x
	end
	
	def to_s
		"FileChanges:[filename:#{@filename}]"
	end
	
	#
	# class methods
	#
	class << self
	end
end

# define module functions
class << self

#
# tell if a set of diffs conflict at all
#
def diffs_conflict(diff_filenames)
	applyDiffFiles = ApplyDiffFiles.new(diff_filenames, false)
	while !applyDiffFiles.eof
		changes = applyDiffFiles.get_changes
		if changes.size > 1 then
			applyDifffiles.close
			return true
		end
	end

	applyDifffiles.close
	return false
end

#
# accumulate successive diffs and write a difffile that is the result of that accumulation
#
def accumulate_diffs(diff_filenames, output_filename)
end

#		def handle_overlap(diffFileAbove, diffFileBelow, diffOutFile, changeAbove, changeBelow, srcOrDest, aboveConst, belowConst, acc)
def handle_overlap(diffFile_nonsplit, diffFile_split, diffOutFile, 
								 cur_nonsplit_change, cur_split_change, 
								 nonsplit_const, split_const, acc)
	next_nonsplit_change = diffFile_nonsplit.get_change
	$TRACE.debug 5, "next_nonsplit_change = #{next_nonsplit_change}\n"
	# if there is no change after the change on the non split side OR 
	#    it is below the split side change
	if !next_nonsplit_change || ((nonsplit_const == Accumulator::LEFT) ?
#													([ChangeRange::BELOW, ChangeRange::ADJACENT_BELOW].include?(next_nonsplit_change.dest.relationship_to(cur_split_change.src))) :
#													([ChangeRange::ABOVE, ChangeRange::ADJACENT_ABOVE].include?(cur_split_change.dest.relationship_to(next_nonsplit_change.src)))) then
											(next_nonsplit_change.dest.relationship_to(cur_split_change.src) == ChangeRange::BELOW) :
											(cur_split_change.dest.relationship_to(next_nonsplit_change.src) == ChangeRange::ABOVE)) then
		$TRACE.debug 5, "cur_nonsplit_change = #{cur_nonsplit_change}, cur_split_change = #{cur_split_change}\n"
		# put out the combined change
		if nonsplit_const == Accumulator::LEFT then
			$TRACE.debug 5, "nonsplit change is on the left\n"
			changes = cur_nonsplit_change.combine_successive_change(cur_split_change)
			if changes then
				changes.each do |change|
					diffOutFile.put_change(change)
				end
			end
		else
			$TRACE.debug 5, "split is on the left\n"
			changes = cur_split_change.combine_successive_change(cur_nonsplit_change)
			if changes then
				changes.each do |change|
					diffOutFile.put_change(change)
				end
			end
		end
		# get the next below change
		cur_split_change = diffFile_split.get_change
		$TRACE.debug 5, "no need to split change, new split change = #{cur_split_change}"
		acc.set_cur_split(Accumulator::NONE)
		
	# the change after the above change overlaps with the below change
	else
		acc.set_cur_split(split_const)
		if nonsplit_const == Accumulator::LEFT then
			cur_split_change, next_split_change = cur_split_change.split_left(next_nonsplit_change.destStart)
			$TRACE.debug 5, "need to split change, new split change = #{cur_split_change}, #{next_split_change}"
			$TRACE.debug 5, "combining cur_nonsplit_change = #{cur_nonsplit_change}, with cur_split_change = #{cur_split_change}"
			changes = cur_nonsplit_change.combine_successive_change(cur_split_change)
			if changes then
				changes.each do |change|
					diffOutFile.put_change(change)
				end
			end
		else
			cur_split_change, next_split_change = cur_split_change.split_right(next_nonsplit_change.srcStart)
			$TRACE.debug 5, "need to split change, new split change = #{cur_split_change}, #{next_split_change}"
			$TRACE.debug 5, "combining cur_split_change = #{cur_split_change}, with cur_nonsplit_change = #{cur_nonsplit_change}"
			changes = cur_split_change.combine_successive_change(cur_nonsplit_change)
			if changes then
				changes.each do |change|
					diffOutFile.put_change(change)
				end
			end
		end
		cur_split_change = next_split_change
	end
	cur_nonsplit_change = next_nonsplit_change

	acc.set_change(nonsplit_const, cur_nonsplit_change)
	acc.set_change(split_const, cur_split_change)

=begin
	next_changeAbove = diffFileAbove.get_change
	$TRACE.debug 5, "next_change above = #{next_changeAbove}\n"
	# if there is no change after the above change or it is below the below change
	if !next_changeAbove || next_changeAbove.dest.relationship_to(changeBelow.send(srcOrDest)) == ChangeRange::BELOW then
		$TRACE.debug 5, "changeAbove = #{changeAbove}, changeBelow = #{changeBelow}\n"
		# put out the combined change
		if aboveConst == Accumulator::LEFT then
			$TRACE.debug 5, "changeAbove is on the left\n"
			$TRACE.set_level 9
			changeAbove.combine_successive_change(changeBelow).each do |change|
				diffOutFile.put_change(change)
			end
			$TRACE.set_level 0
		else
			$TRACE.debug 5, "changeAbove is on the right\n"
			changeBelow.combine_successive_change(changeAbove).each do |change|
				diffOutFile.put_change(change)
			end
		end
		# get the next below change
		changeBelow = diffFileBelow.get_change
		$TRACE.debug 5, "no need to split change, new below change = #{changeBelow}"
		acc.set_cur_split(Accumulator::NONE)
		
	# the change after the above change overlaps with the below change
	else
		acc.set_cur_split(belowConst)
		if aboveConst == Accumulator::LEFT then
			changeBelow, next_changeBelow = changeBelow.split_left(changeAbove.srcStart)
			$TRACE.debug 5, "need to split change, new change below = #{changeBelow}, #{next_changeBelow}"
			changeAbove.combine_successive_change(changeBelow).each do |change|
				diffOutFile.put_change(change)
			end
		else
			changeBelow, next_changeBelow = changeBelow.split_right(changeAbove.destStart)
			$TRACE.debug 5, "need to split change, new change below = #{changeBelow}, #{next_changeBelow}"
			changeBelow.combine_successive_change(changeAbove).each do |change|
				diffOutFile.put_change(change)
			end
		end
		changeBelow = next_changeBelow
	end
	changeAbove = next_changeAbove

	acc.set_change(aboveConst, changeAbove)
	acc.set_change(belowConst, changeBelow)
=end
end


#def accumulate_2_diffs(diff_filename_left, diff_filename_right, output_filename)
#	diffOutFile = FileChanges.new(output_filename, "w")
#	diffFile_left = FileChanges.new(diff_filename_left)
#	diffFile_right = FileChanges.new(diff_filename_right)

def accumulate_2_diffs(diffFile_left, diffFile_right, diffOutFile)
	#srcOffset = destOffset = 0
	acc = Accumulator.new

	diffFile_left = FileChanges.new(diffFile_left) if diffFile_left.kind_of?(String)
	diffFile_right = FileChanges.new(diffFile_right) if diffFile_right.kind_of?(String)
	diffOutFile = FileChanges.new(diffOutFile) if diffOutFile.kind_of?(String)
	
	# open the files for reading
	diffFile_left.open("r")
	diffFile_right.open("r")
	diffOutFile.open("w")
	
	#STDERR.print "in accumulate_2_diffs\n"; STDERR.flush
	#$TRACE.debug 9, "before getting change from '#{diff_filename_left}'"
	acc.left_change = diffFile_left.get_change
	#$TRACE.debug 9, "before getting change from '#{diff_filename_right}'"
	acc.right_change = diffFile_right.get_change
	$TRACE.debug 9, "after getting first changes"

	while true
		#print "acc.left_change = #{acc.left_change}, acc.right_change = #{acc.right_change}\n"
		$TRACE.debug 1, "acc.left_change = #{acc.left_change}, acc.right_change = #{acc.right_change}"

		#determine relationship between changes (based on whether one or both exists)
		if acc.left_change && acc.right_change then
			relationship = acc.left_change.dest.relationship_to(acc.right_change.src)
		elsif acc.left_change && !acc.right_change then
			relationship = ChangeRange::ABOVE
		elsif !acc.left_change && acc.right_change then
			relationship = ChangeRange::BELOW
		else
			break
		end

		$TRACE.debug 1, "relationship = #{relationship}\n"
		# combine and advance to next change based on relationship
		case relationship
		when ChangeRange::ABOVE
			acc.left_change.destStart -= acc.dest_offset
			acc.left_change.destEnd -= acc.dest_offset
			diffOutFile.put_change(acc.left_change)
			#srcOffset += acc.left_change.addLines.size - acc.left_change.deleteLines.size
			acc.left_change = diffFile_left.get_change
		when ChangeRange::BELOW
			acc.right_change.srcStart -= acc.src_offset
			acc.right_change.srcEnd -= acc.src_offset
			diffOutFile.put_change(acc.right_change)
			#destOffset += acc.right_change.deleteLines.size - acc.right_change.addLines.size
			acc.right_change = diffFile_right.get_change
			
=begin
		when ChangeRange::ADJACENT_ABOVE, ChangeRange::OVERLAPS_ABOVE, ChangeRange::CONTAINS
			handle_overlap(diffFile_left, diffFile_right, diffOutFile, 
								acc.left_change, acc.right_change, :src, 
								Accumulator::LEFT, Accumulator::RIGHT, acc)
		when ChangeRange::ADJACENT_BELOW, ChangeRange::OVERLAPS_BELOW, ChangeRange::CONTAINED_BY
			handle_overlap(diffFile_right, diffFile_left, diffOutFile, 
								acc.right_change, acc.left_change, :dest, 
								Accumulator::RIGHT, Accumulator::LEFT, acc)
=end
		when ChangeRange::ADJACENT_ABOVE, ChangeRange::OVERLAPS_ABOVE
			handle_overlap(diffFile_left, diffFile_right, diffOutFile, 
								acc.left_change, acc.right_change,  
								Accumulator::LEFT, Accumulator::RIGHT, acc)
		when ChangeRange::ADJACENT_BELOW, ChangeRange::OVERLAPS_BELOW
			handle_overlap(diffFile_right, diffFile_left, diffOutFile, 
								acc.right_change, acc.left_change, 
								Accumulator::RIGHT, Accumulator::LEFT, acc)
		when ChangeRange::CONTAINS, ChangeRange::EQUAL
			handle_overlap(diffFile_right, diffFile_left, diffOutFile, 
								acc.right_change, acc.left_change, 
								Accumulator::RIGHT, Accumulator::LEFT, acc)
		when ChangeRange::CONTAINED_BY
			handle_overlap(diffFile_left, diffFile_right, diffOutFile, 
								acc.left_change, acc.right_change, 
								Accumulator::LEFT, Accumulator::RIGHT, acc)
		else
			raise "Unknown relationship = #{relationship}"
		end
	end
	
	diffFile_left.close
	diffFile_right.close
	diffOutFile.close
end

#
# apply the difference 
#
def apply_diff(in_filename, diff_changes_array, out_filename, invertChanges=false)
	$TRACE.debug 5, "infile = '#{File.data(in_filename).x}'\n"
	diff_changes_array = diff_changes_array.map do |dc|
		if dc.kind_of?(String) then
			FileChanges.new(dc)
		else
			dc
		end
	end
	
	diff_changes_array.each do |diff_changes|
		$TRACE.debug 5, "diff_changes = '#{diff_changes.content}'\n"
	end

	has_conflict = false

	begin
		infile = File.new(in_filename)
		outfile = File.new(out_filename, "w")
		#difffile = FileChanges.new(diff_filename)

		applyDiffFiles = ApplyDiffFiles.new(diff_changes_array, invertChanges)
		linenum = 0
		getNextChange = true
		change = nil
		changes = nil
		highest_linenum = nil
		lowest_linenum = nil
		
		deleteLines = []
		conflictLines = []
		line = nil
		while true
		#infile.each_line do |line|
			#line.chop!
			
			if getNextChange then
=begin
				change = difffile.get_change
				change.invert! if change && invertChanges
=end
				deleteLines = []
				getNextChange = false

				changes = applyDiffFiles.get_changes
				
				# get lowest change
				change = changes.lowest_start

				if change then
					$TRACE.debug 3, "linenum = #{linenum}, change.srcStart = #{change.srcStart}, line = '#{line}'"
					
					# get lowest and highest line numbers if there is a conflict
					if changes.size > 1 then
						lowest_linenum = change.srcStart
						highest_linenum = changes.highest_end.srcEnd 
					end
				end
			end		

			# if there is no active change or there is an active change and it doesn't start at zero
			if !change ||
				change && change.srcStart != 0 then
				line = infile.gets
				if !line then
					break
				else
					line.chop!
					linenum += 1
				end
			end
				
			# if don't have an active change OR we haven't reached the start of the change yet
			if !change ||
			   linenum < change.srcStart then
			   	# put out the input line
			   	outfile.puts line

			else
			
				# if there was only one change (and that means no conflict)
			
				if changes.size == 1 then	
					
					$TRACE.debug 3, "got change = #{change}"
					# change is an ADDITION
					if change.chgType == Change::ADDITION then
						outfile.puts line if linenum != 0
						change.addLines.each { |l| outfile.puts l}
						getNextChange = true
					# change is DELETION or CHANGE
					else
						# save the deleted lines
						deleteLines.push(line)

						# if done reading past the deleted lines
						if linenum == change.srcEnd then
							# the deleted lines should match the ones we just passed
							if (deleteLines != change.deleteLines) then
								raise "diff does not apply to file '#{deleteLines.inspect}' != '#{change.deleteLines.inspect}'"
							end

							# if its a CHANGE
							if change.chgType == Change::CHANGE then
								# add the new lines in
								change.addLines.each {|l| outfile.puts l}
							end
							getNextChange = true
						end
					end

				# if there is more than one change 
				else
					has_conflict = true
					
					conflictLines.push(line) if linenum != 0
					if linenum == highest_linenum then
						outfile.puts "== #{in_filename}"	
						conflictLines.each {|conflict_line| outfile.print "  ", conflict_line, "\n"}
						applyDiffFiles.each do |adf|
							if adf.conflicts == [] then
								next
							else
								$TRACE.debug 5, "adf = #{adf}"
								outfile.puts "== #{adf.diffFile.filename}"
								conflict_linenum = lowest_linenum
								curChange = adf.conflicts.shift
								conflictLines.each do |conflict_line|
									$TRACE.debug 5, "in conflict loop, line # = #{conflict_linenum}, line = '#{conflict_line}'"
									
									# if we are before or after the change
									if conflict_linenum < curChange.srcStart || conflict_linenum > curChange.srcEnd  then
										$TRACE.debug 5, "in not in change: putting out conflict_line '#{conflict_line}'"
										outfile.print "  ", conflict_line, "\n"

									# if during the lines of a change
									else 
										$TRACE.debug 5, "in conflict output, curChange = #{curChange}"
										
										case curChange.chgType
										when Change::DELETION
											if curChange.srcStart <= conflict_linenum && conflict_linenum <= curChange.srcEnd then
												$TRACE.debug 5, "in DELETION: adding conflict_line '#{conflict_line}'"
												outfile.print "< ", conflict_line, "\n"
											end
											
										when Change::ADDITION
											if conflict_linenum == curChange.srcStart then
												outfile.print "  ", conflict_line, "\n"
												curChange.addLines.each do |add_line|
													$TRACE.debug 5, "in ADDITION: adding line '#{add_line}'"
													outfile.print "> ", add_line, "\n"
												end
											end
											
										when Change::CHANGE
											if conflict_linenum == curChange.srcEnd then
												curChange.addLines.each do |add_line|
													$TRACE.debug 5, "in CHANGE: adding line '#{add_line}'"
													outfile.print "> ", add_line, "\n"
												end
											end
										end # case change type
									end #if before or after a change
									
									conflict_linenum += 1
									
									# if we are past the current change and there are more then 
									if conflict_linenum > curChange.srcEnd && adf.conflicts.size > 0 then
										# try to get the next one
										curChange = adf.conflicts.shift
									end
								end #conflictLines.each

								# the only way this could happen is that there is a conflict on an addition at the zeroth line (before the first line)
								if conflictLines == [] then
									$TRACE.debug 5, "in conflict on zeroeth line"
									curChange.addLines.each do |add_line|
										$TRACE.debug 5, "in ADDITION: adding line '#{add_line}'"
										outfile.print "> ", add_line, "\n"
									end
								end
								
								adf.clear_conflicts
							end #adf.conflicts == []
						end #applyDiffFiles.each
						outfile.puts "================="	
						
						getNextChange = true
						conflictLines = []
					end
					
	#						$TRACE.debug 5, "got conflict, changes = #{changes}"
	#						raise "got conflict"
				end
			end
			# linenum += 1
		end # while true

	ensure
		infile.close
		outfile.close
		#difffile.close
	
		applyDiffFiles.close
	end
	
	$TRACE.debug 5, "has_conflict = #{has_conflict}, outfile = '#{File.data(out_filename).x}'\n"

	return has_conflict
end

def generate_diff(file1, file2, outfile)
	outfile = outfile.gsub("/", "\\")
	#print("running: diff #{file1} #{file2} >#{outfile}\n")
	system("diff #{file1} #{file2} >#{outfile}")
end

end # defining module functions
end #module Diff
