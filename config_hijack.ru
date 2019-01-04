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

    chunk_size = 8 * 1024 # Async::IO::Stream::BLOCK_SIZE
    hj = proc do |io|
      chunk_of_random = Random.new.bytes(chunk_size)
      in_chunks_of(response_content_length, chunk_size) do |write_n|
        io.write(chunk_of_random.slice(0, write_n))
      end
      io.close
    end

    [200, {'Server' => 'stuffer/puma', 'Connection' => 'close', 'Content-Length' => response_content_length.to_s, 'rack.hijack' => hj}, []]
  end
end

run Stuffer.new
