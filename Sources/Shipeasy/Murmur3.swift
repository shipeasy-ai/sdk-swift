import Foundation

public enum Murmur3 {
    private static let c1: UInt32 = 0xcc9e2d51
    private static let c2: UInt32 = 0x1b873593

    public static func hash32(_ key: String) -> UInt32 {
        let data = Array(key.utf8)
        let n = data.count
        var h1: UInt32 = 0
        let nblocks = n / 4

        for i in 0..<nblocks {
            let off = i * 4
            var k1 = UInt32(data[off])
                | (UInt32(data[off + 1]) << 8)
                | (UInt32(data[off + 2]) << 16)
                | (UInt32(data[off + 3]) << 24)
            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2
            h1 ^= k1
            h1 = (h1 << 13) | (h1 >> 19)
            h1 = h1 &* 5 &+ 0xe6546b64
        }

        let tail = nblocks * 4
        var k1: UInt32 = 0
        let rem = n & 3
        if rem >= 3 { k1 ^= UInt32(data[tail + 2]) << 16 }
        if rem >= 2 { k1 ^= UInt32(data[tail + 1]) << 8 }
        if rem >= 1 {
            k1 ^= UInt32(data[tail])
            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2
            h1 ^= k1
        }

        h1 ^= UInt32(n)
        h1 ^= h1 >> 16
        h1 = h1 &* 0x85ebca6b
        h1 ^= h1 >> 13
        h1 = h1 &* 0xc2b2ae35
        h1 ^= h1 >> 16
        return h1
    }

    public static func bucket(_ key: String, mod: UInt32) -> UInt32 {
        return hash32(key) % mod
    }
}
