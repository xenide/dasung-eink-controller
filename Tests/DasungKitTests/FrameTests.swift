import Foundation
import Testing

@testable import DasungKit

struct FrameTests {
  @Test func encodesCommandAsAsciiHex() {
    let frame = Frame.encode(.brightness, value: 20)
    #expect(String(decoding: frame, as: UTF8.self) == "5FF50914000000000000A0FA")
  }

  @Test func encodesQueryWithRegisterAsValue() {
    let frame = Frame.query(.modelVersion)
    #expect(String(decoding: frame, as: UTF8.self) == "5FF50A13000000000000A0FA")
  }

  @Test(arguments: [
    ("5FF5F00A020700000000A0FA", Reply.report(register: 0x02, value: 0x07)),
    ("5FF5F00A103111100000A0FA", Reply.report(register: 0x10, value: 0x31)),
    ("5FF5F009000000000000A0FA", Reply.acknowledged(0x09)),
    ("5FF50914000000000000A0FA", Reply.report(register: 0x09, value: 0x14)),
  ])
  func decodesReplyKinds(text: String, expected: Reply) {
    var decoder = FrameDecoder()
    #expect(decoder.feed(Array(text.utf8)) == [expected])
  }

  @Test func reassemblesFramesSplitAcrossReads() {
    var decoder = FrameDecoder()
    let bytes = Array("5FF5F00A010400000000A0FA5FF5F00A091400000000A0FA".utf8)
    var replies: [Reply] = []
    for chunk in stride(from: 0, to: bytes.count, by: 5) {
      replies += decoder.feed(bytes[chunk..<min(chunk + 5, bytes.count)])
    }
    #expect(replies == [.report(register: 0x01, value: 4), .report(register: 0x09, value: 20)])
  }

  @Test func skipsNoiseAndCorruptFrames() {
    var decoder = FrameDecoder()
    let text = "xx5FF5F00A01040000000000005FF5ZZ0A010400000000A0FA5FF5F00A020600000000A0FA"
    #expect(decoder.feed(Array(text.utf8)) == [.report(register: 0x02, value: 6)])
  }

  @Test func keepsPartialHeaderBetweenReads() {
    var decoder = FrameDecoder()
    #expect(decoder.feed(Array("garbage5FF".utf8)).isEmpty)
    #expect(decoder.feed(Array("5F00A010900000000A0FA".utf8)) == [.report(register: 1, value: 9)])
  }
}
