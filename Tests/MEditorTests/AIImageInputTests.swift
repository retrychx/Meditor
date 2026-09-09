import AppKit
import XCTest
@testable import MEditor

// MARK: - AI 聊天视觉输入：图片处理 / 附件上限 / 消息序列化

final class AIImageInputTests: XCTestCase {

    // MARK: - Helpers

    /// 构造纯色位图 CGImage
    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        // 填充非纯黑内容（纯黑 JPEG 体积太小，测不出缩放/压缩行为）
        let pixels = rep.bitmapData!
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            pixels[i]     = UInt8((i / 4) % 256)        // R 渐变
            pixels[i + 1] = UInt8((i / 4 / width) % 256) // G 按行渐变
            pixels[i + 2] = 128
            pixels[i + 3] = 255
        }
        return rep.cgImage!
    }

    /// 构造随机噪声位图（高频细节，JPEG 最难压缩的场景）
    private func makeNoiseCGImage(width: Int, height: Int) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let pixels = rep.bitmapData!
        var rng = SystemRandomNumberGenerator()
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let v = UInt8.random(in: 0...255, using: &rng)
            pixels[i] = v
            pixels[i + 1] = UInt8.random(in: 0...255, using: &rng)
            pixels[i + 2] = UInt8.random(in: 0...255, using: &rng)
            pixels[i + 3] = 255
        }
        return rep.cgImage!
    }

    /// 构造一个假附件（序列化测试不依赖真实图片编码）
    private func fakeAttachment() -> AIImageAttachment {
        AIImageAttachment(
            mimeType: "image/jpeg",
            data: Data([0xFF, 0xD8, 0xFF, 0xD9]),   // 最小 JPEG SOI/EOI
            width: 2, height: 2
        )
    }

    // MARK: - 图片处理：缩放

    func test_process_largeImage_resizesLongEdgeToLimit() throws {
        let cg = makeCGImage(width: 3136, height: 2000)
        let attachment = try XCTUnwrap(AIImageProcessor.makeAttachment(from: cg))
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertEqual(attachment.width, Int(AIImageProcessor.maxLongEdge))
        // 等比缩小：短边按比例
        let expectedHeight = Int((2000.0 * AIImageProcessor.maxLongEdge / 3136.0).rounded())
        XCTAssertEqual(attachment.height, expectedHeight)
        XCTAssertLessThanOrEqual(attachment.data.count, AIImageProcessor.maxBytes)
    }

    func test_process_smallImage_keepsSize() throws {
        let cg = makeCGImage(width: 100, height: 60)
        let attachment = try XCTUnwrap(AIImageProcessor.makeAttachment(from: cg))
        XCTAssertEqual(attachment.width, 100)
        XCTAssertEqual(attachment.height, 60)
        XCTAssertLessThanOrEqual(attachment.data.count, AIImageProcessor.maxBytes)
    }

    // MARK: - 图片处理：压缩到 1MB 内（噪声大图走质量自适应阶梯）

    func test_process_noisyImage_compressedUnderLimit() throws {
        let cg = makeNoiseCGImage(width: 3136, height: 3136)
        let attachment = try XCTUnwrap(AIImageProcessor.makeAttachment(from: cg))
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        XCTAssertLessThanOrEqual(attachment.data.count, AIImageProcessor.maxBytes)
    }

    // MARK: - 图片处理：PNG → JPEG 格式转换

    func test_process_pngImage_convertsToJPEG() throws {
        let cg = makeCGImage(width: 200, height: 120)
        let rep = NSBitmapImageRep(cgImage: cg)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let nsImage = try XCTUnwrap(NSImage(data: png))

        let attachment = try XCTUnwrap(AIImageProcessor.makeAttachment(from: nsImage))
        XCTAssertEqual(attachment.mimeType, "image/jpeg")
        // 输出确实是 JPEG（magic bytes SOI = 0xFFD8）且可解码
        XCTAssertEqual(attachment.data.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertNotNil(NSImage(data: attachment.data))
    }

    // MARK: - 附件上限（第 5 张被拒）

    func test_appendAttachments_underLimit_allAccepted() {
        let result = AIImageProcessor.appending([fakeAttachment(), fakeAttachment()], to: [])
        XCTAssertEqual(result.merged.count, 2)
        XCTAssertEqual(result.rejected, 0)
    }

    func test_appendAttachments_fifthRejected() {
        let existing = (0..<AIImageProcessor.maxAttachmentsPerMessage).map { _ in fakeAttachment() }
        let result = AIImageProcessor.appending([fakeAttachment()], to: existing)
        XCTAssertEqual(result.merged.count, AIImageProcessor.maxAttachmentsPerMessage)
        XCTAssertEqual(result.rejected, 1)
    }

    func test_appendAttachments_partialOverflow_keepsRoom() {
        let existing = [fakeAttachment(), fakeAttachment(), fakeAttachment()]
        let result = AIImageProcessor.appending([fakeAttachment(), fakeAttachment()], to: existing)
        XCTAssertEqual(result.merged.count, AIImageProcessor.maxAttachmentsPerMessage)
        XCTAssertEqual(result.rejected, 1)
    }

    // MARK: - OpenAI 消息序列化

    func test_openAIDict_withoutImages_keepsPlainStringContent() {
        let msg = AgentMessage(role: .user, content: "hello")
        let dict = msg.openAIDict
        // 回归：无图片的消息 content 必须是纯字符串（兼容文本模型），不是 content parts
        XCTAssertEqual(dict["content"] as? String, "hello")
        XCTAssertEqual(dict["role"] as? String, "user")
    }

    func test_openAIDict_withImages_buildsContentParts() {
        let msg = AgentMessage(role: .user, content: "转 markdown", images: [fakeAttachment()])
        let dict = msg.openAIDict
        let parts = dict["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)
        XCTAssertEqual(parts?[0]["type"] as? String, "text")
        XCTAssertEqual(parts?[0]["text"] as? String, "转 markdown")
        XCTAssertEqual(parts?[1]["type"] as? String, "image_url")
        let imageURL = (parts?[1]["image_url"] as? [String: Any])?["url"] as? String
        XCTAssertTrue(imageURL?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    func test_openAIDict_imageOnlyMessage_skipsTextPart() {
        let msg = AgentMessage(role: .user, content: "", images: [fakeAttachment()])
        let parts = msg.openAIDict["content"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 1)
        XCTAssertEqual(parts?[0]["type"] as? String, "image_url")
    }

    // MARK: - 请求级序列化（MockURLSession 抓包）

    private func makeConfig(wire baseURL: String = "https://api.openai.com/v1") -> AIConfig {
        AIConfig(
            kind: .openai, baseURL: baseURL, model: "gpt-4o",
            cliPath: "", cliModel: "", apiKey: "test-key", requestTimeoutSeconds: 60
        )
    }

    private func stubOK(_ mock: MockURLSession) {
        mock.stubbedData = try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "ok", "role": "assistant"], "finish_reason": "stop"]]
        ])
    }

    func test_request_openAI_withoutImages_contentStaysString() async throws {
        let mock = MockURLSession()
        stubOK(mock)
        let backend = RestAgentBackend(config: makeConfig(), wire: .openAI, session: mock)
        _ = try await backend.complete(messages: [AgentMessage(role: .user, content: "hi")], tools: [])

        let body = mock.capturedRequests.first?.httpBody
        let json = try XCTUnwrap(body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        // 回归：纯文本消息的 content 仍是字符串，不被升级成 content parts
        XCTAssertEqual(messages.first?["content"] as? String, "hi")
    }

    func test_request_openAI_withImages_contentPartsOnWire() async throws {
        let mock = MockURLSession()
        stubOK(mock)
        let backend = RestAgentBackend(config: makeConfig(), wire: .openAI, session: mock)
        _ = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "看图", images: [fakeAttachment()])
        ], tools: [])

        let body = mock.capturedRequests.first?.httpBody
        let json = try XCTUnwrap(body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(parts[1]["type"] as? String, "image_url")
    }

    func test_request_anthropic_withImages_buildsImageBlocks() async throws {
        let mock = MockURLSession()
        mock.stubbedData = try! JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "ok"]],
            "stop_reason": "end_turn"
        ])
        let backend = RestAgentBackend(
            config: makeConfig(wire: "https://api.anthropic.com/v1"),
            wire: .anthropic, session: mock
        )
        _ = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "看图", images: [fakeAttachment()])
        ], tools: [])

        let body = mock.capturedRequests.first?.httpBody
        let json = try XCTUnwrap(body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        // 图片块在前（官方推荐顺序），文本块在后
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        let source = try XCTUnwrap(blocks[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(blocks[1]["type"] as? String, "text")
        XCTAssertEqual(blocks[1]["text"] as? String, "看图")
    }

    // MARK: - 持久化：图片不进磁盘历史

    func test_chatMessage_persistence_dropsImageData_keepsCount() throws {
        let message = AIChatMessage(
            role: .user, text: "看图说话",
            images: [fakeAttachment(), fakeAttachment()]
        )
        let data = try JSONEncoder().encode(message)
        // base64 数据不进 JSON（省体积）
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["images"])
        XCTAssertEqual(json["imageCount"] as? Int, 2)

        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: data)
        XCTAssertEqual(decoded.text, "看图说话")
        XCTAssertEqual(decoded.imageCount, 2)   // 重启后按数量渲染占位
        XCTAssertTrue(decoded.images.isEmpty)   // 图片数据已丢弃
    }

    func test_chatMessage_decodesLegacyJSON_withoutImageCount() throws {
        let legacy = #"{"id":"\#(UUID().uuidString)","role":"user","text":"hi"}"#
        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.text, "hi")
        XCTAssertEqual(decoded.imageCount, 0)
        XCTAssertTrue(decoded.images.isEmpty)
    }

    func test_agentMessage_persistence_excludesImages() throws {
        let msg = AgentMessage(role: .user, content: "看图", images: [fakeAttachment()])
        let data = try JSONEncoder().encode(msg)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["images"])
        XCTAssertEqual(json["content"] as? String, "看图")

        let decoded = try JSONDecoder().decode(AgentMessage.self, from: data)
        XCTAssertNil(decoded.images)
        XCTAssertEqual(decoded.content, "看图")
    }
}
