require 'test_helper'

class GraphQLUnitTest < Minitest::Test
  include Liquid


  class Thing
    attr_reader :thing, :children
    def initialize(thing, children)
      @thing = thing
      @children = children || []
    end

    def merge_with(other_thing)
      @children += [other_thing.children]
#      children |= other_thing.children
      self
    end

    def to_graphql
      attributes_to_graphql([thing] + children)
    end

    private

    def attributes_to_graphql(attributes)
      thing, *children = attributes
      if children.size == 1 && children[0].is_a?(Array)
        "#{thing} #{attributes_to_graphql children[0]}"
      elsif children.size > 0
        "#{thing} { #{attributes_to_graphql children} }"
      else
        thing
      end
    end
  end


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
        Thing.new(attribute, deep_attributes)
      end

      fragments = Hash.new {|h,k| h[k] = [] }
      tags.each do |tag|
        #children = Hash.new {|h,k| h[k] = [] }

        existing_fragments = fragments[tag.name.name]
        new_fragment = transform_tag_to_graphql(tag.name.lookups)

        if existing_fragments.size > 0
          merged = false
          existing_fragments_merged_with_news = existing_fragments.map do |fragment|
            if fragment.thing == new_fragment.thing
              merged = true
              fragment.merge_with(new_fragment)
            else
              fragment
            end
          end

          unless merged
            existing_fragments_merged_with_news << new_fragment
          end

          fragments[tag.name.name] = existing_fragments_merged_with_news
        else
          fragments[tag.name.name] << new_fragment
        end
      end

      fragments.map do |k, v|
         <<-EOS
fragment on #{k.capitalize} {
  #{v.map(&:to_graphql).join(" ")}
}
      EOS
      end
    end

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
    assert_equal magic(template), [user_fragment, deep_nested_fragment, product_fragment]

  end
end
