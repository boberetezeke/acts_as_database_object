# this is only for Windows
if RUBY_PLATFORM == "i386-mswin32" then

require 'Win32API' 

def system(command)
  Win32API.new("crtdll", "system", ['P'], 'L').Call(command)
end 

def `(command)
  popen = Win32API.new("crtdll", "_popen", ['P','P'], 'L')
  pclose = Win32API.new("crtdll", "_pclose", ['L'], 'L')
  fread = Win32API.new("crtdll", "fread", ['P','L','L','L'], 'L')
  feof = Win32API.new("crtdll", "feof", ['L'], 'L')
  saved_stdout = $stdout.clone
  psBuffer = " " * 128
  rBuffer = ""
  f = popen.Call(command,"r")
  while feof.Call( f )==0
      l = fread.Call( psBuffer,1,128,f )
      rBuffer += psBuffer[0..l]
  end
  pclose.Call f
  $stdout.reopen(saved_stdout)
  rBuffer
end

end
