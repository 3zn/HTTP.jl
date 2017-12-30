module StreamRequest

import ..Layer, ..request
using ..IOExtras
using ..Parsers
using ..Messages
using ..HTTPStreams
import ..ConnectionPool
using ..MessageRequest
import ..@debugshort, ..DEBUG_LEVEL, ..printlncompact

abstract type StreamLayer <: Layer end
export StreamLayer


writebody(http, req, body) = for chunk in body write(http, req, chunk) end

function writebody(http, req, body::IO)
    req.body = body_was_streamed
    write(http, body)
end


"""
    request(StreamLayer, ::IO, ::Request, body) -> ::Response

Send a `Request` and return a `Response`.
Send the `Request` body in a background task and begin reading the response
immediately so that the transmission can be aborted if the `Response` status
indicates that the server does wish to receive the message body
[https://tools.ietf.org/html/rfc7230#section-6.5](RFC7230 6.5).
"""

function request(::Type{StreamLayer}, io::IO, req::Request, body;
                 response_stream=nothing,
                 iofunction=nothing,
                 verbose::Int=0,
                 kw...)::Response

    verbose == 1 && printlncompact(req)
    verbose >= 2 && println(req)

    http = HTTPStream(io, req, ConnectionPool.getparser(io))

    if iofunction != nothing
        iofunction(http)
        closewrite(http)
        closeread(http)
    else

        write_body_task = @async begin
            if req.body === body_is_a_stream
                writebody(http, req, body)
            else
                write(http, req.body)
            end
            closewrite(http)
        end
        yield()

        startread(http)
        if response_stream == nothing
            req.response.body = read(http)
        else
            req.response.body = body_was_streamed
            write(response_stream, http)
        end

        closeread(http)
        wait(write_body_task)
    end


    verbose == 1 && printlncompact(req.response)
    verbose >= 2 && println(req.response)

    return req.response
end


end # module StreamRequest
