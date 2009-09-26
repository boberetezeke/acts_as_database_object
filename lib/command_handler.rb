module ODRails
	class CommandHandler
		def initialize(controller)
			@controller = controller
		end

		def handle_command
		end

		def method_missing(sym, *args, &block)
			# forward any calls to the controller
			@controller.send(sym, *args, &block)
		end
	end
end

Dependencies.load_paths.push("#{RAILS_ROOT}/app/command_handlers")
