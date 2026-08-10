// sign_update.swift — Sparkle 更新包 Ed25519 签名（替代 Sparkle 官方 bin/sign_update）。
// 用法: swift scripts/sign_update.swift <base64-私钥> <文件路径>
//   私钥格式: base64(32 字节 Ed25519 种子) 或 base64(64 字节 seed||pub，libsodium 格式)
// 输出: sparkle:edSignature="..." length="..."（与官方 sign_update 相同）
// 说明: CryptoKit 的 Curve25519.Signing 是标准 RFC 8032 Ed25519，与 Sparkle
//   （libsodium）签名互通；公钥即 scripts/sparkle-ed-public-key.txt 的内容。
import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: swift scripts/sign_update.swift <base64-private-key> <file>\n".data(using: .utf8)!)
    exit(1)
}
guard let keyData = Data(base64Encoded: args[1]) else {
    FileHandle.standardError.write("error: 私钥不是合法 base64\n".data(using: .utf8)!)
    exit(1)
}
let seed = keyData.count == 64 ? keyData.prefix(32) : keyData
guard seed.count == 32, let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    FileHandle.standardError.write("error: 私钥长度无效（期望 32 或 64 字节）\n".data(using: .utf8)!)
    exit(1)
}
do {
    let fileURL = URL(fileURLWithPath: args[2])
    let data = try Data(contentsOf: fileURL)
    let signature = try priv.signature(for: data)
    print("sparkle:edSignature=\"\(signature.base64EncodedString())\" length=\"\(data.count)\"")
} catch {
    FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
