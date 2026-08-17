# frozen_string_literal: true

RSpec.describe "Operation DSL" do
  describe Trane::OperationBuilder do
    it "builds a minimal operation" do
      builder = described_class.new(:get_user)
      builder.summary "Get a user"
      op = builder.build

      expect(op.name).to eq(:get_user)
      expect(op.summary).to eq("Get a user")
      expect(op.request).to be_nil
      expect(op.responses).to eq({})
      expect(op.error_keys).to eq([])
    end

    it "builds an operation with request path params" do
      builder = described_class.new(:get_user)
      builder.instance_eval do
        request do
          path :id, type: :integer
        end
      end
      op = builder.build

      expect(op.request).to be_a(Trane::RequestDefinition)
      expect(op.request.params.length).to eq(1)

      param = op.request.params.first
      expect(param.name).to eq(:id)
      expect(param.type).to eq(:integer)
      expect(param.required).to be true
      expect(param.location).to eq(:path)
    end

    it "builds an operation with request query params" do
      builder = described_class.new(:list_users)
      builder.instance_eval do
        request do
          query :status, type: :string, required: false
        end
      end
      op = builder.build

      param = op.request.params.first
      expect(param.location).to eq(:query)
      expect(param.required).to be false
    end

    it "builds an operation with request body" do
      builder = described_class.new(:create_user)
      builder.instance_eval do
        request do
          body do
            field :user do
              field :name, type: :string
              field :email, type: :string
            end
          end
        end
      end
      op = builder.build

      expect(op.request.body_fields.length).to eq(1)
      user_field = op.request.body_fields.first
      expect(user_field.name).to eq(:user)
      expect(user_field.children.length).to eq(2)
    end

    describe "body field required:" do
      it "defaults to required: false for body fields" do
        builder = described_class.new(:op)
        builder.instance_eval { request { body { field :name, type: :string } } }
        node = builder.build.request.body_fields.first
        expect(node.required).to be false
      end

      it "accepts required: true on a body field" do
        builder = described_class.new(:op)
        builder.instance_eval { request { body { field :name, type: :string, required: true } } }
        node = builder.build.request.body_fields.first
        expect(node.required).to be true
      end

      it "propagates required: to nested children via BodyBuilder" do
        builder = described_class.new(:op)
        builder.instance_eval do
          request do
            body do
              field :user, required: true do
                field :name, type: :string, required: true
              end
            end
          end
        end
        op = builder.build
        user_field = op.request.body_fields.first
        expect(user_field.required).to be true
        expect(user_field.children.first.required).to be true
      end

      it "allows outer required: false with inner required: true" do
        builder = described_class.new(:op)
        builder.instance_eval do
          request do
            body do
              field :user do
                field :name, type: :string, required: true
              end
            end
          end
        end
        op = builder.build
        user_field = op.request.body_fields.first
        expect(user_field.required).to be false
        expect(user_field.children.first.required).to be true
      end
    end

    it "builds an operation with response" do
      builder = described_class.new(:get_user)
      builder.instance_eval do
        response 200 do
          field :user, type: :user
        end
      end
      op = builder.build

      expect(op.responses.keys).to eq([ 200 ])
      resp = op.responses[200]
      expect(resp.status).to eq(200)
      expect(resp.fields.length).to eq(1)
      expect(resp.fields.first.name).to eq(:user)
      expect(resp.fields.first.type).to eq(:user)
    end

    it "builds an operation with multiple responses" do
      builder = described_class.new(:create_user)
      builder.instance_eval do
        response 200 do
          field :user, type: :user
        end
        response 201 do
          field :user, type: :user
        end
      end
      op = builder.build

      expect(op.responses.keys).to contain_exactly(200, 201)
    end

    it "builds an operation with error keys" do
      builder = described_class.new(:get_user)
      builder.instance_eval do
        errors do
          key :UserNotFound
          key :UserInvalid
        end
      end
      op = builder.build

      expect(op.error_keys).to eq([ :UserNotFound, :UserInvalid ])
    end

    it "builds a full operation with all components" do
      builder = described_class.new(:update_user)
      builder.instance_eval do
        summary "Update a user"

        request do
          path :id, type: :integer
          body do
            field :user do
              field :name, type: :string
              field :email, type: :string
            end
          end
        end

        response 200 do
          field :user, type: :user
        end

        errors do
          key :UserNotFound
          key :UserInvalid
        end
      end
      op = builder.build

      expect(op.name).to eq(:update_user)
      expect(op.summary).to eq("Update a user")
      expect(op.request.params.length).to eq(1)
      expect(op.request.body_fields.length).to eq(1)
      expect(op.responses.keys).to eq([ 200 ])
      expect(op.error_keys).to eq([ :UserNotFound, :UserInvalid ])
    end

    describe "path validation" do
      it "raises ArgumentError when type: keyword is missing" do
        builder = described_class.new(:get_user)
        expect {
          builder.instance_eval { request { path :id } }
        }.to raise_error(ArgumentError)
      end

      it "raises ArgumentError when type: nil is given" do
        builder = described_class.new(:get_user)
        expect {
          builder.instance_eval { request { path :id, type: nil } }
        }.to raise_error(ArgumentError, /type: cannot be nil/)
      end

      it "raises ArgumentError for the old positional form" do
        builder = described_class.new(:get_user)
        expect {
          builder.instance_eval { request { path :id, :integer } }
        }.to raise_error(ArgumentError)
      end

      context "when path is called with required:" do
        it "raises ArgumentError if required: true is passed" do
          expect {
            Trane.operation :bad_op do
              request do
                path :id, type: :integer, required: true
              end
            end
          }.to raise_error(ArgumentError, /unknown keyword: :?required/)
        end

        it "raises ArgumentError if required: false is passed" do
          expect {
            Trane.operation :bad_op do
              request do
                path :id, type: :integer, required: false
              end
            end
          }.to raise_error(ArgumentError, /unknown keyword: :?required/)
        end
      end
    end

    it "sets required to true internally for path params" do
      Trane.operation :test_op_internal_required do
        request do
          path :id, type: :integer
        end
      end
      op = Trane::Registry.operations[:test_op_internal_required]
      param = op.request.params.first
      expect(param.required).to be(true)
    end

    describe "query validation" do
      it "raises ArgumentError when type: keyword is missing" do
        builder = described_class.new(:list_users)
        expect {
          builder.instance_eval { request { query :page } }
        }.to raise_error(ArgumentError)
      end
    end

    describe "query enum:" do
      it "creates a ParamDefinition with enum when provided" do
        builder = described_class.new(:list_items)
        builder.instance_eval do
          request do
            query :sort, type: :string, enum: [ "asc", "desc" ]
          end
        end
        param = builder.build.request.params.first
        expect(param.enum).to eq([ "asc", "desc" ])
      end

      it "raises ArgumentError when enum values mismatch type" do
        builder = described_class.new(:list_items)
        expect {
          builder.instance_eval do
            request do
              query :count, type: :integer, enum: [ 1.0 ]
            end
          end
        }.to raise_error(ArgumentError, /not coherent with type :integer/)
      end
    end

    describe "path enum:" do
      it "raises ArgumentError when enum: is passed to path" do
        expect {
          Trane.operation :bad_path_enum_op do
            request do
              path :id, type: :integer, enum: [ 1, 2, 3 ]
            end
          end
        }.to raise_error(ArgumentError, /unknown keyword: :?enum/)
      end
    end

    describe "body field enum:" do
      it "creates a FieldNode with enum via BodyBuilder" do
        builder = described_class.new(:create_item)
        builder.instance_eval do
          request do
            body do
              field :status, type: :string, enum: [ "draft", "published" ]
            end
          end
        end
        field = builder.build.request.body_fields.first
        expect(field.enum).to eq([ "draft", "published" ])
      end
    end
  end

  describe "ResponseDefinition status validation" do
    it "raises ArgumentError for status below 100" do
      expect { Trane::ResponseDefinition.new(status: 99) }
        .to raise_error(ArgumentError, /not a valid HTTP status code/)
    end

    it "raises ArgumentError for status above 599" do
      expect { Trane::ResponseDefinition.new(status: 600) }
        .to raise_error(ArgumentError, /not a valid HTTP status code/)
    end

    it "accepts valid HTTP statuses" do
      expect { Trane::ResponseDefinition.new(status: 200) }.not_to raise_error
      expect { Trane::ResponseDefinition.new(status: 201) }.not_to raise_error
      expect { Trane::ResponseDefinition.new(status: 422) }.not_to raise_error
    end
  end

  describe "OperationDefinition name validation" do
    it "raises ArgumentError for nil name" do
      expect { Trane::OperationDefinition.new(name: nil) }
        .to raise_error(ArgumentError, /name cannot be nil or empty/)
    end

    it "raises ArgumentError for empty string name" do
      expect { Trane::OperationDefinition.new(name: "") }
        .to raise_error(ArgumentError, /name cannot be nil or empty/)
    end
  end

  describe "Trane.operation" do
    it "registers an operation in the registry" do
      Trane.operation :get_user do
        summary "Get a user"

        request do
          path :id, type: :integer
        end

        response 200 do
          field :user, type: :user
        end

        errors do
          key :UserNotFound
        end
      end

      op = Trane::Registry.operations[:get_user]
      expect(op).to be_a(Trane::OperationDefinition)
      expect(op.name).to eq(:get_user)
      expect(op.summary).to eq("Get a user")
    end
  end
end
