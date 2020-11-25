module Schemacop
  class StringNode < Node
    ATTRIBUTES = %i[
      min_length
      max_length
      pattern
      format
      enum
      boolean
    ].freeze

    FORMAT_PATTERNS = {
      date:        /^([0-9]{4})-?(1[0-2]|0[1-9])-?(3[01]|0[1-9]|[12][0-9])$/,
      'date-time': /^(-?(?:[1-9][0-9]*)?[0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])T(2[0-3]|[01][0-9]):([0-5][0-9]):([0-5][0-9])(\.[0-9]+)?(Z|[+-](?:2[0-3]|[01][0-9]):[0-5][0-9])?$/,
      email:       URI::MailTo::EMAIL_REGEXP,
      boolean:     /^(true|false)$/,
      binary:      nil,
      integer:     /^-?[0-9]+$/,
      number:      /^-?[0-9]+(\.[0-9]+)?$/
    }.freeze

    def self.allowed_options
      super + ATTRIBUTES - %i[cast_str] + %i[format_options]
    end

    def allowed_types
      { String => :string }
    end

    def as_json
      process_json(ATTRIBUTES, type: :string)
    end

    def _validate(data, result:)
      data = super
      return if data.nil?

      # Validate length #
      length = data.size

      if options[:min_length] && length < options[:min_length]
        result.error "String is #{length} characters long but must be at least #{options[:min_length]}."
      end

      if options[:max_length] && length > options[:max_length]
        result.error "String is #{length} characters long but must be at most #{options[:max_length]}."
      end

      # Validate pattern #
      if options[:pattern]
        unless data.match?(Regexp.compile(options[:pattern]))
          result.error "String does not match pattern #{options[:pattern].inspect}."
        end
      end

      # Validate format #
      if options[:format] && FORMAT_PATTERNS.include?(options[:format])
        pattern = FORMAT_PATTERNS[options[:format]]
        if pattern && !data.match?(pattern)
          result.error "String does not match format #{options[:format].to_s.inspect}."
        elsif options[:format_options] && Node.resolve_class(options[:format])
          node = create(options[:format], **options[:format_options])
          node._validate(cast(data), result: result)
        end
      end
    end

    def cast(value)
      case options[:format]
      when :boolean
        return value == 'true'
      when :date
        return Date.parse(value)
      when :'date-time'
        return DateTime.parse(value)
      when :integer
        return Integer(value)
      when :number
        return Float(value)
      else
        return value || default
      end
    end

    protected

    def init
      if options.include?(:format)
        options[:format] = options[:format].to_s.dasherize.to_sym
      end
    end

    def validate_self
      if options.include?(:format)
        unless FORMAT_PATTERNS.include?(options[:format])
          fail "Format #{options[:format].inspect} is not supported."
        end
      end
    end
  end
end
