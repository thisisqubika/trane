# frozen_string_literal: true

RSpec.describe Trane::Docs::HtmlRenderer do
  let(:definition) do
    {
      service: { name: "testapi" },
      operations: [
        {
          id: "get_user",
          summary: "Get a user by id",
          method: "GET",
          path: "/users/:id",
          request: {
            params: [
              { name: "id", type: "integer", location: "path", required: true }
            ]
          },
          responses: [
            {
              status: 200,
              fields: [
                { name: "user", type: "user" }
              ]
            }
          ],
          errors: ["UserNotFound"]
        },
        {
          id: "create_user",
          summary: "Create a user",
          method: "POST",
          path: "/users",
          request: {
            body: [
              { name: "user", type: "object", required: true, children: [
                { name: "name", type: "string", required: true },
                { name: "email", type: "string", required: false }
              ] }
            ]
          },
          responses: [
            { status: 201, fields: [{ name: "user", type: "user" }] }
          ]
        }
      ],
      representations: [
        {
          name: "user",
          fields: [
            { name: "id", type: "integer" },
            { name: "name", type: "string" },
            { name: "nickname", type: "string", extra: true },
            { name: "birthday", type: "date", format: "iso8601" }
          ]
        }
      ],
      errors: [
        { key: "UserNotFound", status_code: 404, description: "User not found" }
      ]
    }
  end

  describe ".render" do
    subject(:html) { described_class.render(definition) }

    it "produces valid HTML" do
      expect(html).to include("<!DOCTYPE html>")
      expect(html).to include("</html>")
    end

    it "includes the service name in the title" do
      expect(html).to include("testapi API Documentation")
    end

    it "includes operation id inside the operation card header" do
      expect(html).to match(
        %r{<div\s+class="op-card"\s+id="op-get_user".*?<code\s+class="op-id">get_user</code>}m
      )
    end

    it "includes operation id for every operation card" do
      definition[:operations].each do |op|
        expect(html).to include(%(<code class="op-id">#{op[:id]}</code>))
      end
    end

    it "includes HTTP methods" do
      expect(html).to include("GET")
      expect(html).to include("POST")
    end

    it "includes paths" do
      expect(html).to include("/users/:id")
      expect(html).to include("/users")
    end

    it "includes representation names" do
      expect(html).to include('id="rep-user"')
    end

    it "includes representation field names" do
      expect(html).to include("birthday")
      expect(html).to include("nickname")
    end

    it "includes extra badge for extra fields" do
      expect(html).to include("extra")
    end

    it "includes format badge" do
      expect(html).to include("iso8601")
    end

    it "includes error catalog" do
      expect(html).to include("Error Catalog")
      expect(html).to include("UserNotFound")
      expect(html).to include("404")
      expect(html).to include("User not found")
    end

    it "includes cross-links for representation types" do
      expect(html).to include('href="#rep-user"')
    end

    it "includes sidebar navigation" do
      expect(html).to include('class="sidebar"')
      expect(html).to include('href="#op-get_user"')
    end

    it "includes collapsible sections" do
      expect(html).to include("<details")
      expect(html).to include("<summary>")
    end

    it "includes Required column header in body table" do
      expect(html).to include("<th>Required</th>")
    end

    it "shows required badge for body fields with required: true" do
      expect(html).to include('<span class="badge required">required</span>')
    end

    it "shows optional badge for body fields with required: false" do
      expect(html).to include('<span class="badge optional">optional</span>')
    end

    it "does not include Required column in response tables" do
      response_section = html[/Response.*?<\/details>/m]
      expect(response_section).not_to include("<th>Required</th>")
    end

    it "does not include Required column in representation tables" do
      rep_section = html[/id="rep-user".*?<\/div>/m]
      expect(rep_section).not_to include("<th>Required</th>")
    end

    context "with enum values on fields and params" do
      let(:definition_with_enum) do
        definition.merge(
          operations: [
            {
              id: "list_items",
              summary: "List items",
              method: "GET",
              path: "/items",
              request: {
                params: [
                  { name: "sort", type: "string", location: "query", required: false, enum: ["asc", "desc"] },
                  { name: "page", type: "integer", location: "query", required: false }
                ]
              },
              responses: [
                { status: 200, fields: [{ name: "items", type: "array", array_of: "item" }] }
              ]
            }
          ],
          representations: [
            {
              name: "item",
              fields: [
                { name: "status", type: "string", enum: ["active", "archived"] },
                { name: "count", type: "integer" }
              ]
            }
          ]
        )
      end

      subject(:html_with_enum) { described_class.render(definition_with_enum) }

      it "renders enum-values div for representation fields with enum" do
        expect(html_with_enum).to include('<div class="enum-values">enum: active, archived</div>')
      end

      it "does not render enum-values div for fields without enum" do
        expect(html_with_enum).not_to include("enum: 0")
      end

      it "renders enum-values div for query params with enum" do
        expect(html_with_enum).to include('<div class="enum-values">enum: asc, desc</div>')
      end

      it "does not render enum-values div for query params without enum" do
        sort_count = html_with_enum.scan('class="enum-values"').count
        expect(sort_count).to eq(2)
      end
    end
  end
end
