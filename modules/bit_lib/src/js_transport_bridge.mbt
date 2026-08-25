///| JS transport registry bridge for injected HTTP transports.

///|
fn js_transport_headers_to_arrays(
  headers : Map[String, String],
) -> (Array[String], Array[String]) {
  let names : Array[String] = []
  let values : Array[String] = []
  for entry in headers.to_array() {
    let (name, value) = entry
    names.push(name)
    values.push(value)
  }
  (names, values)
}

///|
/// The JS transport externs return the body as raw bytes with the HTTP status
/// framed into the first 4 bytes (big-endian). Returning a base64 `String`
/// needs a string 4/3 the size of the payload, which hits V8's maximum string
/// length (0x1fffffe8) at ~384 MiB; returning `Bytes` keeps the payload as a
/// single `Uint8Array` with no per-byte conversion.
fn js_transport_parse_response(
  raw : Bytes,
) -> (@bit.HttpResponse, Bytes) raise @bit.GitError {
  if raw.length() < 4 {
    raise @bit.GitError::ProtocolError("Malformed JS transport response")
  }
  let status = (raw[0].to_int() << 24) |
    (raw[1].to_int() << 16) |
    (raw[2].to_int() << 8) |
    raw[3].to_int()
  let body = FixedArray::make(raw.length() - 4, b'\x00')
  body.blit_from_bytes(0, raw, 4, raw.length() - 4)
  (@bit.HttpResponse::new(status), Bytes::from_fixedarray(body))
}

///|
extern "js" fn lib_js_transport_get(
  transport_id : Int,
  url : String,
  header_names : Array[String],
  header_values : Array[String],
) -> @js_async.Promise[Bytes] =
  #| async (transportId, url, headerNames, headerValues) => {
  #|   const state = globalThis.__bitGitJsTransportState ??= { nextTransportId: 1, transports: new Map() };
  #|   const transport = state.transports.get(transportId);
  #|   if (!transport || typeof transport.get !== 'function') {
  #|     throw new Error(`bit-git js transport ${transportId} not found`);
  #|   }
  #|   const headers = {};
  #|   for (let i = 0; i < Math.min(headerNames?.length ?? 0, headerValues?.length ?? 0); i++) {
  #|     headers[String(headerNames[i])] = String(headerValues[i]);
  #|   }
  #|   const response = await transport.get(url, headers);
  #|   const status = Math.trunc(response?.status ?? response?.code ?? 200);
  #|   const rawBody = response?.body ?? new Uint8Array();
  #|   const bytes = (() => {
  #|     if (rawBody == null) return new Uint8Array();
  #|     if (rawBody instanceof Uint8Array) return rawBody;
  #|     if (typeof ArrayBuffer !== 'undefined' && rawBody instanceof ArrayBuffer) {
  #|       return new Uint8Array(rawBody);
  #|     }
  #|     if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView(rawBody)) {
  #|       return new Uint8Array(rawBody.buffer, rawBody.byteOffset, rawBody.byteLength);
  #|     }
  #|     if (typeof rawBody === 'string') {
  #|       return new TextEncoder().encode(rawBody);
  #|     }
  #|     return Uint8Array.from(rawBody);
  #|   })();
  #|   // Return raw bytes with the status framed into the first 4 bytes
  #|   // (big-endian). A base64 string would need 4/3 of the payload size and
  #|   // hits V8's maximum string length (0x1fffffe8) at ~384 MiB. Framing the
  #|   // status into the payload (instead of a side channel) keeps concurrent
  #|   // requests on the same transport from reading each other's status.
  #|   const framed = new Uint8Array(4 + bytes.length);
  #|   framed[0] = (status >>> 24) & 0xff;
  #|   framed[1] = (status >>> 16) & 0xff;
  #|   framed[2] = (status >>> 8) & 0xff;
  #|   framed[3] = status & 0xff;
  #|   framed.set(bytes, 4);
  #|   return framed;
  #| }

///|
extern "js" fn lib_js_transport_post(
  transport_id : Int,
  url : String,
  body : Bytes,
  header_names : Array[String],
  header_values : Array[String],
) -> @js_async.Promise[Bytes] =
  #| async (transportId, url, body, headerNames, headerValues) => {
  #|   const state = globalThis.__bitGitJsTransportState ??= { nextTransportId: 1, transports: new Map() };
  #|   const transport = state.transports.get(transportId);
  #|   if (!transport || typeof transport.post !== 'function') {
  #|     throw new Error(`bit-git js transport ${transportId} not found`);
  #|   }
  #|   const headers = {};
  #|   for (let i = 0; i < Math.min(headerNames?.length ?? 0, headerValues?.length ?? 0); i++) {
  #|     headers[String(headerNames[i])] = String(headerValues[i]);
  #|   }
  #|   const response = await transport.post(url, body ?? new Uint8Array(0), headers);
  #|   const status = Math.trunc(response?.status ?? response?.code ?? 200);
  #|   const rawBody = response?.body ?? new Uint8Array();
  #|   const bytes = (() => {
  #|     if (rawBody == null) return new Uint8Array();
  #|     if (rawBody instanceof Uint8Array) return rawBody;
  #|     if (typeof ArrayBuffer !== 'undefined' && rawBody instanceof ArrayBuffer) {
  #|       return new Uint8Array(rawBody);
  #|     }
  #|     if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView(rawBody)) {
  #|       return new Uint8Array(rawBody.buffer, rawBody.byteOffset, rawBody.byteLength);
  #|     }
  #|     if (typeof rawBody === 'string') {
  #|       return new TextEncoder().encode(rawBody);
  #|     }
  #|     return Uint8Array.from(rawBody);
  #|   })();
  #|   // Return raw bytes with the status framed into the first 4 bytes
  #|   // (big-endian). A base64 string would need 4/3 of the payload size and
  #|   // hits V8's maximum string length (0x1fffffe8) at ~384 MiB. Framing the
  #|   // status into the payload (instead of a side channel) keeps concurrent
  #|   // requests on the same transport from reading each other's status.
  #|   const framed = new Uint8Array(4 + bytes.length);
  #|   framed[0] = (status >>> 24) & 0xff;
  #|   framed[1] = (status >>> 16) & 0xff;
  #|   framed[2] = (status >>> 8) & 0xff;
  #|   framed[3] = status & 0xff;
  #|   framed.set(bytes, 4);
  #|   return framed;
  #| }

///|
async fn js_transport_get(
  transport_id : Int,
  url : String,
  headers : Map[String, String],
) -> (@bit.HttpResponse, Bytes) raise @bit.GitError {
  let (header_names, header_values) = js_transport_headers_to_arrays(headers)
  let raw = lib_js_transport_get(transport_id, url, header_names, header_values).wait() catch {
    error => raise @bit.GitError::IoError("JS transport GET failed: \{error}")
  }
  js_transport_parse_response(raw)
}

///|
async fn js_transport_post(
  transport_id : Int,
  url : String,
  body : Bytes,
  headers : Map[String, String],
) -> (@bit.HttpResponse, Bytes) raise @bit.GitError {
  let (header_names, header_values) = js_transport_headers_to_arrays(headers)
  let raw = lib_js_transport_post(
    transport_id,
    url,
    body,
    header_names,
    header_values,
  ).wait() catch {
    error => raise @bit.GitError::IoError("JS transport POST failed: \{error}")
  }
  js_transport_parse_response(raw)
}
