require 'test_helper'

class GraphQLUnitTest < Minitest::Test
  include Liquid

  def test_to_query
    def magic(template)
      template = Liquid::Template.parse(template)

      all_the_nodes = template.root.nodelist
      variable_nodes = all_the_nodes.select do |node|
        node.class < Liquid::Tag || node.class == Liquid::Variable
      end

      def find_them_tags(nodelist, tags=[])
        tags = nodelist.select { |node| node.class != String }
        tags.map { |node| node.class == Liquid::Variable ? node : find_them_tags(node.nodelist) }
      end

      tags = variable_nodes.map { |node| node.class == Liquid::Variable ? node : find_them_tags(node.nodelist) }.flatten

      def transform_tag_to_graphql(lookups)
        attribute, *deep_attributes = lookups
        if deep_attributes.any?
          # warning: recursion!
          "#{attribute} { #{transform_tag_to_graphql deep_attributes} }"
        else
          attribute
        end
      end

      fragments = Hash.new {|h,k| h[k] = [] }
      tags.each do |tag|
        fragments[tag.name.name] << transform_tag_to_graphql(tag.name.lookups)
      end

      fragments.map do |k, v|
         <<-EOS
fragment on #{k.capitalize} {
  #{v.join(" ")}
}
      EOS
      end
    end

    template = %{
      <h1>Hi {{ user.name }} from {{ user.address.city }}</h1>
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
  name address { city }
}
      EOS

    product_fragment = <<-EOS
fragment on Product {
  name price description
}
      EOS
    assert_equal magic(template), [user_fragment, product_fragment]

  end
end
