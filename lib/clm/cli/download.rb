# frozen_string_literal: true

require "optparse"

module CLM
  module CLI
    # clm-download: fetch a projection-head checkpoint and print its local path.
    #
    #   python train/finetune.py --init-ckpt "$(clm-download)"
    class Download
      def initialize(argv, out: $stdout)
        @argv = argv
        @out = out
        @options = { repo: Hub::REPO, filename: Hub::FILENAME, dest_dir: CLM.config.checkpoint_dir, force: false }
      end

      def run
        parser.parse!(@argv)
        @out.puts Hub.download(**@options)
      end

      private

      def parser
        OptionParser.new do |opts|
          opts.banner = "Usage: clm-download [options]\n\n" \
                        "Download a CLM projection-head checkpoint from the Hugging Face Hub.\n\n"
          opts.on("--repo REPO", "Hub repository (default: #{Hub::REPO})") { @options[:repo] = _1 }
          opts.on("--file FILE", "file in the repository (default: #{Hub::FILENAME})") { @options[:filename] = _1 }
          opts.on("--dest DIR", "directory to save into (default: #{@options[:dest_dir]})") { @options[:dest_dir] = _1 }
          opts.on("--force", "download even if the file is already there") { @options[:force] = true }
        end
      end
    end
  end
end
