require 'test_helper'

class GraphQLUnitTest < Minitest::Test
  include Liquid

  def test_to_graphql_query
    template = %{
      <h1>Hi {{ user.name }} from {{ user.address.city }}, {{ user.address.country.iso }}</h1>
      {{ a.b.c.d.e.f.g }}
      <ul id="products">
        {% for product in products %}
          <li>
            <h2>{{ product.name }}</h2>
            Only {{ product.price | price }}

            {{ product.description | prettyprint | paragraph }}
          </li>
        {% endfor %}
     </ul>
    }

    user_fragment = <<-EOS
fragment on User {
  name address { city country { iso } }
}
      EOS

    deep_nested_fragment = <<-EOS
fragment on A {
  b { c { d { e { f { g } } } } }
}
      EOS

    product_fragment = <<-EOS
fragment on Product {
  name price description
}
      EOS
    assert_equal liquid_template_to_graphql_fragments(template), [user_fragment, deep_nested_fragment, product_fragment]
  end

  # ---

  class GraphQLThing
    attr_reader :attribute_name, :children

    def initialize(attribute_name, children)
      @attribute_name = attribute_name
      @children = children || []
    end

    def merge_with(other_thing)
      @children += [other_thing.children]

      self
    end

    def to_graphql
      attributes_to_graphql([attribute_name] + children)
    end

    private

    def attributes_to_graphql(attributes)
      attribute_name, *children = attributes
      if children.size == 1 && children[0].is_a?(Array)
        "#{attribute_name} #{attributes_to_graphql children[0]}"
      elsif children.size > 0
        "#{attribute_name} { #{attributes_to_graphql children} }"
      else
        attribute_name
      end
    end
  end

  def transform_tag_to_graphql((attribute, *deep_attributes))
    GraphQLThing.new attribute, deep_attributes
  end

  def liquid_template_to_graphql_fragments(template)
    template = Liquid::Template.parse(template)

    variable_nodes = []
    tags = []

    variable_nodes = template.root.nodelist.map do |node|
      tags << node if node.class == Liquid::Variable

      if node.respond_to?(:nodelist)
        tags << node.nodelist.map do |child_node|
          child_node.nodelist.select do |node|
            node.class != String
          end
        end
      end
    end

    tags.flatten!

    fragments = {}
    tags.each do |tag|
      new_graphql_nodes = transform_tag_to_graphql(tag.name.lookups)

      nodes = unless (existing_graphql_nodes = fragments[tag.name.name])
        [new_graphql_nodes]
      else
        merged = false
        existing_graphql_nodes_merged_with_new_nodes = existing_graphql_nodes.map do |graphql_node|
          if graphql_node.attribute_name == new_graphql_nodes.attribute_name
            merged = true
            graphql_node.merge_with new_graphql_nodes
          else
            graphql_node
          end
        end

        nodes = unless merged
          existing_graphql_nodes_merged_with_new_nodes << new_graphql_nodes
        else
          existing_graphql_nodes_merged_with_new_nodes
        end
      end

      fragments[tag.name.name] = nodes
    end

    fragments.map do |k, v|
         <<-EOS
fragment on #{k.capitalize} {
  #{v.map(&:to_graphql).join(" ")}
}
      EOS
    end
  end
end
