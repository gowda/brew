require "development_tools"
module Cask
  module Quarantine
    module_function

    QUARANTINE_ATTRIBUTE = "com.apple.quarantine".freeze

    QUARANTINE_SCRIPT = (HOMEBREW_LIBRARY_PATH/"cask/utils/quarantine.swift").freeze

    # @private
    def swift
      @swift ||= DevelopmentTools.locate("swift")
    end

    def check_quarantine_support
      odebug "Checking quarantine support"

      if swift.nil?
        odebug "Swift is not available on this system."
        return :no_swift
      end

      api_check = system_command(swift, args: [QUARANTINE_SCRIPT])

      if api_check.exit_status == 5
        odebug "This feature requires the macOS 10.10 SDK or higher."
        return :no_quarantine
      end

      odebug "Quarantine is available."
      :quarantine_available
    end

    def available?
      @status ||= check_quarantine_support

      @status == :quarantine_available
    end

    def detect(file)
      return if file.nil?

      odebug "Verifying Gatekeeper status of #{file}"

      quarantine_status = !status(file).empty?

      odebug "#{file} is #{quarantine_status ? "quarantined" : "not quarantined"}"

      quarantine_status
    end

    def status(file)
      system_command("/usr/bin/xattr",
                     args:         ["-p", QUARANTINE_ATTRIBUTE, file],
                     print_stderr: false).stdout.rstrip
    end

    def cask(cask: nil, download_path: nil)
      return if cask.nil? || download_path.nil?

      odebug "Quarantining #{download_path}"

      quarantiner = system_command(swift,
                                   args: [
                                     QUARANTINE_SCRIPT,
                                     download_path,
                                     cask.url.to_s,
                                     cask.homepage.to_s,
                                   ])

      return if quarantiner.success?

      case quarantiner.exit_status
      when 2
        raise CaskQuarantineError.new(download_path, "Insufficient parameters")
      else
        raise CaskQuarantineError.new(download_path, quarantiner.stderr)
      end
    end

    def propagate(from: nil, to: nil)
      return if from.nil? || to.nil?

      raise CaskError, "#{from} was not quarantined properly." unless detect(from)

      odebug "Propagating quarantine from #{from} to #{to}"

      quarantine_status = status(from)

      resolved_paths = Pathname.glob(to/"**/*", File::FNM_DOTMATCH)

      quarantiner = system_command("/usr/bin/xargs",
                                   args: [
                                     "-0",
                                     "--",
                                     "/usr/bin/xattr",
                                     "-w",
                                     "-s",
                                     QUARANTINE_ATTRIBUTE,
                                     quarantine_status,
                                   ],
                                   input: resolved_paths.join("\0"),
                                   print_stderr: false)

      return if quarantiner.success?

      raise CaskQuarantinePropagationError.new(to, quarantiner.stderr)
    end
  end
end
