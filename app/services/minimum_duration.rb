# frozen_string_literal: true

# Runs a block and makes sure it takes at least a minimum time (MH-406). Used so
# the answer for an address with an account, which does database writes and
# queues an email, takes as long as the answer for one without.
module MinimumDuration
  module_function

  def call(minimum, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    started = clock.call
    yield
  ensure
    remaining = minimum - (clock.call - started)
    pause(remaining) if remaining.positive?
  end

  def pause(seconds)
    Kernel.sleep(seconds)
  end
end
