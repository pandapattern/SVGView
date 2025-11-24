//
//  SVGTextParser.swift
//  SVGView
//
//  Created by Yuri Strot on 29.05.2022.
//

import SwiftUI

class SVGTextParser: SVGBaseElementParser {
    override func doParse(context: SVGNodeContext, delegate: (XMLElement) -> SVGNode?) -> SVGNode? {
        let fontName = context.style("font-family") ?? "Serif"
        let fontSize = context.value(.fontSize)
        let fontWeight = context.style("font-weight") ?? "normal"
        let font = SVGFont(name: fontName, size: fontSize, weight: fontWeight)
        let textAnchor = parseTextAnchor(context.style("text-anchor"))

        // Collect text content from direct text nodes and tspan elements
        var textContent = ""
        for content in context.element.contents {
            if let textNode = content as? XMLText {
                textContent += textNode.text
            } else if let tspanElement = content as? XMLElement, tspanElement.name == "tspan" {
                // Collect text from tspan elements
                for tspanContent in tspanElement.contents {
                    if let tspanText = tspanContent as? XMLText {
                        textContent += tspanText.text
                    }
                }
            }
        }
        
        guard !textContent.isEmpty else {
            return .none
        }
        
        // Keep original transform logic unchanged (transform attribute is handled by SVGBaseElementParser)
        let x = SVGHelper.parseCGFloat(context.properties, "x")
        let y = SVGHelper.parseCGFloat(context.properties, "y")
        let transform = CGAffineTransform(translationX: x, y: y)

        let trimmed = textContent.trimmingCharacters(in: .whitespacesAndNewlines).processingWhitespaces()
        return SVGText(text: trimmed, font: font, fill: SVGHelper.parseFill(context.styles, context.index), stroke: SVGHelper.parseStroke(context.styles, index: context.index), textAnchor: textAnchor, transform: transform)
    }

    private func parseTextAnchor(_ string: String?) -> HorizontalAlignment {
        if let anchor = string {
            if anchor == "middle" {
                return .center
            } else if anchor == "end" {
                return .trailing
            }
        }
        return .leading
    }

    static var whitespaceRegex = try! NSRegularExpression(pattern: "\\s+", options: NSRegularExpression.Options.caseInsensitive)

}

extension String {

    fileprivate func processingWhitespaces() -> String {
        let range = NSMakeRange(0, self.count)
        let modString = SVGTextParser.whitespaceRegex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: " ")
        return modString
    }
}
