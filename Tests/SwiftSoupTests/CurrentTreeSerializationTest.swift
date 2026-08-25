import XCTest
@testable import SwiftSoup

final class CurrentTreeSerializationTest: XCTestCase {
    private func parseHTML(_ html: String, prettyPrint: Bool = false) throws -> Document {
        let document = try SwiftSoup.parse(html)
        document.outputSettings().prettyPrint(pretty: prettyPrint)
        return document
    }

    private func string(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    func testCurrentTreeSerializationDoesNotReuseCleanSourceFormatting() throws {
        let document = try parseHTML(
            "<!doctype html><html><head><title data-kind='source'>Original</title></head>" +
            "<body><main id='reader'>Before</main></body></html>"
        )

        let sourceBacked = string(try document.outerHtmlUTF8())
        let currentTree = string(try document.outerHtmlUTF8FromCurrentTree())

        XCTAssertTrue(sourceBacked.contains("data-kind='source'"))
        XCTAssertTrue(currentTree.contains("data-kind=\"source\""))

        let title = try XCTUnwrap(document.getElementsByTag("title").first())
        try title.text("Updated")
        let main = try XCTUnwrap(document.getElementById("reader"))
        try main.attr("data-state", "complete")

        let reparsed = try SwiftSoup.parse(string(try document.outerHtmlUTF8FromCurrentTree()))
        XCTAssertEqual(try reparsed.title(), "Updated")
        XCTAssertEqual(try reparsed.getElementById("reader")?.attr("data-state"), "complete")
        XCTAssertEqual(try reparsed.getElementById("reader")?.text(), "Before")
    }

    func testCurrentBodyTreeSerializationPreservesSourceBackedShell() throws {
        let document = try parseHTML(
            "<!doctype html><html><!--before-head--><head data-shell='source'><title>Title</title></head>" +
            "<!--before-body--><body class='reader'><main id='reader'>Before</main></body>" +
            "<!--after-body--></html>"
        )
        let main = try XCTUnwrap(document.getElementById("reader"))
        try main.text("After")
        try main.attr("data-state", "complete")

        let serialized = string(try document.outerHtmlUTF8FromCurrentBodyTree())
        XCTAssertTrue(serialized.contains("<!--before-head-->"))
        XCTAssertTrue(serialized.contains("<!--before-body-->"))
        XCTAssertTrue(serialized.contains("<!--after-body-->"))

        let reparsed = try SwiftSoup.parse(serialized)
        XCTAssertEqual(try reparsed.head()?.attr("data-shell"), "source")
        XCTAssertEqual(try reparsed.getElementById("reader")?.text(), "After")
        XCTAssertEqual(try reparsed.getElementById("reader")?.attr("data-state"), "complete")
    }

    func testReplacingBodyContentsAcceptsPreSerializedBytes() throws {
        let document = try parseHTML(
            "<!doctype html><html><head><title>Title</title></head>" +
            "<body class='reader'><p>Discarded</p></body></html>"
        )
        let replacement = Array("<main id=\"replacement\">Replacement</main>".utf8)

        let serialized = string(
            try document.outerHtmlUTF8ReplacingBodyContents(with: replacement)
        )
        XCTAssertTrue(serialized.contains("<body class=\"reader\">"))
        XCTAssertTrue(serialized.contains(string(replacement)))
        XCTAssertFalse(serialized.contains("Discarded"))

        let reparsed = try SwiftSoup.parse(serialized)
        XCTAssertEqual(try reparsed.getElementById("replacement")?.text(), "Replacement")
    }

    func testCurrentBodyTreeMatchesWholeCurrentTreeWhenPrettyPrinting() throws {
        let html = "<!doctype html><html><head><title>Title</title></head>" +
            "<body><main><p>One</p><p>Two</p></main></body></html>"
        let document = try parseHTML(html, prettyPrint: true)
        try document.body()?.addClass("reader")

        XCTAssertEqual(
            try document.outerHtmlUTF8FromCurrentBodyTree(),
            try document.outerHtmlUTF8FromCurrentTree()
        )
    }

    func testCurrentBodyTreeFallsBackForNonHTMLDocument() throws {
        let parser = Parser.xmlParser()
        let document = try parser.parseInput("<root><body><item>Value</item></body></root>", "")
        document.outputSettings().prettyPrint(pretty: false)

        XCTAssertEqual(
            try document.outerHtmlUTF8FromCurrentBodyTree(),
            try document.outerHtmlUTF8FromCurrentTree()
        )
    }

    func testReplacingBodyContentsRejectsNonHTMLDocument() throws {
        let document = try Parser.xmlParser().parseInput("<root><item>Value</item></root>", "")

        XCTAssertThrowsError(
            try document.outerHtmlUTF8ReplacingBodyContents(with: Array("<item>Replacement</item>".utf8))
        )
    }

    func testCurrentBodyTreeFallsBackForAmbiguousBody() throws {
        let document = try parseHTML(
            "<!doctype html><html><head><title>Title</title></head><body><p>One</p></body></html>"
        )
        let html = try XCTUnwrap(document.getElementsByTag("html").first())
        try html.appendElement("body").appendElement("p").text("Two")

        XCTAssertEqual(
            try document.outerHtmlUTF8FromCurrentBodyTree(),
            try document.outerHtmlUTF8FromCurrentTree()
        )
    }
}
