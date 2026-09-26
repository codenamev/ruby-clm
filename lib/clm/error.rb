# frozen_string_literal: true

module CLM
  # Base class of every error this library raises.
  class Error < StandardError; end

  # A question, answer or request that does not follow the System One schema.
  class InvalidRequestError < Error; end

  # A model name that no loaded checkpoint serves.
  class ModelNotFoundError < InvalidRequestError; end

  # The encoder's /v1/embeddings endpoint could not be reached or refused a request.
  class EmbedderError < Error; end

  # A server that could not be reached at all (refused, reset or timed out).
  class ConnectionError < Error; end

  # A checkpoint file that cannot be read as a CLM projection-head pair.
  class CheckpointError < Error; end

  # A non-success response from a CLM server.  +status+ is the HTTP status and
  # +message+ the server's explanation (FastAPI-style +detail+ when present).
  class APIError < Error
    attr_reader :status, :response

    def initialize(message = nil, status: nil, response: nil)
      @status = status
      @response = response
      super(status ? "#{status}: #{message}" : message)
    end

    STATUSES = {} # rubocop:disable Style/MutableConstant -- filled in below, then frozen

    # The APIError subclass for an HTTP +status+.
    def self.for_status(status)
      STATUSES.fetch(status) { status.to_i >= 500 ? ServerError : APIError }
    end
  end

  class UnauthorizedError < APIError; end
  class UnprocessableEntityError < APIError; end
  class ServerError < APIError; end
  class BadGatewayError < ServerError; end
  class ServiceUnavailableError < ServerError; end

  APIError::STATUSES.merge!(
    401 => UnauthorizedError,
    422 => UnprocessableEntityError,
    502 => BadGatewayError,
    503 => ServiceUnavailableError
  ).freeze
end
