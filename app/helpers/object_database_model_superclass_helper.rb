module ObjectDatabaseModelSuperclassHelper
	def nothing_or_value(value)
		if !value then
			"<strong><i>nothing</i></strong>"
		elsif value == ""
			"<strong><i>blank</i></strong>"
		else
			"<strong>#{value}</strong>"
		end
	end

	def display_change(change)
		if change.kind_of?(SimpleChange) then
			"from #{nothing_or_value(change.oldValue)} to #{nothing_or_value(change.newValue)}"
		elsif change.kind_of?(DiffChange) then
			str = change.to_s
			str = "<br>" + str.gsub(/(\\r\\n|\\r|\\n)/, "<br>") + "<br>"
			str
		else
			"no display implemented for #{change.class}"
		end
	end
end
