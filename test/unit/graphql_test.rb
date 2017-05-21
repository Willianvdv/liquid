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

    def initialize((attribute_name, *children))
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

def merge_existing_nodes_with_new_nodes(existing_nodes, new_nodes)
  if (existing_node_with_the_same_name = existing_nodes.find { |nodes| nodes.attribute_name == new_nodes.attribute_name })
    existing_node_with_the_same_name.merge_with new_nodes
    existing_nodes
  else
    existing_nodes + [new_nodes]
  end
end

  def liquid_template_to_graphql_fragments(template)
    template = Liquid::Template.parse(template)

    variable_nodes = []
    tags = []

    variable_nodes = template.root.nodelist.map do |node|
      tags << node if node.class == Liquid::Variable

      next unless node.respond_to?(:nodelist)
      node.nodelist.inject(tags) do |new_tags, child_node|
        new_tags << child_node.nodelist.select { |grandchild| !grandchild.is_a?(String)}
      end
    end

    tags.flatten!

    fragments = {}
    tags.each do |tag|
      new_graphql_nodes = GraphQLThing.new tag.name.lookups

      nodes = if (existing_graphql_nodes = fragments[tag.name.name])
        merge_existing_nodes_with_new_nodes(existing_graphql_nodes, new_graphql_nodes)
      else
        [new_graphql_nodes]
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
