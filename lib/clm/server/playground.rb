# frozen_string_literal: true

require "rack/files"

module CLM
  class Server
    # The playground: index.html, app.css and app.js, no build step.
    #
    # Every file is sent with +Cache-Control: no-cache+ (revalidated, still 304 when
    # unchanged), and the page references its assets with a +?v=+ stamp of their
    # newest mtime, so upgrading the gem can never leave a stale UI in a browser.
    class Playground
      ROOT = File.expand_path("static", __dir__)
      FILES = %w[index.html app.css app.js].freeze

      def initialize(root: ROOT)
        @root = root
        @files = Rack::Files.new(root, { "cache-control" => "no-cache" })
      end

      def serves?(request)
        (request.get? || request.head?) && (index?(request.path_info) || FILES.include?(asset(request.path_info)))
      end

      def call(env)
        return index if index?(env["PATH_INFO"])

        @files.call(env)
      end

      private

      def index?(path)
        ["/", "", "/index.html"].include?(path)
      end

      def asset(path)
        path.delete_prefix("/")
      end

      def index
        stamp = FILES.map { File.mtime(File.join(@root, _1)).to_i }.max.to_s(16)
        html = File.read(File.join(@root, "index.html"), encoding: Encoding::UTF_8)
                   .sub('href="app.css"', %(href="app.css?v=#{stamp}"))
                   .sub('src="app.js"', %(src="app.js?v=#{stamp}"))
        [200, { "content-type" => "text/html; charset=utf-8", "cache-control" => "no-cache" }, [html]]
      end
    end
  end
end
