import Foundation
import Testing
@testable import vLensCore

@Test func helperBinaryNotFoundHasEndUserMessage() {
    let message = HelperClientError.helperBinaryNotFound.errorDescription
    #expect(message != nil)
    // Regression guard: this used to tell the user to run a Go build
    // command, which only makes sense to someone building from source, not
    // someone running the packaged .app.
    #expect(message?.contains("go build") == false)
}

@Test func emptyResponseHasEndUserMessage() {
    let message = HelperClientError.emptyResponse.errorDescription
    #expect(message != nil)
    #expect(message != "emptyResponse")
}

@Test func decodingFailedIncludesDetailButNotRawEnumDump() {
    let message = HelperClientError.decodingFailed("unexpected token").errorDescription
    #expect(message?.contains("unexpected token") == true)
    #expect(message?.hasPrefix("decodingFailed(") == false)
}

@Test func helperReportedErrorPassesMessageThroughVerbatim() {
    let message = HelperClientError.helperReportedError("Certificate for host isn't trusted yet.").errorDescription
    #expect(message == "Certificate for host isn't trusted yet.")
}

@Test func processFailedIncludesExitCodeAndStderr() {
    let message = HelperClientError.processFailed(exitCode: 1, stderr: "connection refused").errorDescription
    #expect(message?.contains("1") == true)
    #expect(message?.contains("connection refused") == true)
}
