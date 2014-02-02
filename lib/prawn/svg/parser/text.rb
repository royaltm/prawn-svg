class Prawn::Svg::Parser::Text
  Delta = Prawn::Svg::Delta
  def parse(element)
    element.add_call_and_enter "text_group"
    internal_parse(element, [element.document.x(0)], [element.document.y(0)])
  end

  protected
  def internal_parse(element, x_positions, y_positions)
    attrs = element.attributes

    if attrs['x']
      old_x_position = x_positions
      x_positions = attrs['x'].split(/[\s,]+/).collect {|n| element.document.x(n)}
      x_positions.concat(old_x_position[x_positions.length..-1]) if old_x_position.length > x_positions.length
    end

    if attrs['y']
      old_y_position = y_positions
      y_positions = attrs['y'].split(/[\s,]+/).collect {|n| element.document.y(n)}
      y_positions.concat(old_y_position[y_positions.length..-1]) if old_y_position.length > y_positions.length
    end

    if attrs['dx']
      dx_positions = attrs['dx'].to_s.split(/[\s,]+/).collect {|n| element.document.distance(n)}
      dx_positions.slice!(0...x_positions.length).each_with_index {|dx,i| x_positions[i] += dx }
      dx_positions.each {|dx| x_positions << Delta.new(dx)}
    end

    if attrs['dy']
      dy_positions = attrs['dy'].to_s.split(/[\s,]+/).collect {|n| -element.document.distance(n)}
      dy_positions.slice!(0...y_positions.length).each_with_index {|dy,i| y_positions[i] += dy }
      dy_positions.each {|dy| y_positions << y_positions.last + dy}
    end

    opts = {}
    if size = element.state[:font_size]
      opts[:size] = size
    end
    opts[:style] = element.state[:font_subfamily]

    # This is not a prawn option but we can't work out how to render it here -
    # it's handled by Svg#rewrite_call_arguments
    if anchor = attrs['text-anchor']
      opts[:text_anchor] = anchor
    end

    if text_length = element.document.distance(attrs['textLength'])
      text_command = 'text_box'
      opts[:width] = text_length
      opts[:overflow] = :shrink_to_fit
    else
      text_command = 'draw_text'
    end

    element.element.children.each do |child|
      if child.node_type == :text
        text = child.value.strip.gsub(/\s+/, " ")

        while text != ""
          opts[:at] = [x_positions.first, y_positions.first]

          if x_positions.length > 1 || y_positions.length > 1
            element.add_call text_command, text[0..0], opts.dup
            text = text[1..-1]

            if x_positions.length > 1
              x_positions.shift
            else
              x_positions[0] = Delta::ZERO
            end
            y_positions.shift if y_positions.length > 1
          else
            element.add_call text_command, text, opts.dup
            x_positions[0] = Delta::ZERO
            break
          end
        end

      elsif child.name == "tspan"
        element.add_call 'save'
        child.attributes['text-anchor'] ||= opts[:text_anchor] if opts[:text_anchor]
        child_element = Prawn::Svg::Element.new(element.document, child, element.calls, element.state.dup)
        internal_parse(child_element, x_positions, y_positions)
        child_element.append_calls_to_parent
        element.add_call 'restore'

      else
        element.warnings << "Unknown tag '#{child.name}' inside text tag; ignoring"
      end
    end
  end
end
