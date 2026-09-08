import XCTest
@testable import SwiftSoup

final class MutationAndOutputPolicyTests: XCTestCase {
    func testExposedValuesInvalidateSelectorsAndSerializedSource() throws {
        for useIterator in [false, true] {
            let doc = try SwiftSoup.parse("<p id='old' class='before' data-x='one'>text</p>")
            doc.outputSettings().prettyPrint(pretty: false)
            let element = try XCTUnwrap(doc.select("p").first())
            for query in ["#old", ".before", "[data-x=one]"] {
                XCTAssertEqual(try doc.select(query).size(), 1)
            }
            let attributes = try XCTUnwrap(element.getAttributes())
            let exposed = useIterator ? Array(attributes) : attributes.asList()
            let replacements = ["id": "new", "class": "after", "data-x": "two"]
            for attribute in exposed {
                if let value = replacements[attribute.getKey()] {
                    attribute.setValue(value: Array(value.utf8))
                }
            }
            for query in ["#old", ".before", "[data-x=one]"] {
                XCTAssertEqual(try doc.select(query).size(), 0)
            }
            for query in ["#new", ".after", "[data-x=two]"] {
                XCTAssertEqual(try doc.select(query).size(), 1)
            }
            let serialized = try SwiftSoup.parse(doc.outerHtml())
            XCTAssertEqual(try serialized.select("p").attr("id"), "new")
            XCTAssertEqual(try serialized.select("p").attr("class"), "after")
            XCTAssertEqual(try serialized.select("p").attr("data-x"), "two")
        }
    }

    func testSharedAttributeNotifiesEveryCollectionAndSurvivesRemoval() throws {
        let left = try SwiftSoup.parse("<p></p>")
        let right = try SwiftSoup.parse("<p></p>")
        let leftAttributes = try XCTUnwrap(left.select("p").first()?.getAttributes())
        let rightAttributes = try XCTUnwrap(right.select("p").first()?.getAttributes())
        let shared = try Attribute(key: "id", value: "old")
        leftAttributes.put(attribute: shared)
        rightAttributes.addAll(incoming: leftAttributes)
        for doc in [left, right] { XCTAssertEqual(try doc.select("#old").size(), 1) }
        shared.setValue(value: Array("new".utf8))
        for doc in [left, right] {
            XCTAssertEqual(try doc.select("#old").size(), 0)
            XCTAssertEqual(try doc.select("#new").size(), 1)
        }
        try leftAttributes.remove(key: "id")
        shared.setValue(value: Array("last".utf8))
        XCTAssertEqual(try left.select("#last").size(), 0)
        XCTAssertEqual(try right.select("#last").size(), 1)
    }

    func testCopiedAttributesNotifyOriginalAndClone() throws {
        let original = try SwiftSoup.parse("<p data-x='one'>text</p>")
        let cloned = original.copy() as! Document
        for doc in [original, cloned] { XCTAssertEqual(try doc.select("[data-x=one]").size(), 1) }
        let attribute = try XCTUnwrap(original.select("p").first()?.getAttributes()?.asList().first)
        attribute.setValue(value: Array("two".utf8))
        for doc in [original, cloned] {
            XCTAssertEqual(try doc.select("[data-x=one]").size(), 0)
            XCTAssertEqual(try doc.select("[data-x=two]").size(), 1)
        }
    }

    func testNondefaultOutputPolicySerializesDocumentsNodesAndSparseEdits() throws {
        for charset in [String.Encoding.ascii, .utf8] {
            for mode in [Entities.EscapeMode.base, .extended, .xhtml] {
                if charset == .utf8 && mode == .base { continue }
                let doc = try SwiftSoup.parse("<p title='日本語'>日本語 © &nbsp;</p><b>元</b>")
                doc.outputSettings().prettyPrint(pretty: false).charset(charset).escapeMode(mode)
                for mutate in [false, true] {
                    if mutate { try doc.select("b").first()?.text("変更") }
                    let expected = try doc.outerHtmlUTF8WithoutSourceReuse()
                    XCTAssertEqual(try doc.outerHtmlUTF8(), expected)
                    XCTAssertEqual(try doc.outerHtml(), String(decoding: expected, as: UTF8.self))
                    let node = try XCTUnwrap(doc.select("p").first())
                    XCTAssertEqual(try node.outerHtmlUTF8Internal(), try node.outerHtmlUTF8Internal(doc.outputSettings(), allowRawSource: false))
                    if charset == .ascii { XCTAssertTrue(expected.allSatisfy { $0 < 128 }) }
                }
            }
        }
    }
}
