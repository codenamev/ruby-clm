# frozen_string_literal: true

require "fileutils"
require "net/http"

module CLM
  # Fetches projection-head checkpoints from the Hugging Face Hub.
  #
  # The reference head is Contrastive-LM/CLM-v0.1-8B (CLM_v0.1-8B.pt, trained
  # against Qwen3-8B last-token pooling).
  #
  #   CLM::Hub.download # => "~/.cache/clm/CLM_v0.1-8B.pt"
  module Hub
    REPO = "Contrastive-LM/CLM-v0.1-8B"
    FILENAME = "CLM_v0.1-8B.pt"
    ENDPOINT = "https://huggingface.co"
    MAX_REDIRECTS = 5

    class DownloadError < CLM::Error; end

    module_function

    # Downloads +filename+ from +repo+ into +dest_dir+ unless it is already there,
    # and returns the local path.  HF_TOKEN, when set, authorises gated repos.
    def download(repo: REPO, filename: FILENAME, dest_dir: CLM.config.checkpoint_dir, force: false,
                 token: ENV.fetch("HF_TOKEN", nil))
      dest = File.join(dest_dir, filename)
      return dest if File.exist?(dest) && !force

      FileUtils.mkdir_p(dest_dir)
      count_download(repo)
      partial = "#{dest}.part"
      File.open(partial, "wb") { |file| stream(URI("#{ENDPOINT}/#{repo}/resolve/main/#{filename}"), file, token) }
      File.rename(partial, dest)
      dest
    ensure
      FileUtils.rm_f(partial) if partial && File.exist?(partial)
    end

    # The checkpoint served as clm-latest when none is given: CLM_CKPT if it exists,
    # else the reference head in the checkpoint directory if it was downloaded.
    def default_checkpoint(config = CLM.config)
      [config.checkpoint, File.join(config.checkpoint_dir, FILENAME)].compact.find { File.exist?(_1) }
    end

    # The Hub counts a model download per request to the repo's config.json
    # (https://huggingface.co/docs/hub/models-download-stats); best-effort, never fails.
    def count_download(repo)
      uri = URI("#{ENDPOINT}/#{repo}/resolve/main/config.json")
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 5) do |http|
        http.head(uri.request_uri)
      end
    rescue StandardError
      nil
    end

    def stream(uri, io, token, redirects = 0)
      raise DownloadError, "too many redirects fetching #{uri}" if redirects > MAX_REDIRECTS

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 600) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}" if token && uri.host == URI(ENDPOINT).host
        http.request(request) do |response|
          case response
          when Net::HTTPSuccess then response.read_body { io.write(_1) }
          when Net::HTTPRedirection then return stream(URI.join(uri, response["location"]), io, token, redirects + 1)
          else raise DownloadError, "GET #{uri} failed: #{response.code} #{response.message}"
          end
        end
      end
    end
    private_class_method :stream
  end
end
