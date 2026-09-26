# frozen_string_literal: true

require "numo/narray"
require "zip"

module CLM
  # Reads a file written by +torch.save+ into plain Ruby objects, no LibTorch needed.
  #
  # The file is a zip archive holding +data.pkl+ (the pickled object graph) and one
  # raw little-endian blob per tensor storage under +data/+.  Tensors come back as
  # Numo arrays of their shape (0-d tensors as plain numbers), dicts as hashes.
  # Only the globals a checkpoint legitimately uses are allowed; anything else is
  # refused rather than executed.
  #
  #   checkpoint = CLM::TorchFile.load("CLM_v0.1-8B.pt")
  #   checkpoint["state_head"]["inp.weight"] # => Numo::SFloat#shape=[2048,4096]
  class TorchFile
    # A tensor storage type, as named by the pickle ("torch.FloatStorage" or "torch.float32").
    DType = Data.define(:name, :numo, :bytesize, :decoder)

    DTYPES = [
      DType.new("Float", Numo::SFloat, 4, nil), DType.new("Double", Numo::DFloat, 8, nil),
      DType.new("Half", Numo::SFloat, 2, :half), DType.new("BFloat16", Numo::SFloat, 2, :bfloat16),
      DType.new("Long", Numo::Int64, 8, nil), DType.new("Int", Numo::Int32, 4, nil),
      DType.new("Short", Numo::Int16, 2, nil), DType.new("Char", Numo::Int8, 1, nil),
      DType.new("Byte", Numo::UInt8, 1, nil), DType.new("Bool", Numo::UInt8, 1, nil)
    ].to_h { [_1.name, _1] }.freeze

    # torch.<dtype> names used by newer pickles (TypedStorage)
    DTYPE_ALIASES = {
      "float32" => "Float", "float" => "Float", "float64" => "Double", "double" => "Double",
      "float16" => "Half", "half" => "Half", "bfloat16" => "BFloat16", "int64" => "Long", "long" => "Long",
      "int32" => "Int", "int" => "Int", "int16" => "Short", "short" => "Short", "int8" => "Char",
      "uint8" => "Byte", "bool" => "Bool"
    }.freeze

    HOST_BYTEORDER = [1].pack("S") == [1].pack("v") ? "little" : "big"

    # torch.save stamps every entry 1980-00-00, which rubyzip would warn about per entry.
    Zip.warn_invalid_date = false

    def self.load(path)
      new(path).load
    end

    def initialize(path)
      @path = path.to_s
      @storages = {}
    end

    def load
      Zip::File.open(@path) do |zip|
        @zip = zip
        pickle = zip.glob("**/data.pkl").min_by { _1.name.count("/") } or
          raise CheckpointError, "#{@path} is not a torch.save zip archive (no data.pkl)"
        @prefix = pickle.name.delete_suffix("data.pkl")
        @byteorder = read_entry("byteorder")&.strip || "little"
        Pickle.load(pickle.get_input_stream.read, find_class: method(:find_class),
                                                  persistent_load: method(:persistent_load))
      end
    rescue Zip::Error => e
      raise CheckpointError, "#{@path} is not a torch.save zip archive: #{e.message}"
    ensure
      @zip = nil
    end

    private

    def read_entry(name)
      @zip.find_entry("#{@prefix}#{name}")&.get_input_stream&.read
    end

    def find_class(mod, name)
      constructor = CONSTRUCTORS[[mod, name]]
      return constructor.is_a?(Symbol) ? method(constructor) : constructor if constructor

      dtype(mod, name) or
        raise CheckpointError, "#{@path} uses #{mod}.#{name}, which a projection-head checkpoint never needs"
    end

    CONSTRUCTORS = {
      %w[collections OrderedDict] => ->(pairs = []) { pairs.to_h },
      %w[torch._utils _rebuild_tensor_v2] => :rebuild_tensor,
      %w[torch._utils _rebuild_tensor] => :rebuild_tensor,
      %w[torch._utils _rebuild_parameter] => ->(data, *) { data },
      %w[torch._utils _rebuild_parameter_with_state] => ->(data, *) { data },
      %w[torch Size] => ->(dims) { dims },
      %w[_codecs encode] => ->(text, _encoding) { text.encode(Encoding::ISO_8859_1).b },
      %w[__builtin__ set] => ->(items = []) { Set.new(items) },
      %w[builtins set] => ->(items = []) { Set.new(items) }
    }.freeze
    private_constant :CONSTRUCTORS

    # torch.FloatStorage (legacy storages) or torch.float32 (typed storages)
    def dtype(mod, name)
      return unless mod == "torch"

      DTYPES[name.delete_suffix("Storage")] || DTYPES[DTYPE_ALIASES[name]]
    end

    # ("storage", storage_type, key, location, numel) -> a flat Numo array of the storage.
    def persistent_load(pid)
      kind, dtype, key, _location, _numel = pid
      raise CheckpointError, "unknown persistent id #{kind.inspect}" unless kind == "storage" && dtype.is_a?(DType)

      @storages[key] ||= decode(dtype, read_entry("data/#{key}") ||
                                       raise(CheckpointError, "#{@path} is missing storage data/#{key}"))
    end

    def decode(dtype, bytes)
      raw = case dtype.decoder
            when :half then half_to_single(Numo::UInt16.from_binary(bytes))
            when :bfloat16 then Numo::SFloat.from_binary((Numo::UInt32.cast(Numo::UInt16.from_binary(bytes)) << 16)
                                                          .to_binary)
            else dtype.numo.from_binary(bytes)
            end
      @byteorder == HOST_BYTEORDER || dtype.bytesize == 1 || dtype.decoder ? raw : raw.swap_byte
    end

    # IEEE 754 binary16 -> binary32 (Numo has no half type): re-bias the exponent
    # and widen the mantissa, keep infinities and NaNs, and scale subnormals.
    def half_to_single(bits)
      bits = bits.swap_byte unless @byteorder == HOST_BYTEORDER
      u = Numo::UInt32.cast(bits)
      sign = u >> 15
      exponent = (u >> 10) & 0x1f
      mantissa = u & 0x3ff
      single = (sign << 31) | ((exponent + 112) << 23) | (mantissa << 13)
      special = exponent.eq(31)
      single[special] = ((sign << 31) | (0xff << 23) | (mantissa << 13))[special] if special.any?
      Numo::SFloat.from_binary(single.to_binary).tap { |out| fix_subnormals(out, exponent.eq(0), sign, mantissa) }
    end

    def fix_subnormals(out, subnormal, sign, mantissa)
      return unless subnormal.any?

      signs = 1 - (2 * Numo::SFloat.cast(sign[subnormal]))
      out[subnormal] = Numo::SFloat.cast(mantissa[subnormal]) * (2.0**-24) * signs
    end

    def rebuild_tensor(storage, offset, size, stride, *)
      return storage[offset] if size.empty?

      numel = size.reduce(:*)
      if stride == contiguous_strides(size)
        storage[offset...(offset + numel)].reshape(*size).dup
      else
        storage[strided_index(offset, size, stride)].reshape(*size).dup
      end
    end

    def contiguous_strides(size)
      size.drop(1).reverse.each_with_object([1]) { |dim, strides| strides.unshift(strides.first * dim) }
    end

    # Flat storage positions of every element of a strided view, in row-major order.
    def strided_index(offset, size, stride)
      index = Numo::Int64.zeros(*size) + offset
      size.each_with_index do |dim, axis|
        shape = Array.new(size.size, 1).tap { _1[axis] = dim }
        index += Numo::Int64.new(dim).seq.reshape(*shape) * stride[axis]
      end
      index.flatten
    end
  end
end
