module Schemacop
  module V3
    class ArrayNode < Node
      ATTRIBUTES = %i[
        min_items
        max_items
        unique_items
      ].freeze

      supports_children

      def self.allowed_options
        super + ATTRIBUTES + %i[additional_items contains]
      end

      def self.dsl_methods
        super + NodeRegistry.dsl_methods(false) + %i[dsl_add]
      end

      attr_reader :items

      def dsl_add(type, **options, &block)
        if @options[:additional_items].is_a?(Node)
          fail Exceptions::InvalidSchemaError, 'You can only use "add" once to specify additional items.'
        end

        @options[:additional_items] = create(type, **options, &block)
      end

      def add_child(node)
        @items << node
      end

      def as_json
        json = { type: :array }

        if @items.any?
          if options[:contains]
            json[:contains] = @items.first.as_json
          else
            # If only one item given: List validation, every item needs to match the given
            # schema (e.g. be a boolean). If multiple items are given, it's a tuple validation
            # and the order of the items matters
            json[:items] = @items.count == 1 ? @items.first.as_json : @items.map(&:as_json)
          end
        end

        # Only applicable if items > 1, i.e. it's a tuple validation and not a list validation
        if options[:additional_items] == true
          json[:additionalItems] = true
        elsif options[:additional_items].is_a?(Node)
          json[:additionalItems] = options[:additional_items].as_json
        elsif @items.any? && !options[:contains]
          json[:additionalItems] = false
        end

        return process_json(ATTRIBUTES, json)
      end

      def allowed_types
        { Array => :array }
      end

      def _validate(data, result:)
        super_data = super
        return if super_data.nil?

        # Validate length #
        length = super_data.size

        if options[:min_items] && length < options[:min_items]
          result.error "Array has #{length} items but needs at least #{options[:min_items]}."
        end

        if options[:max_items] && length > options[:max_items]
          result.error "Array has #{length} items but needs at most #{options[:max_items]}."
        end

        # Validate contains #
        if options[:contains]
          fail 'Array nodes with "contains" must have exactly one item.' unless items.size == 1

          item = items.first

          unless super_data.any? { |obj| item_matches?(item, obj) }
            result.error "At least one entry must match schema #{item.as_json.inspect}."
          end
        # Validate list #
        elsif items.size == 1
          node = items.first

          super_data.each_with_index do |value, index|
            result.in_path :"[#{index}]" do
              node._validate(value, result: result)
            end
          end

        # Validate tuple #
        elsif items.size > 1
          if length == items.size || (options[:additional_items] != false && length >= items.size)
            items.each_with_index do |child_node, index|
              value = super_data[index]

              result.in_path :"[#{index}]" do
                child_node._validate(value, result: result)
              end
            end

            # Validate additional items #
            if options[:additional_items].is_a?(Node)
              (items.size..(length - 1)).each do |index|
                additional_item = super_data[index]
                result.in_path :"[#{index}]" do
                  options[:additional_items]._validate(additional_item, result: result)
                end
              end
            end
          else
            result.error "Array has #{length} items but must have exactly #{items.size}."
          end
        end

        # Validate uniqueness #
        if options[:unique_items] && super_data.size != super_data.uniq.size
          result.error 'Array has duplicate items.'
        end
      end

      def children
        (@items + [@contains]).compact
      end

      def cast(value)
        return default unless value

        result = []

        value.each_with_index do |value_item, index|
          if options[:contains]
            item = item_for_data(value_item, force: false)
            if item
              result << item.cast(value_item)
            else
              result << value_item
            end
          elsif options[:additional_items] != false && index >= items.size
            if options[:additional_items].is_a?(Node)
              result << options[:additional_items].cast(value_item)
            else
              result << value_item
            end
          else
            item = item_for_data(value_item)
            result << item.cast(value_item)
          end
        end

        return result
      end

      protected

      def item_for_data(data, force: true)
        item = children.find { |c| item_matches?(c, data) }
        return item if item
        return nil unless force

        fail "Could not find specification for item #{data.inspect}."
      end

      def init
        @items = []
        @contains = nil

        if options[:additional_items].nil?
          options[:additional_items] = false
        end
      end

      def validate_self
        unless options[:min_items].nil? || options[:min_items].is_a?(Integer)
          fail 'Option "min_items" must be an "integer"'
        end

        unless options[:max_items].nil? || options[:max_items].is_a?(Integer)
          fail 'Option "max_items" must be an "integer"'
        end

        unless options[:unique_items].nil? || options[:unique_items].is_a?(TrueClass) || options[:unique_items].is_a?(FalseClass)
          fail 'Option "unique_items" must be a "boolean".'
        end

        if options[:min_items] && options[:max_items] && options[:min_items] > options[:max_items]
          fail 'Option "min_items" can\'t be greater than "max_items".'
        end

        if options[:contains] && items.size != 1
          fail 'Array nodes with "contains" must have exactly one item.'
        end
      end
    end
  end
end
