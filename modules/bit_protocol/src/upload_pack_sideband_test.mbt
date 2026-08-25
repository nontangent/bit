///|
/// Side-band packfile assembly in `parse_fetch_response_v2` / `_v0`.
///
/// Band-1 payloads are collected as one fragment per pkt-line and joined once,
/// instead of being pushed byte-by-byte into an `Array[Byte]`. On the JS
/// backend `Array[Byte]` is a boxed array, so the old shape capped packfiles at
/// ~80 MiB (V8's maximum array length). These tests pin the observable
/// contract of the new shape: byte-exact concatenation across fragment
/// boundaries, empty packs, and band-3 errors.
fn band(channel : Byte, payload : Bytes) -> Bytes {
  let out = FixedArray::make(payload.length() + 1, channel)
  out.blit_from_bytes(1, payload, 0, payload.length())
  pktline_encode_bytes(Bytes::from_fixedarray(out))
}

///|
fn concat(parts : Array[Bytes]) -> Bytes {
  let mut total = 0
  for part in parts {
    total += part.length()
  }
  let out = FixedArray::make(total, b'\x00')
  let mut pos = 0
  for part in parts {
    out.blit_from_bytes(pos, part, 0, part.length())
    pos += part.length()
  }
  Bytes::from_fixedarray(out)
}

///|
test "v2: single band-1 fragment becomes the pack verbatim" {
  let data = concat([
    pktline_encode("packfile\n"),
    band(b'\x01', b"PACK\x00\x00\x00\x02"),
    pktline_flush(),
  ])
  let result = parse_fetch_response_v2(data)
  inspect(result.pack, content="b\"PACK\\x00\\x00\\x00\\x02\"")
}

///|
test "v2: band-1 fragments are joined byte-exact across pkt-line boundaries" {
  let data = concat([
    pktline_encode("packfile\n"),
    band(b'\x01', b"PA"),
    band(b'\x01', b"CK\x00"),
    band(b'\x01', b""),
    band(b'\x01', b"\x00\x00\x02"),
    pktline_flush(),
  ])
  let result = parse_fetch_response_v2(data)
  inspect(result.pack, content="b\"PACK\\x00\\x00\\x00\\x02\"")
  inspect(result.pack.length(), content="8")
}

///|
test "v2: band-2 progress is dropped, band-1 is kept" {
  let data = concat([
    pktline_encode("packfile\n"),
    band(b'\x02', b"Counting objects: 1\r"),
    band(b'\x01', b"PACK"),
    band(b'\x02', b"done.\n"),
    pktline_flush(),
  ])
  let result = parse_fetch_response_v2(data)
  inspect(result.pack, content="b\"PACK\"")
}

///|
test "v2: no band-1 data yields an empty pack" {
  let data = concat([pktline_encode("packfile\n"), pktline_flush()])
  let result = parse_fetch_response_v2(data)
  inspect(result.pack.length(), content="0")
}

///|
test "v2: band-3 raises a protocol error with the message" {
  let data = concat([
    pktline_encode("packfile\n"),
    band(b'\x01', b"PACK"),
    band(b'\x03', b"upload-pack: not our ref\n"),
  ])
  guard (try? parse_fetch_response_v2(data))
    is Err(@bit.GitError::ProtocolError(msg)) else {
    fail("expected ProtocolError")
  }
  inspect(msg, content="upload-pack error: upload-pack: not our ref\n")
}

///|
test "v0: band-1 fragments are joined byte-exact" {
  let data = concat([
    band(b'\x01', b"PACK\x00"),
    band(b'\x01', b"\x00\x00\x02"),
    pktline_flush(),
  ])
  let result = parse_fetch_response_v0(data)
  inspect(result.pack, content="b\"PACK\\x00\\x00\\x00\\x02\"")
}

///|
test "v0: shallow lines are parsed alongside band-1 data" {
  let sha = "0123456789abcdef0123456789abcdef01234567"
  let data = concat([
    pktline_encode("shallow \{sha}\n"),
    band(b'\x01', b"PACK"),
    pktline_flush(),
  ])
  let result = parse_fetch_response_v0(data)
  inspect(result.pack, content="b\"PACK\"")
  inspect(result.shallow.length(), content="1")
}

///|
test "v0: band-3 raises a protocol error" {
  let data = concat([band(b'\x03', b"fatal: early EOF\n")])
  guard (try? parse_fetch_response_v0(data))
    is Err(@bit.GitError::ProtocolError(msg)) else {
    fail("expected ProtocolError")
  }
  inspect(msg, content="upload-pack error: fatal: early EOF\n")
}
