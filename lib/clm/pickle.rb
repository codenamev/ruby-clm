# frozen_string_literal: true

require "stringio"

require_relative "pickle/unpickler"

module CLM
  # A small, safe reader for Python pickles (protocols 0-5, binary opcodes).
  #
  # Unlike Python's pickle it never imports or runs anything: every global a
  # pickle names is resolved through +find_class+, so only the constructors a
  # caller allows can be built.  That is all a PyTorch checkpoint needs.
  #
  #   CLM::Pickle.load(bytes, find_class: ->(mod, name) { ... }, persistent_load: ->(pid) { ... })
  module Pickle
    class UnpicklingError < CLM::Error; end

    # A global the caller's +find_class+ chose to leave unresolved (e.g. a dtype marker).
    Global = Data.define(:module_name, :name) do
      def to_s
        "#{module_name}.#{name}"
      end
    end

    def self.load(data, **)
      io = data.respond_to?(:read) ? data : StringIO.new(data.b)
      Unpickler.new(io, **).load
    end
  end
end
