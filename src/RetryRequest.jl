module RetryRequest

import ..HTTP
import ..Layer, ..request
using ..IOExtras.isioerror
using ..MessageRequest
using ..Messages
import ..@debug, ..DEBUG_LEVEL

abstract type RetryLayer{Next <: Layer} <: Layer end
export RetryLayer


isrecoverable(e::Exception) = isioerror(e)
isrecoverable(e::Base.DNSError) = true
isrecoverable(e::HTTP.StatusError) = e.status == 403 || # Forbidden
                                     e.status == 408 || # Timeout
                                     e.status >= 500    # Server Error


isrecoverable(e, req, retry_non_idempotent) =
    isrecoverable(e) &&
    !(req.body === body_was_streamed) &&
    !(req.response.body === body_was_streamed) &&
    (retry_non_idempotent || isidempotent(req))
    # "MUST NOT automatically retry a request with a non-idempotent method"
    # https://tools.ietf.org/html/rfc7230#section-6.3.1

function request(::Type{RetryLayer{Next}}, uri, req, body;
                 retries::Int=4, retry_non_idempotent::Bool=false,
                 kw...) where Next

    retry_request = retry(request,
        delays=ExponentialBackOff(n = retries),
        check=(s,ex)->begin
            retry = isrecoverable(ex, req, retry_non_idempotent)
            if retry
                @debug 1 "🔄  Retry $ex: $(sprint(showcompact, req))"
                reset!(req.response)
            else
                @debug 1 "🚷  No Retry: $(no_retry_reason(ex, req))"
            end
            return s, retry
        end)

    retry_request(Next, uri, req, body; kw...)
end


function no_retry_reason(ex, req)
    buf = IOBuffer()
    showcompact(buf, req)
    print(buf, ", ",
        ex isa HTTP.StatusError ? "HTTP $(ex.status): " :
        !isrecoverable(ex) ?  "$ex not recoverable, " : "",
        (req.body === body_was_streamed) ? "request streamed, " : "",
        (req.response.body === body_was_streamed) ? "response streamed, " : "",
        !isidempotent(req) ? "$(req.method) non-idempotent" : "")
    return String(take!(buf))
end


end # module RetryRequest
