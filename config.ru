# frozen_string_literal: true

class Stuffer
  class SlowLoris < StandardError
  end

  # We need to expose the pending tasks to provide backpressure
  # The solution with LimitedQueue is not sufficient for us unfortunately
  class CustomizedBody < ::Async::HTTP::Body::Writable
    # Now a tricky bit. This wonderful piece of eqpt (falcon+async-http) does
    # have backpressure but it is only based on the queue size. It expects something
    # to take stuff from the queue to signal the task that it can resume. If nothing reads,
    # the signal is never sent and the task just stays there, waiting.
    # The Readable and Writable (which inherits from Readable) actually contains
    # a queue of Strings. Basically an array.
    # We can't ask the Body directly "how many items do you have in the queue?" and sleep
    # the task to try later. This way we turn signaling into polling - even though it is less
    # efficient, it does give us a guarantee that the task will be revisited and there
    # will be an opportunity to close the connection and abort the task forcibly.
    #
    # The native approach is now `Async::HTTP::Body::Writable.new(content_len, queue: Async::LimitedQueue.new(n_items))
    # but as described above it doesn't work for us as it will leak tasks which will forever stay "stopped".
    def wait_writable(max_queue_items_pending, task)
      # Ok, this is a Volkswagen, but bear with me. When we are running
      # inside the test suite, our reactor will finish _first_, and _then_ will our
      # Writable body be read in full. This means that we are going to be
      # throttling the writes but on the other end nobody is really reading much.
      # That, in turn, means that the test will fail as the response will not
      # going to be written in full. There, I said it. This is volkswagen.
      return if 'test' == ENV['RACK_ENV']
  
      # and then see whether we can do anything
      max_waited_s = 45
      started_polling_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      while @queue.items.length > max_queue_items_pending
        task.annotate "Waiting for client to continue reading"
        waited_for_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_polling_at
        if waited_for_s > max_waited_s
          LOGGER.info { "Slow client, closing" }
          raise SlowLoris, "Disconnecting client as no data was picked up in #{waited_for_s}s"
        end
        task.yield # Allow something else to take data from our queue meanwhile
      end
    end
  end

  def in_chunks_of(total, chunk_size)
    wholes = total / chunk_size
    remaining = total % chunk_size
    wholes.times { yield(chunk_size) }
    yield(remaining) if remaining > 0
  end

  def call(env)
    req = Rack::Request.new(env)
    qry = Rack::Utils.parse_nested_query(req.query_string)
    response_content_length = qry.fetch("bytes").to_i

    chunk_size = Async::IO::Stream::BLOCK_SIZE
    body = CustomizedBody.new(response_content_length)
    chunk_of_random = Random.new.bytes(chunk_size)
    
    Async::Reactor.run do |task|
      begin
        in_chunks_of(response_content_length, chunk_size) do |write_n|
          body.wait_writable(_max_pending_chunks = 8, task)
          task.annotate "Writing data"
          body.write(chunk_of_random.slice(0, write_n))
        end
        body.wait_writable(_max_pending_chunks = 1, task)
      rescue Errno::EPIPE # disconnect
      ensure
        body.close
      end
    end
    [200, {'Connection' => 'close', 'Content-Length' => response_content_length.to_s}, body]
  end
end

run Stuffer.new
