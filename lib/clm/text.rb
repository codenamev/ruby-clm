# frozen_string_literal: true

module CLM
  # Renders states and descriptions as the prose the heads were trained on.
  #
  # A state may be a string, a hash or an array.  The heads never saw JSON, so a
  # hash becomes +key: value+ fields (top-level fields separated by a blank line,
  # nested ones indented) and an array becomes one +- item+ line per element.
  # Key order is preserved.
  #
  #   CLM::Text.render({ user: "ada", cart: %w[tea milk] })
  #   # => "user: ada\n\ncart:\n  - tea\n  - milk"
  module Text
    module_function

    def render(value, indent = 0)
      case value
      when nil then ""
      when String then value
      when Symbol, Numeric, true, false then value.to_s
      when Hash then render_hash(value, indent)
      when Array then render_array(value, indent)
      else value.respond_to?(:to_h) ? render_hash(value.to_h, indent) : value.to_s
      end
    end

    # Context first, question last: the layout the state head was trained on.
    def state(state, instructions)
      [render(state).strip, render(instructions).strip].reject(&:empty?).join("\n\n")
    end

    def render_hash(hash, indent)
      pad = " " * indent
      parts = hash.map do |key, value|
        nested?(value) ? "#{pad}#{key}:\n#{render(value, indent + 2)}" : "#{pad}#{key}: #{render(value)}"
      end
      parts.join(indent.zero? ? "\n\n" : "\n")
    end

    def render_array(array, indent)
      pad = " " * indent
      array.map { |value| nested?(value) ? "#{pad}-\n#{render(value, indent + 2)}" : "#{pad}- #{render(value)}" }
           .join("\n")
    end

    def nested?(value)
      (value.is_a?(Hash) || value.is_a?(Array)) && !value.empty?
    end

    private_class_method :render_hash, :render_array, :nested?
  end
end
