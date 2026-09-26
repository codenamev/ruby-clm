# frozen_string_literal: true

require_relative "lib/clm/version"

Gem::Specification.new do |spec|
  spec.name = "clm"
  spec.version = CLM::VERSION
  spec.authors = ["Valentino Stoll"]
  spec.email = ["v@codenamev.com"]

  spec.summary = "Contrastive Language Models for Ruby: typed noul / choice / score questions over state"
  spec.description = <<~DESC
    A Ruby port of Contrastive-LM/CLM. Ask typed questions about a state and get answer
    distributions back from a System One model: an HTTP client for the CLM API, an
    in-process inference engine that loads PyTorch projection-head checkpoints without
    LibTorch, and a Rack server (clm-serve) with the playground UI.
  DESC
  spec.homepage = "https://github.com/codenamev/ruby-clm"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE", "NOTICE", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "falcon", "~> 0.47"
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "numo-narray", "~> 0.9"
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "rubyzip", ">= 2.3", "< 4"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
