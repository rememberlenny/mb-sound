module MB
  module Sound
    class Filter
      # Follows the value (or absolute value) of incoming samples with some
      # maximum velocity up or down.  If the signal's derivative is always
      # lower than the max, then the signal passes unaltered.
      #
      # If the derivative is greater than the max, then the output rises at the
      # maximum rate until it either reaches the input value, or the input
      # drops below the output.
      #
      # Different upward and downward maximums may be set.
      #
      # One application of this class is smoothing control parameter changes.
      #
      # This is analogous to a slew rate limiter, and will have strange
      # nonlinear effects if applied to audio.
      class LinearFollower < Filter
        # The sample rate given to the constructor, in Hz.
        attr_reader :rate

        # The computed maximum fall rate, in units *per sample*.
        attr_reader :max_fall

        # The computed maximum rise rate, in units *per sample*.
        attr_reader :max_rise

        # Whether the absolute value of the signal is followed (true), or the
        # original unmodified signal (false).
        attr_reader :absolute

        # Initializes a velocity-limited signal follower.
        #
        # +:rate+ is the sample rate of the system in Hz.  Pass 1.0 if you want
        #         to specify +:max_rise+ and +:max_fall+ as per-sample, rather
        #         than per-second, values.
        # +:max_rise+ is the maximum positive derivative, in units per second
        #             (not per sample!).  This may be positive or negative as
        #             the absolute value of +:max_rise+ is used.  Set to nil to
        #             allow through all signals that rise above the current
        #             output.
        # +:max_fall+ is the maximum negative derivative, in units per second
        #             (not per sample).  This may be positive or negative, as
        #             the negative absolute value of +:max_fall+ is used.  Set
        #             to nil to allow through all signals that fall below the
        #             current output.
        # +:absolute+ toggles the use of the absolute value of the input
        #             signal.  If true, then the signal's absolute value is
        #             used and this functions like a linear envelope follower.
        #             If false, then the positive and negative values of the
        #             signal are preserved.
        def initialize(rate:, max_rise:, max_fall:, absolute: false)
          # TODO: would there be some way of doing this with complex numbers?
          # maybe impose different limits on +re, -re, +im, and -im?  Or limits
          # on +/-mag and +/-phase.  Would that have any use?

          raise 'Sample rate must be a positive number' unless rate.is_a?(Numeric) && rate > 0
          @rate = rate.to_f

          # parameters are rate per second, internal storage is rate per sample
          @max_fall = max_fall && max_fall.abs.to_f / @rate
          @max_rise = max_rise && max_rise.abs.to_f / @rate

          @absolute = !!absolute

          @s = 0.0
        end

        # Resets the output to 0, or to the given value.
        def reset(initial_value = 0.0)
          @s = initial_value
        end

        # Processes the given array of samples, updating the state of the
        # follower along the way.  Returns the velocity-limited result.
        # Supports in-place processing of NArray.
        def process(samples)
          samples.map { |s|
            s = s.abs if @absolute

            rise = @max_rise && @s + @max_rise
            fall = @max_fall && @s - @max_fall

            if rise && s > rise
              @s = rise
            elsif fall && s < fall
              @s = fall
            else
              @s = s
            end
          }
        end
      end
    end
  end
end
