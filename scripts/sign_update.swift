// sign_update.swift — Sparkle 更新包 Ed25519 签名（替代 Sparkle 官方 bin/sign_update）。
// 用法: swift scripts/sign_update.swift <base64-私钥> <文件路径> [--expect-public-key <base64|路径>]
//   私钥格式: base64(32 字节 Ed25519 种子) 或 base64(64 字节 seed||pub，libsodium 格式)
//   --expect-public-key: 可选。给出后从私钥派生公钥并与之比对，不匹配立即 exit(1)。
//     参数既可以是 base64 字符串，也可以是含 base64 的文件路径
//     （如 scripts/sparkle-ed-public-key.txt）。
// 输出: sparkle:edSignature="..." length="..."（与官方 sign_update 相同）
// 说明: CryptoKit 的 Curve25519.Signing 是标准 RFC 8032 Ed25519，与 Sparkle
//   （libsodium）签名互通；公钥即 scripts/sparkle-ed-public-key.txt 的内容。
import Foundation
import CryptoKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 || args.count == 5 else {
    FileHandle.standardError.write(
        "usage: swift scripts/sign_update.swift <base64-private-key> <file> [--expect-public-key <base64|path>]\n"
            .data(using: .utf8)!)
    exit(1)
}

let expectedPublicKeyArg: String? = {
    guard args.count == 5 else { return nil }
    guard args[3] == "--expect-public-key" else {
        fail("未知参数 \(args[3])（期望 --expect-public-key）")
    }
    return args[4]
}()

guard let keyData = Data(base64Encoded: args[1]) else {
    fail("私钥不是合法 base64")
}
let seed = keyData.count == 64 ? keyData.prefix(32) : keyData
guard seed.count == 32, let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    fail("私钥长度无效（期望 32 或 64 字节）")
}

// 可选：校验私钥派生出的公钥与期望公钥一致——CI 里用来提前发现 secret 配错。
if let expectedArg = expectedPublicKeyArg {
    let rawExpected: String
    if FileManager.default.fileExists(atPath: expectedArg) {
        guard let contents = try? String(contentsOfFile: expectedArg, encoding: .utf8) else {
            fail("无法读取 --expect-public-key 文件: \(expectedArg)")
        }
        rawExpected = contents
    } else {
        rawExpected = expectedArg
    }
    let trimmed = rawExpected.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let expected = Data(base64Encoded: trimmed) else {
        fail("--expect-public-key 不是合法 base64（也不是可读文件）: \(expectedArg)")
    }
    let actual = priv.publicKey.rawRepresentation
    guard actual == expected else {
        fail("Sparkle 签名私钥与仓库内期望公钥不匹配：expected=\(expected.base64EncodedString()) "
            + "got=\(actual.base64EncodedString())")
    }
    FileHandle.standardError.write("public key verified: \(actual.base64EncodedString())\n".data(using: .utf8)!)
}

do {
    let fileURL = URL(fileURLWithPath: args[2])
    let data = try Data(contentsOf: fileURL)
    let signature = try priv.signature(for: data)
    print("sparkle:edSignature=\"\(signature.base64EncodedString())\" length=\"\(data.count)\"")
} catch {
    fail(error.localizedDescription)
}
