# helpers: coerce_to, prop, freeze, annotate_regexp, escape_metacharacters
# backtick_javascript: true
# use_strict: true

class ::RegexpError < ::StandardError; end

class ::Regexp < `RegExp`
  self::IGNORECASE = 1
  self::EXTENDED = 2
  self::MULTILINE = 4
  # Not supported:
  self::FIXEDENCODING = 16
  self::NOENCODING = 32

  `Opal.prop(self.$$prototype, '$$is_regexp', true)`
  `Opal.prop(self.$$prototype, '$$source', null)`
  `Opal.prop(self.$$prototype, '$$options', null)`
  `Opal.prop(self.$$prototype, '$$g', null)`

  class << self
    def allocate
      allocated = super
      `#{allocated}.uninitialized = true`
      allocated
    end

    def escape(string)
      %x{
        string = $coerce_to(string, #{::String}, 'to_str');
        return Opal.escape_regexp(string);
      }
    end

    def last_match(n = nil)
      if n.nil?
        $~
      elsif $~
        $~[n]
      end
    end

    def union(*parts)
      %x{
        function exclude_compatible(flags) {
          return (flags || 0) & ~#{MULTILINE} & ~#{EXTENDED};
        }
        function compatible_flags(first, second) {
          return exclude_compatible(first) == exclude_compatible(second)
        }

        var is_first_part_array, quoted_validated, part, options, each_part_options;
        if (parts.length == 0) {
          return /(?!)/;
        }
        // return fast if there's only one element
        if (parts.length == 1 && parts[0].$$is_regexp) {
          return parts[0];
        }
        // cover the 2 arrays passed as arguments case
        is_first_part_array = parts[0].$$is_array;
        if (parts.length > 1 && is_first_part_array) {
          #{::Kernel.raise ::TypeError, 'no implicit conversion of Array into String'}
        }
        // deal with splat issues (related to https://github.com/opal/opal/issues/858)
        if (is_first_part_array) {
          parts = parts[0];
        }
        options = undefined;
        quoted_validated = [];
        for (var i=0; i < parts.length; i++) {
          part = parts[i];
          if (part.$$is_string) {
            quoted_validated.push(#{escape(`part`)});
          }
          else if (part.$$is_regexp) {
            each_part_options = #{`part`.options};
            if (options != undefined && !compatible_flags(options, each_part_options)) {
              #{::Kernel.raise ::TypeError, 'All expressions must use the same options'}
            }
            options = each_part_options;
            quoted_validated.push('(?:'+#{`part`.source}+')');
          }
          else {
            quoted_validated.push(#{escape(`part`.to_str)});
          }
        }
      }
      # Take advantage of logic that can parse options from JS Regex
      new(`quoted_validated`.join('|'), `options`)
    end

    def new(regexp, options = undefined)
      %x{
        if (regexp.$$is_regexp) {
          return $annotate_regexp(new RegExp(regexp), regexp.$$source, regexp.$$options);
        }

        regexp = #{::Opal.coerce_to!(regexp, ::String, :to_str)};

        if (regexp.charAt(regexp.length - 1) === '\\' && regexp.charAt(regexp.length - 2) !== '\\') {
          #{::Kernel.raise ::RegexpError, "too short escape sequence: /#{regexp}/"}
        }

        if (options === undefined || #{!options}) {
          options = 'u';
        }
        else if (options.$$is_number) {
          var temp = 'u';
          if (#{IGNORECASE} & options) { temp += 'i'; }
          if (#{MULTILINE}  & options) { temp += 'm'; }
          options = temp;
        }
        else if (!options.$$is_string) {
          options = 'iu';
        }

        var result = Opal.transform_regexp(regexp, options);
        return Opal.annotate_regexp(new RegExp(result[0], result[1]), $escape_metacharacters(regexp), options);
      }
    end

    alias compile new
    alias quote escape
  end

  def ==(other)
    `other instanceof RegExp && self.$options() == other.$options() && self.$source() == other.$source()`
  end

  def ===(string)
    `#{match(::Opal.coerce_to?(string, ::String, :to_str))} !== nil`
  end

  def =~(string)
    match(string) && $~.begin(0)
  end

  def freeze
    # Specialized version of freeze, because the $$gm and $$g properties need to be set
    # especially for RegExp.

    return self if frozen?

    %x{
      if (!self.hasOwnProperty('$$g')) { $prop(self, '$$g', null); }

      return $freeze(self);
    }
  end

  def inspect
    # Use a regexp to extract the regular expression and the optional mode modifiers from the string.
    # In the regular expression, escape any front slash (not already escaped) with a backslash.
    %x{
      var regexp_pattern = self.$source();
      var regexp_flags = self.$$options != null ? self.$$options : self.flags;
      regexp_flags = regexp_flags.replace('u', '');
      var chars = regexp_pattern.split('');
      var chars_length = chars.length;
      var char_escaped = false;
      var regexp_pattern_escaped = '';
      for (var i = 0; i < chars_length; i++) {
        var current_char = chars[i];
        if (!char_escaped && current_char == '/') {
          regexp_pattern_escaped += '\\';
        }
        regexp_pattern_escaped += current_char;
        if (current_char == '\\') {
          // does not over escape
          char_escaped = !char_escaped;
        } else {
          char_escaped = false;
        }
      }
      return '/' + regexp_pattern_escaped + '/' + regexp_flags;
    }
  end

  def match(string, pos = undefined, &block)
    %x{
      if (self.uninitialized) {
        #{::Kernel.raise ::TypeError, 'uninitialized Regexp'}
      }

      if (pos === undefined) {
        if (string === nil) return #{$~ = nil};
        var m = self.exec($coerce_to(string, #{::String}, 'to_str'));
        if (m) {
          #{$~ = ::MatchData.new(`self`, `m`)};
          return block === nil ? #{$~} : #{yield $~};
        } else {
          return #{$~ = nil};
        }
      }

      pos = $coerce_to(pos, #{::Integer}, 'to_int');

      if (string === nil) {
        return #{$~ = nil};
      }

      string = $coerce_to(string, #{::String}, 'to_str');

      if (pos < 0) {
        pos += string.length;
        if (pos < 0) {
          return #{$~ = nil};
        }
      }

      // global RegExp maintains state, so not using self/this
      var md, re = Opal.global_regexp(self);

      while (true) {
        md = re.exec(string);
        if (md === null) {
          return #{$~ = nil};
        }
        if (md.index >= pos) {
          #{$~ = ::MatchData.new(`re`, `md`)};
          return block === nil ? #{$~} : #{yield $~};
        }
        re.lastIndex = md.index + 1;
      }
    }
  end

  def match?(string, pos = undefined)
    %x{
      if (self.uninitialized) {
        #{::Kernel.raise ::TypeError, 'uninitialized Regexp'}
      }

      if (pos === undefined) {
        return string === nil ? false : self.test($coerce_to(string, #{::String}, 'to_str'));
      }

      pos = $coerce_to(pos, #{::Integer}, 'to_int');

      if (string === nil) {
        return false;
      }

      string = $coerce_to(string, #{::String}, 'to_str');

      if (pos < 0) {
        pos += string.length;
        if (pos < 0) {
          return false;
        }
      }

      // global RegExp maintains state, so not using self/this
      var md, re = Opal.global_regexp(self);

      md = re.exec(string);
      if (md === null || md.index < pos) {
        return false;
      } else {
        return true;
      }
    }
  end

  def names
    source.scan(/\(?<(\w+)>/, no_matchdata: true).map(&:first).uniq
  end

  def named_captures
    source.scan(/\(?<(\w+)>/, no_matchdata: true) # Scan for capture groups
          .map(&:first)                           # Get the first regexp match (\w+)
          .each_with_index                        # Add index to an iterator
          .group_by(&:first)                      # Group by the capture group names
          .transform_values do |i|                # Convert hash values
            i.map { |j| j.last + 1 }              # Drop the capture group names; increase indexes by 1
          end
  end

  def ~
    self =~ $_
  end

  def source
    `self.$$source != null ? self.$$source : self.source`
  end

  def options
    # Flags would be nice to use with this, but still experimental - https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/RegExp/flags
    %x{
      if (self.uninitialized) {
        #{::Kernel.raise ::TypeError, 'uninitialized Regexp'}
      }
      var result = 0;
      // should be supported in IE6 according to https://msdn.microsoft.com/en-us/library/7f5z26w4(v=vs.94).aspx
      if (self.$$options != null ? self.$$options.includes('m') : self.multiline) {
        result |= #{MULTILINE};
      }
      if (self.$$options != null ? self.$$options.includes('i') : self.ignoreCase) {
        result |= #{IGNORECASE};
      }
      if (self.$$options != null ? self.$$options.includes('x') : false) {
        result |= #{EXTENDED};
      }
      return result;
    }
  end

  def casefold?
    `self.ignoreCase`
  end

  alias eql? ==
  alias to_s source
end

class MatchData
  attr_reader :post_match, :pre_match, :regexp, :string

  def initialize(regexp, match_groups, no_matchdata: false)
    $~          = self unless no_matchdata
    @regexp     = regexp
    @begin      = `match_groups.index`
    @string     = `match_groups.input`
    @pre_match  = `match_groups.input.slice(0, match_groups.index)`
    @post_match = `match_groups.input.slice(match_groups.index + match_groups[0].length)`
    @matches    = []

    %x{
      for (var i = 0, length = match_groups.length; i < length; i++) {
        var group = match_groups[i];

        if (group == null) {
          #{@matches}.push(nil);
        }
        else {
          #{@matches}.push(group);
        }
      }
    }
  end

  def match(idx)
    if (match = self[idx])
      match
    elsif idx.is_a?(Integer) && idx >= length
      ::Kernel.raise ::IndexError, "index #{idx} out of matches"
    end
  end

  def match_length(idx)
    match(idx)&.length
  end

  def [](*args)
    %x{
      if (args[0].$$is_string) {
        if (#{!regexp.names.include?(args[0])}) {
          #{::Kernel.raise ::IndexError, "undefined group name reference: #{args[0]}"}
        }
        return #{named_captures[args[0]]}
      }
      else {
        return #{@matches[*args]}
      }
    }
  end

  def offset(n)
    %x{
      if (n !== 0) {
        #{::Kernel.raise ::ArgumentError, 'MatchData#offset only supports 0th element'}
      }
      return [self.begin, self.begin + self.matches[n].length];
    }
  end

  def ==(other)
    return false unless ::MatchData === other

    `self.string == other.string` &&
      `self.regexp.toString() == other.regexp.toString()` &&
      `self.pre_match == other.pre_match` &&
      `self.post_match == other.post_match` &&
      `self.begin == other.begin`
  end

  def begin(n)
    %x{
      if (n !== 0) {
        #{::Kernel.raise ::ArgumentError, 'MatchData#begin only supports 0th element'}
      }
      return self.begin;
    }
  end

  def end(n)
    %x{
      if (n !== 0) {
        #{::Kernel.raise ::ArgumentError, 'MatchData#end only supports 0th element'}
      }
      return self.begin + self.matches[n].length;
    }
  end

  def captures
    `#{@matches}.slice(1)`
  end

  def named_captures
    matches = captures
    regexp.named_captures.transform_values do |i|
      matches[i.last - 1]
    end
  end

  def names
    regexp.names
  end

  def inspect
    %x{
      var str = "#<MatchData " + #{`#{@matches}[0]`.inspect};

      if (#{regexp.names.empty?}) {
        for (var i = 1, length = #{@matches}.length; i < length; i++) {
          str += " " + i + ":" + #{`#{@matches}[i]`.inspect};
        }
      }
      else {
        #{ named_captures.each do |k, v|
             %x{
               str += " " + #{k} + ":" + #{v.inspect}
             }
           end }
      }

      return str + ">";
    }
  end

  def length
    `#{@matches}.length`
  end

  def to_a
    @matches
  end

  def to_s
    `#{@matches}[0]`
  end

  def values_at(*args)
    %x{
      var i, a, index, values = [];

      for (i = 0; i < args.length; i++) {

        if (args[i].$$is_range) {
          a = #{`args[i]`.to_a};
          a.unshift(i, 1);
          Array.prototype.splice.apply(args, a);
        }

        index = #{::Opal.coerce_to!(`args[i]`, ::Integer, :to_int)};

        if (index < 0) {
          index += #{@matches}.length;
          if (index < 0) {
            values.push(nil);
            continue;
          }
        }

        values.push(#{@matches}[index]);
      }

      return values;
    }
  end

  alias eql? ==
  alias size length
end
