import Foundation
import Testing
@testable import scarf

@Suite("OpenAI Realtime Voice")
struct OpenAIRealtimeVoiceTests {
    @Test func transcriptionSessionUsesGARealtimeShape() throws {
        let json = try object(OpenAIRealtimeProtocol.transcriptionSessionUpdate())
        #expect(json["type"] as? String == "session.update")
        let session = try #require(json["session"] as? [String: Any])
        #expect(session["type"] as? String == "realtime")
        #expect(session["model"] as? String == "gpt-realtime")
        #expect(session["output_modalities"] as? [String] == ["text"])
        let audio = try #require(session["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        #expect(input["turn_detection"] is NSNull)
        let transcription = try #require(input["transcription"] as? [String: Any])
        #expect(transcription["model"] as? String == "gpt-realtime-whisper")
        #expect(transcription["delay"] as? String == "low")
        let format = try #require(input["format"] as? [String: Any])
        #expect(format["type"] as? String == "audio/pcm")
        #expect(format["rate"] as? Int == 24_000)
    }

    @Test func speechSessionUsesAudioOnlyWithMarinVoice() throws {
        let json = try object(OpenAIRealtimeProtocol.speechSessionUpdate())
        let session = try #require(json["session"] as? [String: Any])
        #expect(session["output_modalities"] as? [String] == ["audio"])
        let audio = try #require(session["audio"] as? [String: Any])
        let output = try #require(audio["output"] as? [String: Any])
        #expect(output["voice"] as? String == "marin")
        let format = try #require(output["format"] as? [String: Any])
        #expect(format["type"] as? String == "audio/pcm")
        #expect(format["rate"] as? Int == 24_000)
    }

    @Test func audioAppendBase64EncodesRawPCM() throws {
        let pcm = Data([0x01, 0x02, 0xFE, 0xFF])
        let json = try object(OpenAIRealtimeProtocol.appendAudio(pcm))
        #expect(json["type"] as? String == "input_audio_buffer.append")
        #expect(json["audio"] as? String == pcm.base64EncodedString())
    }

    @Test func serverEventDecodesTranscriptDeltaAndErrors() throws {
        let delta = try OpenAIRealtimeProtocol.decode(
            #"{"type":"response.output_text.delta","delta":"hello"}"#
        )
        #expect(delta.type == "response.output_text.delta")
        #expect(delta.delta == "hello")

        let error = try OpenAIRealtimeProtocol.decode(
            #"{"type":"error","error":{"message":"bad key"}}"#
        )
        #expect(error.error?.message == "bad key")
    }

    @Test func wavExtractorFindsPCMBehindOddSizedMetadataChunk() throws {
        let pcm = Data([0x01, 0x00, 0xFF, 0x7F])
        var wav = Data("RIFF".utf8)
        appendLittleEndian(UInt32(4 + 8 + 3 + 1 + 8 + pcm.count), to: &wav)
        wav.append(Data("WAVE".utf8))
        wav.append(Data("JUNK".utf8))
        appendLittleEndian(3, to: &wav)
        wav.append(Data([1, 2, 3, 0]))
        wav.append(Data("data".utf8))
        appendLittleEndian(UInt32(pcm.count), to: &wav)
        wav.append(pcm)

        #expect(try WAVPCM16.extract(from: wav) == pcm)
    }

    @Test func wavExtractorRejectsNonWaveData() {
        #expect(throws: OpenAIRealtimeVoiceError.self) {
            try WAVPCM16.extract(from: Data("not audio".utf8))
        }
    }

    private func object(_ string: String) throws -> [String: Any] {
        let data = try #require(string.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
