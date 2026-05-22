import Foundation

public enum ULID {
    private static let encoding: [UInt8] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)
    private nonisolated(unsafe) static var lastTimestampMs: UInt64 = 0
    private nonisolated(unsafe) static var lastRandom: [UInt8] = Array(repeating: 0, count: 10)
    private static let lock = NSLock()

    public static func generate(now: Date = Date()) -> String {
        let ts = UInt64(now.timeIntervalSince1970 * 1000.0)

        var timeBytes = [UInt8](repeating: 0, count: 6)
        timeBytes[0] = UInt8((ts >> 40) & 0xff)
        timeBytes[1] = UInt8((ts >> 32) & 0xff)
        timeBytes[2] = UInt8((ts >> 24) & 0xff)
        timeBytes[3] = UInt8((ts >> 16) & 0xff)
        timeBytes[4] = UInt8((ts >> 8) & 0xff)
        timeBytes[5] = UInt8(ts & 0xff)

        let randomBytes: [UInt8] = lock.withLock {
            if ts > lastTimestampMs {
                lastTimestampMs = ts
                var bytes = [UInt8](repeating: 0, count: 10)
                for i in 0..<10 {
                    bytes[i] = UInt8.random(in: UInt8.min...UInt8.max)
                }
                lastRandom = bytes
                return bytes
            }

            var bytes = lastRandom
            var i = 9
            while i >= 0 {
                if bytes[i] == 0xff {
                    bytes[i] = 0x00
                    i -= 1
                    continue
                }
                bytes[i] &+= 1
                break
            }
            lastRandom = bytes
            return bytes
        }

        var data = [UInt8]()
        data.reserveCapacity(16)
        data.append(contentsOf: timeBytes)
        data.append(contentsOf: randomBytes)
        return encodeBase32(data)
    }

    private static func encodeBase32(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(26)

        var buffer: UInt32 = 0
        var bitsLeft: Int = 0
        for b in bytes {
            buffer = (buffer << 8) | UInt32(b)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = Int((buffer >> UInt32(bitsLeft - 5)) & 0x1f)
                out.append(encoding[index])
                bitsLeft -= 5
            }
        }

        if bitsLeft > 0 {
            let index = Int((buffer << UInt32(5 - bitsLeft)) & 0x1f)
            out.append(encoding[index])
        }

        if out.count < 26 {
            out.append(contentsOf: Array(repeating: encoding[0], count: 26 - out.count))
        } else if out.count > 26 {
            out = Array(out.prefix(26))
        }

        return String(decoding: out, as: UTF8.self)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
