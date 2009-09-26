def File.split3(filename)
	a = File.split(filename)
	name = a[1]
	path = a[0]
	if name != "." && name != ".." then
		#print "got second match '#{$1}', '#{$2}'\n"
		name =~ %r{([^.]*)(\.(.*))?}
		name = $1
		ext = $3
	else
		ext = ""
	end
	return [path, name, ext]
end

def File.extname(filename)
	a = File.split3(filename)
	return a[2]
end

def File.data(filename)
	data = nil
	File.open(filename) {|f| data = f.read}
	data
end

def File.join2(path1, path2)
	end_path1 = path1[-1..-1]
	start_path2 = path2[0..0]
	if end_path1 != "/" && start_path2 != "/" then
		return path1 + "/" + path2
	elsif end_path1 == "/" && start_path2 == "/" then
		return path1[0..-2] + path1
	else
		return path1 + path2
	end
end
