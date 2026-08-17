# frozen_string_literal: true

module Trane
  RequestDefinition = Data.define(:params, :body_fields) do
    def initialize(params: [], body_fields: [])
      super(params: params.freeze, body_fields: body_fields.freeze)
    end
  end

  ResponseDefinition = Data.define(:status, :fields) do
    def initialize(status:, fields: [])
      status_int = status.to_i
      unless Trane::Types::HTTP_STATUS_RANGE.cover?(status_int)
        raise ArgumentError,
              "ResponseDefinition status #{status.inspect} is not a valid HTTP status code " \
              "(must be in #{Trane::Types::HTTP_STATUS_RANGE})"
      end
      super(status: status_int, fields: fields.freeze)
    end
  end

  OperationDefinition = Data.define(:name, :summary, :request, :responses, :error_keys) do
    def initialize(name:, summary: nil, request: nil, responses: {}, error_keys: [])
      if name.nil? || name.to_s.empty?
        raise ArgumentError, "OperationDefinition name cannot be nil or empty"
      end
      super(
        name: name.to_sym,
        summary: summary,
        request: request,
        responses: responses.freeze,
        error_keys: error_keys.freeze
      )
    end
  end

  # Builder for the `body do ... end` block inside a request.
  # Extends FieldBuilder to accept the `required:` kwarg on body fields.
  class BodyBuilder < FieldBuilder
    def field(name, type: nil, extra: false, format: nil, of: nil, required: false, enum: nil, &block)
      @fields << _build_field_node(
        name: name, type: type, extra: extra, format: format,
        of: of, enum: enum, child_builder_class: BodyBuilder,
        required: required, &block
      )
    end
  end

  # Builder for the `request do ... end` block
  class RequestBuilder
    def initialize
      @params = []
      @body_fields = []
    end

    def path(name, type:)
      raise ArgumentError, "path #{name.inspect} type: cannot be nil" if type.nil?

      @params << ParamDefinition.new(name: name, type: type, required: true, location: :path)
    end

    def query(name, type:, required: false, enum: nil)
      raise ArgumentError, "query #{name.inspect} type: cannot be nil" if type.nil?

      Trane::Types.validate_enum!(name: name, type: type, enum: enum) if enum
      @params << ParamDefinition.new(name: name, type: type, required: required, location: :query, enum: enum)
    end

    def body(&block)
      builder = BodyBuilder.new
      builder.instance_eval(&block)
      @body_fields = builder.fields
    end

    def build
      RequestDefinition.new(params: @params, body_fields: @body_fields)
    end
  end

  # Builder for the `response STATUS do ... end` block
  class ResponseBuilder < FieldBuilder
    def initialize(status)
      super()
      @status = status.to_i
    end

    def build
      ResponseDefinition.new(status: @status, fields: @fields)
    end
  end

  # Builder for the `errors do ... end` block inside an operation
  class ErrorKeysBuilder
    attr_reader :keys

    def initialize
      @keys = []
    end

    def key(error_key)
      @keys << error_key.to_sym
    end
  end

  # Builder for `Trane.operation :name do ... end`
  class OperationBuilder
    def initialize(name)
      @name = name.to_sym
      @summary = nil
      @request_builder = nil
      @responses = {}
      @error_keys = []
    end

    def summary(text)
      @summary = text
    end

    def request(&block)
      @request_builder = RequestBuilder.new
      @request_builder.instance_eval(&block)
    end

    def response(status, &block)
      builder = ResponseBuilder.new(status)
      builder.instance_eval(&block)
      @responses[status.to_i] = builder.build
    end

    def errors(&block)
      builder = ErrorKeysBuilder.new
      builder.instance_eval(&block)
      @error_keys = builder.keys
    end

    def build
      OperationDefinition.new(
        name: @name,
        summary: @summary,
        request: @request_builder&.build,
        responses: @responses,
        error_keys: @error_keys
      )
    end
  end
end
