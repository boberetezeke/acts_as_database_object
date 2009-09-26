# Put your code that runs your task inside the do_work method
# it will be run automatically in a thread. You have access to
# all of your rails models if you set load_rails to true in the
# config file. You also get @logger inside of this class by default.
class CommandWorker < BackgrounDRb::Rails
  attr_reader :current_command

  def do_work(args)
    #puts "CommandWorker: at beginning of do_work"
    @evaluation_start_mutex = Mutex.new
    @evaluation_done_mutex = Mutex.new
    @evaluate_now = ConditionVariable.new
    @evaluate_done = ConditionVariable.new
    #puts "CommandWorker: before call to evaluate_loop eval start mutex = " + 
          "#{@evaluation_start_mutex.inspect}"
    evaluate_loop
    #puts "CommandWorker: at end of do_work"
  end

  def evaluate(command)
    #puts "CommandWorker: evaluate - '#{command}'"
    @evaluate_command = command
    #puts "CommandWorker: in evaluate eval start mutex = " +  
          "#{@evaluation_start_mutex.inspect}"
    @evaluation_start_mutex.synchronize { @evaluate_now.signal }
    #puts "before wait for evaluate done"
    @evaluation_done_mutex.synchronize do
      @evaluate_done.wait(@evaluation_done_mutex) 
    end
    #puts "after wait for evaluate done"
    return @current_command.attributes["id"]
  end

  def evaluate_loop()
    Thread.new do
      while true
        #puts "before wait for evaluate now #{@evaluate_now.inspect}"
        @evaluation_start_mutex.synchronize do
          @evaluate_now.wait(@evaluation_start_mutex)
        end

        $LOG = SimpleTracer.new
        log_string_io = StringIO.new
        $LOG.set_output_io(log_string_io)
        
        #puts "got evaluate now, evaluate_command = #{@evaluate_command}"
        str_result = nil
        @current_command = Command.new(:command => @evaluate_command, 
                             :when_created => Time.now, :output => "")
        @current_command.save

        inspect_str = nil
        str_result = nil
        begin
          # Make sure all ruby code is up to date
          ObjectDatabaseRuby.find(:all).each do |r|
            puts "evaling: #{r.content.to_s}"
            Object.module_eval(r.content.to_s)
          end

          puts "evaluating command = '#{@evaluate_command}'"
          object = Object.module_eval(@evaluate_command)
          inspect_str = object.inspect
          puts "evaluating command ret = #{inspect_str}"
          puts "evaluating command object_id = " + sprintf("0x%8.8x", object.object_id)
        rescue Exception => e
          str_result = e.message
        end
puts "before unless str_result"
        unless str_result
          begin
puts "before inspect parser"
            str_result = InspectParser.new(inspect_str, 
              CommandHelper::ActiveRecordProxyConstructor.new).parse.inspect
puts "after inspect parser, str_result = #{str_result}"
          rescue Exception => e
puts "inspect parser exception: #{e.message}"
puts "backtrace: "
puts e.backtrace.join("\n")
            str_result = "ERROR: #{e.message} when parsing inspect of " + 
                         "'#{str_result}'"
          end
        end
puts "before setting command result"
        @current_command.result = str_result #BigString.new(str_result)
puts "before log_string_io.seek"
        log_string_io.seek(0)
puts "before @current_command.output = log_string_io.read"
        @current_command.output = log_string_io.read
puts "before @current_command.save"
        @current_command.save
        puts "before signalling evaluation_done"
        @evaluation_done_mutex.synchronize { @evaluate_done.signal }
        puts "after signalling evaluation_done"
      end
    end
  end
end
