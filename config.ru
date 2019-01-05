# frozen_string_literal: true

class Stuffer
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
    body = Async::HTTP::Body::Writable.new(response_content_length, queue: Async::LimitedQueue.new(64))
    chunk_of_random = Random.new.bytes(chunk_size)
    
    Async::Reactor.run do |task|
      begin
        in_chunks_of(response_content_length, chunk_size) do |write_n|
          task.annotate "Writing data"
          body.write(chunk_of_random.slice(0, write_n))
        end
      rescue Errno::EPIPE # disconnect
      ensure
        body.close
      end
    end
    [200, {'Server' => 'stuffer/falcon', 'Connection' => 'close', 'Content-Length' => response_content_length.to_s}, body]
  end
end

run Stuffer.new
