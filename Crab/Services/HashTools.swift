import Foundation
import CryptoKit

enum HashTools {
    static func digests(of url: URL) throws -> [String: String] {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw NSError(domain: "Crab.Hash", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择普通文件计算校验值；文件夹与符号链接不参与计算。"])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        var sha512 = SHA512()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            md5.update(data: chunk)
            sha1.update(data: chunk)
            sha256.update(data: chunk)
            sha512.update(data: chunk)
        }
        func hex<D: Digest>(_ value: D) -> String { value.map { String(format: "%02x", $0) }.joined() }
        return ["MD5": hex(md5.finalize()), "SHA1": hex(sha1.finalize()),
                "SHA256": hex(sha256.finalize()), "SHA512": hex(sha512.finalize())]
    }
}
