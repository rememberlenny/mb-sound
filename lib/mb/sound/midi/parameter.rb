module MB
  module Sound
    module MIDI
      # Represents a parameter controllable by MIDI message (e.g. control
      # change, pitch bend), with smoothing of the output.
      #
      # Filtering/smoothing is updated for every call to #value.
      class Parameter
        # MIDI event ranges for different MIDI event types.
        RAW_RANGE = {
          MIDIMessage::NoteOn => 0..127,
          MIDIMessage::NoteOff => 0..127,
          MIDIMessage::ControlChange => 0..127, # TODO: support MSB/LSB and NRPN?
          MIDIMessage::ProgramChange => 0..127,
          MIDIMessage::PitchBend => 0..16383,
          MIDIMessage::ChannelAftertouch => 0..127,
          MIDIMessage::PolyphonicAftertouch => 0..127,
        }

        attr_reader :message, :default, :raw_default, :range, :raw_range, :update_rate, :description

        # The last filtered and scaled value calculated for the parameter, or
        # the default value if no changes have been received.  This is useful
        # for getting the current state of a parameter (e.g. for display)
        # without updating the filter state.
        #
        # This is updated whenever #value is called.
        attr_reader :last_value

        # The last-received (or default) raw value of the parameter, or the
        # default value in the raw range if no MIDI events have changed the
        # value.
        attr_reader :raw_value

        # Initializes a MIDI-controllable smoothed parameter.
        #
        # The +:message+ is a template MIDIMessage (from the midi-message gem)
        # that will be used to reject non-matching messages given to #notify.
        # The template message's channel may be set to nil or -1 to listen on
        # all channels.
        #
        # For MIDIMessage::NoteOn and MIDIMessage::NoteOff, if the note number
        # is -1 or nil, then the note number is used.  Otherwise the velocity
        # is used.
        #
        # The MIDI message's range (e.g. 0..127 or 0..16383) will be scaled to
        # the given output +:range+.
        #
        # The starting value is normally the beginning of the given +:range+,
        # but may be changed with the +:default+ parameter.
        #
        # The +:rise+ and +:fall+ parameters control how far a parameter may
        # increase or decrease per second, specified in the output range and
        # based on +:update_rate+.  The default is to allow full range jumps in
        # a single update.  See MB::Sound::Filter::LinearFollower.
        #
        # The +:filter_hz+ parameter controls the cutoff frequency of a
        # low-pass, single-pole (to avoid ringing) filter that is applied after
        # +:max_rise+ and +:max_fall+.  See MB::Sound::Filter::FirstOrder.
        def initialize(message:, range: 0.0..1.0, default: nil, max_rise: nil, max_fall: nil, filter_hz: 15, update_rate: 60, description: nil)
          @range = range

          @raw_range = RAW_RANGE[message.class]
          raise "Unsupported message type #{message.class}" if @raw_range.nil?

          @min = [range.begin, range.end].min
          @max = [range.begin, range.end].max
          @width = (@max - @min).abs

          @default = default || range.begin
          @raw_default = MB::M.scale(@default, @range, @raw_range).round
          @update_rate = update_rate

          # Call #notify to validate the message type
          @message = message
          notify(message)

          @description = description&.to_s || default_description(message)

          # TODO: Allow bypassing the filters
          @filter = MB::Sound::Filter::FilterChain.new(
            @follower = MB::Sound::Filter::LinearFollower.new(
              rate: update_rate,
              max_rise: max_rise || (@width * update_rate),
              max_fall: max_fall || (@width * update_rate)
            ),
            @lowpass = filter_hz.hz.at_rate(update_rate).lowpass1p
          )

          # Set the starting value to the default
          reset(@default)
        end

        # Checks if the given +message+ matches the template that was given to
        # the constructor, and if so, updates the pre-filtered value
        # accordingly.
        def notify(message)
          return if message.class != @message.class
          return if @message.respond_to?(:channel) && @message.channel && @message.channel >= 0 && @message.channel != message.channel

          case @message
          when MIDIMessage::NoteOn, MIDIMessage::NoteOff
            # If a note number was given to the constructor, use velocity.
            # Otherwise, use note number.
            if @message.note && @message.note >= 0 && @message.note <= 127
              @raw_value = message.velocity
            else
              @raw_value = message.note
            end

          when MIDIMessage::ControlChange
            # TODO: support MSB+LSB for higher resolution?
            # TODO: support NRPN?
            if @message.index == message.index
              @raw_value = message.value
            end

          when MIDIMessage::ProgramChange
            @raw_value = message.program

          when MIDIMessage::PitchBend
            @raw_value = message.high * 128 + message.low

          when MIDIMessage::ChannelAftertouch
            @raw_value = message.value

          when MIDIMessage::PolyphonicAftertouch
            if @message.note == message.note
              @raw_value = message.value
            end

          else
            raise "Unsupported message type: #{message.class}"
          end

          @value = MB::M.scale(@raw_value, @raw_range, @range)
        end

        # Sets the pre-filtered value of the parameter, clamping to the
        # parameter's range.  Smoothing and filtering will still apply.
        def value=(v)
          @value = MB::M.clamp(v, @min, @max)
          @raw_value = MB::M.scale(@value, @range, @raw_range)
        end

        # Immediately sets the post-filtered value of the parameter, bypassing
        # smoothing and filtering.  Pass nil to reset to the initial default.
        def reset(v)
          @value = @filter.reset(v || @default)
          @raw_value = MB::M.scale(@value, @range, @raw_range).round
          @last_value = @value
        end

        # Retrieves the current smoothed/filtered value of the parameter, and
        # updates the filter.  This should be called 60 times per second (or
        # whatever was given to the constructor's :update_rate parameter).
        #
        # Use #last_value to retrieve the parameter value without updating the
        # filter (e.g. for displaying in a UI).
        def value(count = nil)
          @last_value = MB::M.clamp(@filter.process([@value])[0], @min, @max)
        end

        # Returns Builder-generated XML describing this parameter in the format
        # used by Sony/MAGIX ACID.  Pass the parent element in +xml+ to nest
        # within another XML element.
        #
        # You will need the Builder gem in your project to use this method.
        def to_acid_xml(xml = nil)
          require 'builder'

          xml ||= Builder::XmlMarkup.new(indent: 2)
          xml.param(name: @description) do |p|
            p.flags do |f|
              f.flag('DEFAULT')
              f.flag('ACTIVE')
              f.flag('LOCAL')
            end

            if @message.is_a?(MIDIMessage::ControlChange)
              p.ChannelMask(1)
            else
              p.ChannelMask(65535)
            end

            p.MIDIMsg(@message.to_byte_array[0])

            if @message.is_a?(MIDIMessage::ControlChange)
              p.ccMsg(@message.index)
            else
              p.ccMsg(0)
            end

            p.CurveType('LINEAR')
            p.CurveMask do |c|
              c.curve('HOLD')
              c.curve('LINEAR')
              c.curve('LOG FAST')
              c.curve('LOG SLOW')
              c.curve('CUBIC SHARP TANGENT')
              c.curve('CUBIC SMOOTH')
            end

            p.Min(@raw_range.min)
            p.Max(@raw_range.max)
            p.Neutral(@raw_default)
          end

          xml

        rescue LoadError => e
          raise 'The builder gem is required for generating ACID controller XML templates'
        end

        private

        def default_description(message)
          case message
          when MIDIMessage::NoteOn, MIDIMessage::NoteOff
            if message.note && message.note >= 0 && message.note <= 127
              "Note #{message.note} Velocity"
            else
              'Note Number'
            end

          when MIDIMessage::ControlChange
            name = message.name
            "CC #{message.index}#{name ? " (#{name})" : ''}"

          when MIDIMessage::PitchBend
            'Pitch Bend'

          when MIDIMessage::ChannelAftertouch
            'Aftertouch'

          when MIDIMessage::PolyphonicAftertouch
            'Polyphonic Aftertouch'

          when MIDIMessage::ProgramChange
            'Program Change'

          else
            raise "Unsupported message class #{message.class}"
          end
        end
      end
    end
  end
end
