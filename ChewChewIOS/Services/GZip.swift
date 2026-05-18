import Compression
import Foundation

/// 외부 의존성 0인 gzip 인코더.
/// iOS `Compression` 프레임워크는 raw deflate를 직접 노출하지 않아 `COMPRESSION_ZLIB`
/// 결과의 zlib 헤더 2바이트 / Adler-32 4바이트를 잘라 raw deflate stream을 얻고,
/// 그 위에 gzip 헤더(10B) + CRC32 + ISIZE footer(8B)를 직접 덧붙인다.
enum GZip {
    static func compress(_ source: Data) -> Data? {
        // 빈 데이터: gzip(empty)는 사전 정의된 짧은 스트림으로 즉시 반환.
        if source.isEmpty {
            return Data([
                0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff,
                0x03, 0x00,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00
            ])
        }

        guard let zlib = encodeZlib(source), zlib.count >= 6 else {
            return nil
        }
        // zlib container = 2B header + deflate body + 4B Adler-32 → 본문만 추출.
        let deflateBody = zlib.subdata(in: 2..<(zlib.count - 4))

        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
        out.append(deflateBody)

        var crc = crc32(source).littleEndian
        var isize = UInt32(truncatingIfNeeded: source.count).littleEndian
        withUnsafeBytes(of: &crc)   { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
        return out
    }

    private static func encodeZlib(_ src: Data) -> Data? {
        src.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> Data? in
            guard let base = rawBuf.baseAddress else { return nil }
            let srcPtr = base.assumingMemoryBound(to: UInt8.self)
            // 최악의 경우 원본보다 살짝 클 수 있으므로 여유 마진.
            let capacity = max(src.count + src.count / 10 + 64, 4096)
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            let n = compression_encode_buffer(
                dst, capacity,
                srcPtr, src.count,
                nil, COMPRESSION_ZLIB
            )
            guard n > 0 else { return nil }
            return Data(bytes: dst, count: n)
        }
    }

    // CRC-32/ISO-HDLC (gzip 사용 변종). poly 0xEDB88320, init 0xFFFFFFFF, final XOR 0xFFFFFFFF.
    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}
