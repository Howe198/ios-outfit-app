import Foundation

/// 极简 ZIP 读写：只用 store（不压缩）方式，避免引入任何第三方库或付费能力。
/// 导出的备份能被 macOS「归档工具」和 iOS「文件」App 正常解压。
enum StoreZip {

    struct Entry {
        let name: String
        let data: Data
    }

    enum ZipError: LocalizedError {
        case notZip
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notZip:
                return "不是有效的 zip 文件"
            case .corrupt(let message):
                return "备份文件损坏：\(message)"
            }
        }
    }

    // MARK: - 写

    static func make(entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let checksum = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(output.count)

            // Local file header
            output.appendUInt32(0x0403_4B50)
            output.appendUInt16(20)            // version needed
            output.appendUInt16(0x0800)        // UTF-8 文件名
            output.appendUInt16(0)             // method: store
            output.appendUInt16(0)             // mod time
            output.appendUInt16(0x0021)        // mod date: 1980-01-01
            output.appendUInt32(checksum)
            output.appendUInt32(size)
            output.appendUInt32(size)
            output.appendUInt16(UInt16(nameBytes.count))
            output.appendUInt16(0)             // extra length
            output.append(contentsOf: nameBytes)
            output.append(entry.data)

            // Central directory header
            central.appendUInt32(0x0201_4B50)
            central.appendUInt16(20)           // version made by
            central.appendUInt16(20)           // version needed
            central.appendUInt16(0x0800)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0x0021)
            central.appendUInt32(checksum)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameBytes.count))
            central.appendUInt16(0)            // extra
            central.appendUInt16(0)            // comment
            central.appendUInt16(0)            // disk number
            central.appendUInt16(0)            // internal attributes
            central.appendUInt32(0)            // external attributes
            central.appendUInt32(offset)
            central.append(contentsOf: nameBytes)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)

        // End of central directory
        output.appendUInt32(0x0605_4B50)
        output.appendUInt16(0)                 // disk number
        output.appendUInt16(0)                 // disk with central directory
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(central.count))
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)                 // comment length

        return output
    }

    // MARK: - 读

    static func read(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard bytes.count > 22 else { throw ZipError.notZip }

        var eocd = -1
        var index = bytes.count - 22
        let lowerBound = max(0, bytes.count - 22 - 65_535)
        while index >= lowerBound {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4B, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }

        let total = Int(readUInt16(bytes, eocd + 10))
        let centralSize = Int(readUInt32(bytes, eocd + 12))
        let centralOffset = Int(readUInt32(bytes, eocd + 16))
        guard centralOffset >= 0, centralSize >= 0, centralOffset + centralSize <= bytes.count else {
            throw ZipError.corrupt("目录位置越界")
        }

        var entries: [Entry] = []
        var offset = centralOffset

        for _ in 0..<total {
            guard offset + 46 <= bytes.count else { throw ZipError.corrupt("目录项不完整") }
            guard readUInt32(bytes, offset) == 0x0201_4B50 else { throw ZipError.corrupt("目录项签名错误") }

            let method = readUInt16(bytes, offset + 10)
            let checksum = readUInt32(bytes, offset + 16)
            let compressedSize = Int(readUInt32(bytes, offset + 20))
            let nameLength = Int(readUInt16(bytes, offset + 28))
            let extraLength = Int(readUInt16(bytes, offset + 30))
            let commentLength = Int(readUInt16(bytes, offset + 32))
            let localOffset = Int(readUInt32(bytes, offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { throw ZipError.corrupt("文件名越界") }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)

            guard method == 0 else { throw ZipError.corrupt("仅支持未压缩条目：\(name)") }
            guard localOffset + 30 <= bytes.count else { throw ZipError.corrupt("本地头越界：\(name)") }
            guard readUInt32(bytes, localOffset) == 0x0403_4B50 else { throw ZipError.corrupt("本地头签名错误：\(name)") }

            let localNameLength = Int(readUInt16(bytes, localOffset + 26))
            let localExtraLength = Int(readUInt16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= bytes.count else { throw ZipError.corrupt("数据越界：\(name)") }

            let payload = Data(bytes[dataStart..<(dataStart + compressedSize)])
            guard CRC32.checksum(payload) == checksum else { throw ZipError.corrupt("校验失败：\(name)") }

            entries.append(Entry(name: name, data: payload))
            offset = nameStart + nameLength + extraLength + commentLength
        }

        return entries
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var crc = UInt32(index)
            for _ in 0..<8 {
                if (crc & 1) == 1 {
                    crc = 0xEDB8_8320 ^ (crc >> 1)
                } else {
                    crc = crc >> 1
                }
            }
            table[index] = crc
        }
        return table
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
