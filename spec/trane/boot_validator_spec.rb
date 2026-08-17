# frozen_string_literal: true

RSpec.describe Trane::BootValidator do
  describe ".validate!" do
    context "when all references are valid" do
      before do
        Trane.representation :user do
          field :id, type: :integer
          field :name, type: :string
        end

        Trane.errors do
          error :UserNotFound, status_code: 404, description: "User not found"
        end

        Trane.operation :get_user do
          response 200 do
            field :user, type: :user
          end
          errors do
            key :UserNotFound
          end
        end
      end

      it "does not raise" do
        expect { described_class.validate!(Trane::Registry) }.not_to raise_error
      end
    end

    context "when a response field references a nonexistent representation" do
      before do
        Trane.operation :get_user do
          response 200 do
            field :user, type: :user
          end
        end
      end

      it "raises an error" do
        expect { described_class.validate!(Trane::Registry) }
          .to raise_error(Trane::Error, /field :user references representation :user, which does not exist/)
      end
    end

    context "when an array field references a nonexistent representation" do
      before do
        Trane.operation :list_users do
          response 200 do
            field :users, type: :array, of: :user
          end
        end
      end

      it "raises an error" do
        expect { described_class.validate!(Trane::Registry) }
          .to raise_error(Trane::Error, /field :users has array of :user, which does not exist/)
      end
    end

    context "when an operation references a nonexistent error key" do
      before do
        Trane.representation :user do
          field :id, type: :integer
        end

        Trane.operation :get_user do
          response 200 do
            field :user, type: :user
          end
          errors do
            key :UserNotFound
          end
        end
      end

      it "raises an error" do
        expect { described_class.validate!(Trane::Registry) }
          .to raise_error(Trane::Error, /references error :UserNotFound, but no such error is registered/)
      end
    end

    context "when multiple references are invalid" do
      before do
        Trane.operation :get_user do
          response 200 do
            field :user, type: :user
          end
          errors do
            key :UserNotFound
          end
        end
      end

      it "reports all errors in a single exception" do
        expect { described_class.validate!(Trane::Registry) }
          .to raise_error(Trane::Error) do |error|
            expect(error.message).to include("representation :user")
            expect(error.message).to include("error :UserNotFound")
          end
      end
    end

    context "with primitive array types" do
      before do
        Trane.operation :list_tags do
          response 200 do
            field :tags, type: :array, of: :string
          end
        end
      end

      it "does not raise for primitive array element types" do
        expect { described_class.validate!(Trane::Registry) }.not_to raise_error
      end
    end

    context "with no operations" do
      it "does not raise" do
        expect { described_class.validate!(Trane::Registry) }.not_to raise_error
      end
    end

    context "when operation error_key matches by short name a FQDN-registered error" do
      before do
        Trane.representation :user do
          field :id, type: :integer
        end

        Trane.errors do
          error "Errors::UserNotFound", status_code: 404, description: "User not found"
        end

        Trane.operation :get_user do
          response 200 do
            field :user, type: :user
          end
          errors do
            key :UserNotFound
          end
        end
      end

      it "does not raise" do
        expect { described_class.validate!(Trane::Registry) }.not_to raise_error
      end
    end

    context "when operation error_key matches by FQDN" do
      before do
        Trane.representation :user do
          field :id, type: :integer
        end

        Trane.errors do
          error "Errors::UserNotFound", status_code: 404, description: "User not found"
        end

        Trane.operation :get_user do
          response 200 do
            field :user, type: :user
          end
          errors do
            key "Errors::UserNotFound"
          end
        end
      end

      it "does not raise" do
        expect { described_class.validate!(Trane::Registry) }.not_to raise_error
      end
    end

    context "with :object type fields" do
      it "does not require a registered representation" do
        Trane.operation :test_op do
          response 200 do
            field :payload, type: :object
            field :meta,    type: :object
          end
        end

        expect { described_class.validate!(Trane::Registry) }.not_to raise_error
      end
    end

    context "when a removed type is referenced" do
      it "raises a boot error for :any" do
        Trane.operation :bad_any_op do
          response 200 do
            field :payload, type: :any
          end
        end

        expect {
          described_class.validate!(Trane::Registry)
        }.to raise_error(Trane::Error, /representation :any.*does not exist/)
      end

      it "raises a boot error for :dynamic" do
        Trane.operation :bad_dynamic_op do
          response 200 do
            field :payload, type: :dynamic
          end
        end

        expect {
          described_class.validate!(Trane::Registry)
        }.to raise_error(Trane::Error, /representation :dynamic.*does not exist/)
      end
    end

    context "when a nested inline field references a nonexistent representation" do
      before do
        Trane.operation :get_user_with_nested do
          response 200 do
            field :user do
              field :address do
                field :city, type: :nonexistent_rep
              end
            end
          end
        end
      end

      it "includes the full dotted field path in the error message" do
        expect { described_class.validate!(Trane::Registry) }
          .to raise_error(Trane::Error, /field :user\.address\.city references representation :nonexistent_rep/)
      end
    end

    context "when a nested inline array field references a nonexistent representation" do
      before do
        Trane.operation :get_org_with_nested_array do
          response 200 do
            field :org do
              field :members, type: :array, of: :nonexistent_member_rep
            end
          end
        end
      end

      it "includes the full dotted field path" do
        expect { described_class.validate!(Trane::Registry) }
          .to raise_error(Trane::Error, /field :org\.members has array of :nonexistent_member_rep/)
      end
    end
  end
end
