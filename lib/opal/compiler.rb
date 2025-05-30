# frozen_string_literal: true

if RUBY_ENGINE == 'opal'
  require 'corelib/string/unpack'
end
require 'set'
require 'opal/parser'
require 'opal/fragment'
require 'opal/nodes'
require 'opal/eof_content'
require 'opal/errors'
require 'opal/magic_comments'
require 'opal/nodes/closure'
require 'opal/source_map'

module Opal
  # Compile a string of ruby code into javascript.
  #
  # @example
  #
  #     Opal.compile "ruby_code"
  #     # => "string of javascript code"
  #
  # @see Opal::Compiler.new for compiler options
  #
  # @param source [String] ruby source
  # @param options [Hash] compiler options
  # @return [String] javascript code
  #
  def self.compile(source, options = {})
    Compiler.new(source, options).compile
  end

  # {Opal::Compiler} is the main class used to compile ruby to javascript code.
  # This class uses {Opal::Parser} to gather the sexp syntax tree for the ruby
  # code, and then uses {Opal::Node} to step through the sexp to generate valid
  # javascript.
  #
  # @example
  #   Opal::Compiler.new("ruby code").compile
  #   # => "javascript code"
  #
  # @example Accessing result
  #   compiler = Opal::Compiler.new("ruby_code")
  #   compiler.compile
  #   compiler.result # => "javascript code"
  #
  # @example Source Maps
  #   compiler = Opal::Compiler.new("")
  #   compiler.compile
  #   compiler.source_map # => #<SourceMap:>
  #
  class Compiler
    include Nodes::Closure::CompilerSupport

    # Generated code gets indented with two spaces on each scope
    INDENT = '  '

    # All compare method nodes - used to optimize performance of
    # math comparisons
    COMPARE = %w[< > <= >=].freeze

    def self.module_name(path)
      path = File.join(File.dirname(path), File.basename(path).split('.').first)
      Pathname(path).cleanpath.to_s
    end

    # Defines a compiler option.
    # @option as: [Symbol] uses a different method name, e.g. with a question mark for booleans
    # @option default: [Object] the default value for the option
    # @option magic_comment: [Bool] allows magic-comments to override the option value
    def self.compiler_option(name, config = {})
      method_name = config.fetch(:as, name)
      define_method(method_name) { option_value(name, config) }
    end

    # Fetches and memoizes the value for an option.
    def option_value(name, config)
      return @option_values[name] if @option_values.key? name

      default_value = config[:default]
      valid_values  = config[:valid_values]
      magic_comment = config[:magic_comment]

      value = @options.fetch(name, default_value)

      if magic_comment && @magic_comments.key?(name)
        value = @magic_comments.fetch(name)
      end

      if valid_values && !valid_values.include?(value)
        raise(
          ArgumentError,
          "invalid value #{value.inspect} for option #{name.inspect} " \
          "(valid values: #{valid_values.inspect})"
        )
      end

      @option_values[name] = value
    end

    # @!method file
    #
    # The filename to use for compiling this code. Used for __FILE__ directives
    # as well as finding relative require()
    #
    # @return [String]
    compiler_option :file, default: '(file)'

    # @!method method_missing?
    #
    # adds method stubs for all used methods in file
    #
    # @return [Boolean]
    compiler_option :method_missing, default: true, as: :method_missing?

    # @!method arity_check?
    #
    # adds an arity check to every method definition
    #
    # @return [Boolean]
    compiler_option :arity_check, default: false, as: :arity_check?

    # @deprecated
    # @!method freezing?
    #
    # stubs out #freeze and #frozen?
    #
    # @return [Boolean]
    compiler_option :freezing, default: true, as: :freezing?

    # @!method irb?
    #
    # compile top level local vars with support for irb style vars
    compiler_option :irb, default: false, as: :irb?

    # @!method dynamic_require_severity
    #
    # how to handle dynamic requires (:error, :warning, :ignore)
    compiler_option :dynamic_require_severity, default: :ignore, valid_values: %i[error warning ignore]

    # @!method requirable?
    #
    # Prepare the code for future requires
    compiler_option :requirable, default: false, as: :requirable?

    # @!method load?
    #
    # Instantly load a requirable module
    compiler_option :load, default: false, as: :load?

    # @!method esm?
    #
    # Encourage ESM semantics, eg. exporting run result
    compiler_option :esm, default: false, as: :esm?

    # @!method no_export?
    #
    # Don't export this compile, even if ESM mode is enabled. We use
    # this internally in CLI, so that even if ESM output is desired,
    # we would only have one default export.
    compiler_option :no_export, default: false, as: :no_export?

    # @!method inline_operators?
    #
    # are operators compiled inline
    compiler_option :inline_operators, default: true, as: :inline_operators?

    compiler_option :eval, default: false, as: :eval?

    # @!method enable_source_location?
    #
    # Adds source_location for every method definition
    compiler_option :enable_source_location, default: false, as: :enable_source_location?

    # @!method enable_file_source_embed?
    #
    # Embeds source code along compiled files
    compiler_option :enable_file_source_embed, default: false, as: :enable_file_source_embed?

    # @!method use_strict?
    #
    # Enables JavaScript's strict mode (i.e., adds 'use strict'; statement)
    compiler_option :use_strict, default: false, as: :use_strict?, magic_comment: true

    # @!method directory?
    #
    # Builds a JavaScript file that is aimed to reside as part of a directory
    # for an import map build or something similar.
    compiler_option :directory, default: false, as: :directory?

    # @!method parse_comments?
    #
    # Adds comments for every method definition
    compiler_option :parse_comments, default: false, as: :parse_comments?

    # @!method backtick_javascript?
    #
    # Allows use of a backtick operator (and `%x{}`) to embed verbatim JavaScript.
    # If false, backtick operator will
    compiler_option :backtick_javascript, default: nil, as: :backtick_javascript?, magic_comment: true

    # @!method runtime_mode?
    #
    # Generates code for runtime use, only suitable for early runtime functions.
    compiler_option :opal_runtime_mode, default: false, as: :runtime_mode?, magic_comment: true

    # Warn about impending compatibility break
    def backtick_javascript_or_warn?
      case backtick_javascript?
      when true
        true
      when nil
        @backtick_javascript_warned ||= begin
          warning 'Backtick operator usage interpreted as intent to embed JavaScript; this code will ' \
                  'break in Opal 2.0; add a magic comment: `# backtick_javascript: true`'
          true
        end

        true
      when false
        false
      end
    end

    compiler_option :scope_variables, default: []

    # @!method async_await
    #
    # Enable async/await support and optionally enable auto-await.
    #
    # Use either true, false, an Array of Symbols, a String containing names
    # to auto-await separated by a comma or a Regexp.
    #
    # Auto-await awaits provided methods by default as if .__await__ was added to
    # them automatically.
    #
    # By default, the support is disabled (set to false).
    #
    # If the config value is not set to false, any calls to #__await__ will be
    # translated to ES8 await keyword which makes the scope return a Promise
    # and a containing scope will be async (instead of a value, it will return
    # a Promise).
    #
    # If the config value is an array, or a String separated by a comma,
    # auto-await is also enabled.
    #
    # A member of this collection can contain a wildcard character * in which
    # case all methods containing a given substring will be awaited.
    #
    # It can be used as a magic comment, examples:
    # ```
    # # await: true
    # # await: *await*
    # # await: *await*, sleep, gets
    compiler_option :await, default: false, as: :async_await, magic_comment: true

    # @return [String] The compiled ruby code
    attr_reader :result

    # @return [Array] all [Opal::Fragment] used to produce result
    attr_reader :fragments

    # Current scope
    attr_accessor :scope

    # Top scope
    attr_accessor :top_scope

    # Current case_stmt
    attr_reader :case_stmt

    # Any content in __END__ special construct
    attr_reader :eof_content

    # Comments from the source code
    attr_reader :comments

    # Method calls made in this file
    attr_reader :method_calls

    # Magic comment flags extracted from the leading comments
    attr_reader :magic_comments

    # Access the source code currently processed
    attr_reader :source

    # Set if some rewritter caused a dynamic cache result, meaning it's not
    # fit to be cached
    attr_accessor :dynamic_cache_result

    def initialize(source, options = {})
      @source = source
      @indent = ''
      @unique = 0
      @options = options
      @comments = Hash.new([])
      @case_stmt = nil
      @method_calls = Set.new
      @option_values = {}
      @magic_comments = {}
      @dynamic_cache_result = false
    end

    # Compile some ruby code to a string.
    #
    # @return [String] javascript code
    def compile
      parse

      @fragments = re_raise_with_location { process(@sexp).flatten }
      @fragments << fragment("\n", nil, s(:newline)) unless @fragments.last.code.end_with?("\n")

      @result = @fragments.map(&:code).join('')
    end

    def parse
      @buffer = ::Opal::Parser::SourceBuffer.new(file, 1)
      @buffer.source = @source

      @parser = Opal::Parser.default_parser

      sexp, comments, tokens = re_raise_with_location { @parser.tokenize(@buffer) }

      kind = case
             when requirable?
               :require
             when eval?
               :eval
             else
               :main
             end

      @sexp = sexp.tap { |i| i.meta[:kind] = kind }

      first_node = sexp.children.first if sexp.children.first.location

      @comments = ::Parser::Source::Comment.associate_locations(first_node, comments)
      @magic_comments = MagicComments.parse(first_node, comments)
      @eof_content = EofContent.new(tokens, @source).eof
    end

    # Returns a source map that can be used in the browser to map back to
    # original ruby code.
    #
    # @param source_file [String] optional source_file to reference ruby source
    # @return [Opal::SourceMap]
    def source_map
      # We only use @source_map if compiler is cached.
      @source_map || ::Opal::SourceMap::File.new(@fragments, file, @source, @result)
    end

    # Any helpers required by this file. Used by {Opal::Nodes::Top} to reference
    # runtime helpers that are needed. These are used to minify resulting
    # javascript by keeping a reference to helpers used.
    #
    # @return [Set<Symbol>]
    def helpers
      @helpers ||= Set.new(
        magic_comments[:helpers].to_s.split(',').map { |h| h.strip.to_sym }
      )
    end

    def record_method_call(mid)
      @method_calls << mid
    end

    alias async_await_before_typecasting async_await
    def async_await
      if defined? @async_await
        @async_await
      else
        original = async_await_before_typecasting
        @async_await = case original
                       when String
                         async_await_set_to_regexp(original.split(',').map { |h| h.strip.to_sym })
                       when Array, Set
                         async_await_set_to_regexp(original.to_a.map(&:to_sym))
                       when Regexp, true, false
                         original
                       else
                         raise 'A value of await compiler option can be either ' \
                               'a Set, an Array, a String or a Boolean.'
                       end
      end
    end

    def async_await_set_to_regexp(set)
      set = set.map { |name| Regexp.escape(name.to_s).gsub('\*', '.*?') }
      set = set.join('|')
      /^(#{set})$/
    end

    # This is called when a parsing/processing error occurs. This
    # method simply appends the filename and curent line number onto
    # the message and raises it.
    def error(msg, line = nil)
      error = ::Opal::SyntaxError.new(msg)
      error.location = Opal::OpalBacktraceLocation.new(file, line)
      raise error
    end

    def re_raise_with_location
      yield
    rescue StandardError, ::Opal::SyntaxError => error
      opal_location = ::Opal.opal_location_from_error(error)
      opal_location.path = file
      opal_location.label ||= @source.lines[opal_location.line.to_i - 1].strip
      new_error = ::Opal::SyntaxError.new(error.message)
      new_error.set_backtrace error.backtrace
      ::Opal.add_opal_location_to_error(opal_location, new_error)
      raise new_error
    end

    # This is called when a parsing/processing warning occurs. This
    # method simply appends the filename and curent line number onto
    # the message and issues a warning.
    def warning(msg, line = nil)
      warn "warning: #{msg} -- #{file}:#{line}"
    end

    # Instances of `Scope` can use this to determine the current
    # scope indent. The indent is used to keep generated code easily
    # readable.
    def parser_indent
      @indent
    end

    # Create a new sexp using the given parts.
    def s(type, *children)
      ::Opal::AST::Node.new(type, children)
    end

    def fragment(str, scope, sexp = nil)
      Fragment.new(str, scope, sexp)
    end

    # Used to generate a unique id name per file. These are used
    # mainly to name method bodies for methods that use blocks.
    def unique_temp(name)
      name = name.to_s
      if name && !name.empty?
        name = name
               .to_s
               .gsub('<=>', '$lt_eq_gt')
               .gsub('===', '$eq_eq_eq')
               .gsub('==', '$eq_eq')
               .gsub('=~', '$eq_tilde')
               .gsub('!~', '$excl_tilde')
               .gsub('!=', '$not_eq')
               .gsub('<=', '$lt_eq')
               .gsub('>=', '$gt_eq')
               .gsub('=', '$eq')
               .gsub('?', '$ques')
               .gsub('!', '$excl')
               .gsub('/', '$slash')
               .gsub('%', '$percent')
               .gsub('+', '$plus')
               .gsub('-', '$minus')
               .gsub('<', '$lt')
               .gsub('>', '$gt')
               .gsub(/[^\w\$]/, '$')
      end
      unique = (@unique += 1)
      "#{'$' unless name.start_with?('$')}#{name}$#{unique}"
    end

    # Use the given helper
    def helper(name)
      helpers << name
    end

    # To keep code blocks nicely indented, this will yield a block after
    # adding an extra layer of indent, and then returning the resulting
    # code after reverting the indent.
    def indent
      indent = @indent
      @indent += INDENT
      @space = "\n#{@indent}"
      res = yield
      @indent = indent
      @space = "\n#{@indent}"
      res
    end

    # Temporary varibales will be needed from time to time in the
    # generated code, and this method will assign (or reuse) on
    # while the block is yielding, and queue it back up once it is
    # finished. Variables are queued once finished with to save the
    # numbers of variables needed at runtime.
    def with_temp
      tmp = @scope.new_temp
      res = yield tmp
      @scope.queue_temp tmp
      res
    end

    # Used when we enter a while statement. This pushes onto the current
    # scope's while stack so we know how to handle break, next etc.
    def in_while
      return unless block_given?
      @while_loop = @scope.push_while
      result = yield
      @scope.pop_while
      result
    end

    def in_case
      return unless block_given?
      old = @case_stmt
      @case_stmt = {}
      yield
      @case_stmt = old
    end

    # Returns true if the parser is curently handling a while sexp,
    # false otherwise.
    def in_while?
      @scope.in_while?
    end

    # Process the given sexp by creating a node instance, based on its type,
    # and compiling it to fragments.
    def process(sexp, level = :expr)
      return fragment('', scope) if sexp.nil?

      if handler = handlers[sexp.type]
        return handler.new(sexp, level, self).compile_to_fragments
      else
        error "Unsupported sexp: #{sexp.type}"
      end
    end

    def handlers
      @handlers ||= Opal::Nodes::Base.handlers
    end

    # An array of requires used in this file
    def requires
      @requires ||= []
    end

    # An array of trees required in this file
    # (typically by calling #require_tree)
    def required_trees
      @required_trees ||= []
    end

    # An array of things (requires, trees) which don't need to success in
    # loading compile-time.
    def autoloads
      @autoloads ||= []
    end

    # The last sexps in method bodies, for example, need to be returned
    # in the compiled javascript. Due to syntax differences between
    # javascript any ruby, some sexps need to be handled specially. For
    # example, `if` statemented cannot be returned in javascript, so
    # instead the "truthy" and "falsy" parts of the if statement both
    # need to be returned instead.
    #
    # Sexps that need to be returned are passed to this method, and the
    # alterned/new sexps are returned and should be used instead. Most
    # sexps can just be added into a `s(:return) sexp`, so that is the
    # default action if no special case is required.
    def returns(sexp)
      return returns s(:nil) unless sexp

      case sexp.type
      when :undef
        # undef :method_name always returns nil
        returns sexp.updated(:begin, [sexp, s(:nil)])
      when :break, :next, :redo, :retry
        sexp
      when :yield
        sexp.updated(:returnable_yield, nil)
      when :when
        *when_sexp, then_sexp = *sexp
        sexp.updated(nil, [*when_sexp, returns(then_sexp)])
      when :rescue
        body_sexp, *resbodies, else_sexp = *sexp

        resbodies = resbodies.map do |resbody|
          returns(resbody)
        end

        if else_sexp
          else_sexp = returns(else_sexp)
        end

        sexp.updated(
          nil, [
            returns(body_sexp),
            *resbodies,
            else_sexp
          ]
        )
      when :resbody
        klass, lvar, body = *sexp
        sexp.updated(nil, [klass, lvar, returns(body)])
      when :ensure
        rescue_sexp, ensure_body = *sexp
        sexp = sexp.updated(nil, [returns(rescue_sexp), ensure_body])
        sexp.updated(:js_return, [sexp])
      when :begin, :kwbegin
        # Wrapping last expression with s(:js_return, ...)
        *rest, last = *sexp
        sexp.updated(nil, [*rest, returns(last)])
      when :while, :until, :while_post, :until_post
        sexp
      when :return, :js_return, :returnable_yield
        sexp
      when :xstr
        if backtick_javascript_or_warn?
          sexp.updated(nil, [s(:js_return, *sexp.children)])
        else
          sexp
        end
      when :if
        cond, true_body, false_body = *sexp
        sexp.updated(
          nil, [
            cond,
            returns(true_body),
            returns(false_body)
          ]
        ).tap { |s| s.meta[:returning] = true }
      else
        if sexp.type == :send && sexp.children[1] == :debugger
          # debugger is a statement, so it doesn't return a value
          # and returning it is invalid. Therefore we update it
          # to do `debugger; return nil`.
          sexp.updated(:begin, [sexp, s(:js_return, s(:nil))])
        else
          sexp.updated(:js_return, [sexp])
        end
      end
    end

    def handle_block_given_call(sexp)
      @scope.uses_block!
      if @scope.block_name
        fragment("(#{@scope.block_name} !== nil)", scope, sexp)
      elsif (scope = @scope.find_parent_def) && scope.block_name
        fragment("(#{scope.block_name} !== nil)", scope, sexp)
      else
        fragment('false', scope, sexp)
      end
    end

    # Track a module as required, so that builder will know to process it
    def track_require(mod)
      requires << mod
    end

    # Marshalling for cache shortpath
    def marshal_dump
      [@options, @option_values, @source_map ||= source_map.cache,
       @magic_comments, @result,
       @required_trees, @requires, @autoloads]
    end

    def marshal_load(src)
      @options, @option_values, @source_map,
      @magic_comments, @result,
      @required_trees, @requires, @autoloads = src
    end
  end
end
