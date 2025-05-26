//
//  SVGImageView.swift
//  edgellmtest
//
//  Created by Sidhant Srikumar on 5/25/25.
//

import Foundation
import UIKit
import SwiftUI
import SVGKit

struct SVGImageView: UIViewRepresentable {
    var svgString: String
    var size: CGSize

    func updateUIView(_ uiView: SVGKFastImageView, context: Context) {
        // Create a new SVGKImage with the updated svgString
        let svgData = svgString.data(using: .utf8) ?? Data()
        let svgImage = SVGKImage(data: svgData) ?? SVGKImage()

        // Update the image in the view
        uiView.image = svgImage
        uiView.contentMode = .scaleAspectFit
        uiView.image.size = size
    }

    func makeUIView(context: Context) -> SVGKFastImageView {
        let svgData = svgString.data(using: .utf8) ?? Data()
        let svgImage = SVGKImage(data: svgData)
        return SVGKFastImageView(svgkImage: svgImage ?? SVGKImage())
    }
}

struct SVGImageView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleSVG = """
        <svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
            <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
        </svg>
        """

        SVGImageView(svgString: sampleSVG, size: CGSize(width: 100, height: 100))
    }
}
