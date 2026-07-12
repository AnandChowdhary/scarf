//
//  Scarf_iOSUITests.swift
//  Scarf iOSUITests
//
//  Created by Alan Wizemann on 4/23/26.
//

import XCTest

final class Scarf_iOSUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLiveVoiceRoundTripFromSyntheticSpeech() throws {
        let environment = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchEnvironment["CLAWDIA_VOICE_E2E_PHRASE"] = environment["CLAWDIA_VOICE_E2E_PHRASE"]
            ?? "Reply with exactly: CLAWDIA VOICE E2E OK."
        app.launchEnvironment["CLAWDIA_VOICE_E2E_SILENT_FOLLOWUP"] = "1"
        app.launch()
        addTeardownBlock { app.terminate() }

        let serversTitle = app.navigationBars["Servers"]
        if serversTitle.waitForExistence(timeout: 5) {
            let configuredServer = app.buttons.matching(
                NSPredicate(format: "label CONTAINS '@'")
            ).firstMatch
            XCTAssertTrue(
                configuredServer.waitForExistence(timeout: 3),
                "The live voice gate requires a server already configured in this simulator."
            )
            configuredServer.tap()
        }

        XCTAssertTrue(
            app.navigationBars["Chat"].waitForExistence(timeout: 20),
            "Clawdia did not reach Chat using the simulator's configured server."
        )

        let composerMode = app.segmentedControls["clawdia.composer.mode"]
        XCTAssertTrue(composerMode.waitForExistence(timeout: 20))
        composerMode.buttons["Voice"].tap()

        let microphone = app.buttons["clawdia.voice.microphone"]
        XCTAssertTrue(
            microphone.waitForExistence(timeout: 5),
            "Voice mode is not ready. Confirm this simulator has an OpenAI key saved in Clawdia."
        )
        let voiceReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: microphone
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [voiceReady], timeout: 30),
            .completed,
            "Chat did not become ready to start the voice conversation."
        )
        let status = app.staticTexts["clawdia.voice.status"]
        let voiceError = app.staticTexts["clawdia.voice.error"]
        startVoiceConversation(
            microphone: microphone,
            status: status,
            errorElement: voiceError
        )
        assertStatus("Listening…", element: status, errorElement: voiceError, timeout: 15)
        keepScreenshot(named: "Clawdia waveform — listening", from: app, after: 0.8)
        assertStatus("Clawdia is responding…", element: status, errorElement: voiceError, timeout: 45)
        assertStatus("Clawdia is speaking…", element: status, errorElement: voiceError, timeout: 120)
        keepScreenshot(named: "Clawdia waveform — speaking", from: app, after: 3.0)

        let expectedResponse = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "VOICE E2E OK")
        ).firstMatch
        XCTAssertTrue(
            expectedResponse.waitForExistence(timeout: 30),
            "Hermes did not produce the requested deterministic voice-test response."
        )

        // Voice should automatically reopen listening after speech playback.
        assertStatus("Listening…", element: status, errorElement: voiceError, timeout: 30)
        app.buttons["clawdia.voice.conversation.end"].tap()

        keepScreenshot(named: "Clawdia voice E2E passed", from: app)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func startVoiceConversation(
        microphone: XCUIElement,
        status: XCUIElement,
        errorElement: XCUIElement
    ) {
        let idleTitle = "Tap the microphone to start"
        for _ in 0..<2 {
            microphone.tap()
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if status.exists, status.label != idleTitle { return }
                if errorElement.exists {
                    XCTFail("Voice pipeline failed while starting: \(errorElement.label)")
                    return
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTFail("The microphone remained idle after two UI taps.")
    }

    @MainActor
    private func assertStatus(
        _ expected: String,
        element: XCUIElement,
        errorElement: XCUIElement,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label == expected { return }
            if errorElement.exists {
                XCTFail("Voice pipeline failed before '\(expected)': \(errorElement.label)")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail(
            "Expected voice status '\(expected)' within \(Int(timeout)) seconds; current label is '\(element.label)'."
        )
    }

    private func keepScreenshot(
        named name: String,
        from app: XCUIApplication,
        after delay: TimeInterval = 0
    ) {
        if delay > 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(delay))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
