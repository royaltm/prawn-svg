#
# Prawn::Svg::Interface makes a Prawn::Svg::Document instance, uses that object to parse the supplied
# SVG into Prawn-compatible method calls, and then calls the Prawn methods.
#
module Prawn
  module Svg

    class Delta
      def initialize(n)
        @n = n
      end
      def +(value)
        @n + value
      end
      ZERO = Delta.new(0)
    end

    class Interface
      DEFAULT_FONT_PATHS = ["/Library/Fonts", "/System/Library/Fonts", "#{ENV["HOME"]}/Library/Fonts", "/usr/share/fonts/truetype"]

      @font_path = []
      DEFAULT_FONT_PATHS.each {|path| @font_path << path if File.exists?(path)}

      class << self; attr_accessor :font_path; end

      attr_reader :data, :prawn, :document, :options

      #
      # Creates a Prawn::Svg object.
      #
      # +data+ is the SVG data to convert.  +prawn+ is your Prawn::Document object.
      #
      # +options+ can contain the key :at, which takes a tuple of x and y co-ordinates.
      # If :at is not specified the coordinates [0, cursor] are used.
      # In this instance if the current bounds are the margin bounds and if the
      # rendered SVG overflows the current page, a new page is created.
      #
      # +options+ can optionally contain the key :width or :height.  If both are
      # specified, only :width will be used.
      #
      def initialize(data, prawn, options)
        @data = data
        @prawn = prawn
        @options = options

        Prawn::Svg::Font.load_external_fonts(prawn.font_families)

        @document = Document.new(data, [prawn.bounds.width, prawn.bounds.height], options)
      end

      #
      # Draws the SVG to the Prawn::Document object.
      #
      def draw
        x, y = @options[:at]
        unless y
          x ||= 0
          y = prawn.cursor
          if prawn.bounds.parent.nil? && y - @document.height < 0
            prawn.bounds.move_past_bottom
            y = prawn.cursor
          end
        end
        prawn.bounding_box([x,y], :width => @document.width, :height => @document.height) do
          prawn.save_graphics_state do
            clip_rectangle 0, 0, @document.width, @document.height
            proc_creator(prawn, Parser.new(@document).parse).call
          end
        end
      end


      private
      def proc_creator(prawn, calls)
        Proc.new {issue_prawn_command(prawn, calls)}
      end

      def issue_prawn_command(prawn, calls)
        calls.each do |call, arguments, children|
          if rewrite_call_arguments(prawn, call, arguments) == false
            issue_prawn_command(prawn, children) if children.any?
          else
            if children.empty?
              prawn.send(call, *arguments)
            else
              prawn.send(call, *arguments, &proc_creator(prawn, children))
            end
          end
        end
      end

      def rewrite_call_arguments(prawn, call, arguments)

        case call
        when 'text_group'
          @relative_text_position = nil
          false

        when 'text_box'
          text, options = arguments
          at = options[:at]
          at[0] += @relative_text_position if at[0].is_a?(Delta)

          width = options[:width]
          size = options[:size] || prawn.font_size
          text_width = prawn.width_of(text, options.merge(:kerning => true))
          options[:size] = size = size.to_f * width / text_width
          options[:height] = size
          options[:at][1] += size

          if (anchor = options.delete(:text_anchor)) && %w(middle end).include?(anchor)
            width /= 2 if anchor == 'middle'
            at[0] -= width
          end

          @relative_text_position = at[0] + width

        when 'draw_text'
          text, options = arguments
          at = options[:at]
          at[0] += @relative_text_position if at[0].is_a?(Delta)

          width = prawn.width_of(text, options.merge(:kerning => true))

          if (anchor = options.delete(:text_anchor)) && %w(middle end).include?(anchor)
            width /= 2 if anchor == 'middle'
            at[0] -= width
          end

          # space_width = prawn.width_of("n", options)
          @relative_text_position = at[0] + width

        when 'transformation_matrix'
          left = prawn.bounds.absolute_left
          top = prawn.bounds.absolute_top
          arguments[4] += left - (left * arguments[0] + top * arguments[2])
          arguments[5] += top - (left * arguments[1] + top * arguments[3])

        when 'clip'
          prawn.add_content "W n" # clip to path
          false

        when 'save'
          prawn.save_graphics_state
          false

        when 'restore'
          prawn.restore_graphics_state
          false
        end
      end

      def clip_rectangle(x, y, width, height)
          prawn.move_to x, y
          prawn.line_to x + width, y
          prawn.line_to x + width, y + height
          prawn.line_to x, y + height
          prawn.close_path
          prawn.add_content "W n" # clip to path
      end
    end
  end
end
