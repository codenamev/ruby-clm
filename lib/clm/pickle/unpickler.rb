# frozen_string_literal: true

module CLM
  module Pickle
    # The pickle virtual machine: a stack, a mark stack and a memo.
    #
    # Python values map to Ruby as: dict -> Hash, list -> Array, tuple -> frozen
    # Array, str -> UTF-8 String, bytes -> binary String, int -> Integer,
    # float -> Float, None/True/False -> nil/true/false.
    class Unpickler
      # Resolves nothing: a pickle that names any global is refused.
      REFUSE = ->(mod, name) { raise UnpicklingError, "global #{mod}.#{name} is not allowed" }

      def initialize(io, find_class: REFUSE, persistent_load: nil)
        @io = io
        @find_class = find_class
        @persistent_load = persistent_load
        @stack = []
        @marks = []
        @memo = {}
      end

      def load
        loop do
          opcode = @io.getbyte or raise UnpicklingError, "pickle data was truncated"
          handler = OPCODES.fetch(opcode) do
            raise UnpicklingError, format("unsupported pickle opcode 0x%<op>02x", op: opcode)
          end
          return @stack.pop if handler == :stop

          send(handler)
        end
      end

      OPCODES = {
        0x80 => :op_proto, 0x95 => :op_frame, 0x2e => :stop,
        0x28 => :op_mark, 0x31 => :op_pop_mark, 0x30 => :op_pop, 0x32 => :op_dup,
        0x4e => :op_none, 0x88 => :op_true, 0x89 => :op_false,
        0x4a => :op_binint, 0x4b => :op_binint1, 0x4d => :op_binint2, 0x8a => :op_long1, 0x8b => :op_long4,
        0x47 => :op_binfloat,
        0x58 => :op_binunicode, 0x8c => :op_short_binunicode, 0x8d => :op_binunicode8,
        0x54 => :op_binstring, 0x55 => :op_short_binstring,
        0x42 => :op_binbytes, 0x43 => :op_short_binbytes, 0x8e => :op_binbytes8, 0x96 => :op_bytearray8,
        0x29 => :op_empty_tuple, 0x74 => :op_tuple, 0x85 => :op_tuple1, 0x86 => :op_tuple2, 0x87 => :op_tuple3,
        0x5d => :op_empty_list, 0x6c => :op_list, 0x61 => :op_append, 0x65 => :op_appends,
        0x7d => :op_empty_dict, 0x64 => :op_dict, 0x73 => :op_setitem, 0x75 => :op_setitems,
        0x8f => :op_empty_set, 0x90 => :op_additems, 0x91 => :op_frozenset,
        0x71 => :op_binput, 0x72 => :op_long_binput, 0x94 => :op_memoize,
        0x68 => :op_binget, 0x6a => :op_long_binget,
        0x63 => :op_global, 0x93 => :op_stack_global,
        0x52 => :op_reduce, 0x81 => :op_newobj, 0x92 => :op_newobj_ex, 0x62 => :op_build,
        0x51 => :op_binpersid
      }.freeze

      private

      def read(n)
        bytes = @io.read(n)
        raise UnpicklingError, "pickle data was truncated" if bytes.nil? || bytes.bytesize < n

        bytes
      end

      def read_line
        @io.gets("\n")&.chomp or raise UnpicklingError, "pickle data was truncated"
      end

      def uint(n, directive)
        read(n).unpack1(directive)
      end

      def pop_mark
        mark = @marks.pop or raise UnpicklingError, "MARK expected"
        @stack.slice!(mark..)
      end

      # --- framing and control
      def op_proto = read(1)
      def op_frame = read(8)
      def op_mark = @marks.push(@stack.size)
      def op_pop_mark = pop_mark
      def op_pop = @stack.pop
      def op_dup = @stack.push(@stack.last)

      # --- scalars
      def op_none = @stack.push(nil)
      def op_true = @stack.push(true)
      def op_false = @stack.push(false)
      def op_binint = @stack.push(uint(4, "l<"))
      def op_binint1 = @stack.push(uint(1, "C"))
      def op_binint2 = @stack.push(uint(2, "S<"))
      def op_long1 = @stack.push(decode_long(read(uint(1, "C"))))
      def op_long4 = @stack.push(decode_long(read(uint(4, "l<"))))
      def op_binfloat = @stack.push(uint(8, "G"))

      # Little-endian two's complement.
      def decode_long(bytes)
        return 0 if bytes.empty?

        value = bytes.reverse.unpack1("H*").to_i(16)
        bytes.getbyte(-1) >= 0x80 ? value - (1 << (8 * bytes.bytesize)) : value
      end

      # --- strings and bytes
      def op_binunicode = @stack.push(read(uint(4, "L<")).force_encoding(Encoding::UTF_8))
      def op_short_binunicode = @stack.push(read(uint(1, "C")).force_encoding(Encoding::UTF_8))
      def op_binunicode8 = @stack.push(read(uint(8, "Q<")).force_encoding(Encoding::UTF_8))
      def op_binstring = @stack.push(read(uint(4, "l<")))
      def op_short_binstring = @stack.push(read(uint(1, "C")))
      def op_binbytes = @stack.push(read(uint(4, "L<")))
      def op_short_binbytes = @stack.push(read(uint(1, "C")))
      def op_binbytes8 = @stack.push(read(uint(8, "Q<")))
      def op_bytearray8 = @stack.push(read(uint(8, "Q<")))

      # --- containers
      def op_empty_tuple = @stack.push([].freeze)
      def op_tuple = @stack.push(pop_mark.freeze)
      def op_tuple1 = @stack.push(@stack.pop(1).freeze)
      def op_tuple2 = @stack.push(@stack.pop(2).freeze)
      def op_tuple3 = @stack.push(@stack.pop(3).freeze)
      def op_empty_list = @stack.push([])
      def op_list = @stack.push(pop_mark)
      def op_empty_dict = @stack.push({})
      def op_dict = @stack.push(pop_mark.each_slice(2).to_h)
      def op_empty_set = @stack.push(Set.new)
      def op_frozenset = @stack.push(Set.new(pop_mark).freeze)

      def op_append
        item = @stack.pop
        @stack.last.push(item)
      end

      def op_appends
        items = pop_mark
        @stack.last.concat(items)
      end

      def op_setitem
        value = @stack.pop
        key = @stack.pop
        @stack.last[key] = value
      end

      def op_setitems
        pairs = pop_mark
        target = @stack.last
        pairs.each_slice(2) { |key, value| target[key] = value }
      end

      def op_additems
        items = pop_mark
        @stack.last.merge(items)
      end

      # --- memo
      def op_binput = @memo[uint(1, "C")] = @stack.last
      def op_long_binput = @memo[uint(4, "L<")] = @stack.last
      def op_memoize = @memo[@memo.size] = @stack.last
      def op_binget = @stack.push(memo_get(uint(1, "C")))
      def op_long_binget = @stack.push(memo_get(uint(4, "L<")))

      def memo_get(index)
        @memo.fetch(index) { raise UnpicklingError, "memo key #{index} was never stored" }
      end

      # --- objects
      def op_global = @stack.push(@find_class.call(read_line, read_line))

      def op_stack_global
        name = @stack.pop
        @stack.push(@find_class.call(@stack.pop, name))
      end

      def op_reduce
        args = @stack.pop
        @stack.push(construct(@stack.pop, args))
      end

      def op_newobj
        args = @stack.pop
        @stack.push(construct(@stack.pop, args))
      end

      def op_newobj_ex
        kwargs = @stack.pop
        args = @stack.pop
        @stack.push(construct(@stack.pop, args, kwargs))
      end

      def construct(callable, args, kwargs = {})
        raise UnpicklingError, "#{callable} cannot be called while unpickling" unless callable.respond_to?(:call)

        kwargs.empty? ? callable.call(*args) : callable.call(*args, **kwargs.transform_keys(&:to_sym))
      end

      # BUILD sets an object's state.  Objects that understand +__setstate__+ get it;
      # plain hashes (an OrderedDict's +_metadata+) and arrays keep their items and ignore it.
      def op_build
        state = @stack.pop
        target = @stack.last
        target.__setstate__(state) if target.respond_to?(:__setstate__)
      end

      def op_binpersid
        raise UnpicklingError, "persistent id found but no persistent_load was given" unless @persistent_load

        @stack.push(@persistent_load.call(@stack.pop))
      end
    end
  end
end
