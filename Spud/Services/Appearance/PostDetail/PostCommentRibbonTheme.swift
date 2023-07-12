//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

enum PostCommentRibbonTheme: String, CaseIterable, Codable {
    case rainbow
    case combustion
    case ocean
    case forecast
    case nuit
    case bleep

    var localizedString: String {
        switch self {
        case .rainbow:
            return "Rainbow"
        case .combustion:
            return "Combustion"
        case .ocean:
            return "Ocean"
        case .forecast:
            return "Forecast"
        case .nuit:
            return "Nuit"
        case .bleep:
            return "Bleep"
        }
    }

    var colors: [UIColor] {
        switch self {
        case .rainbow:
            return [
                UIColor(displayP3Red: 161 / 255.0, green: 57 / 255.0, blue: 46 / 255.0, alpha: 1),
                UIColor(displayP3Red: 165 / 255.0, green: 91 / 255.0, blue: 37 / 255.0, alpha: 1),
                UIColor(displayP3Red: 145 / 255.0, green: 120 / 255.0, blue: 54 / 255.0, alpha: 1),
                UIColor(displayP3Red: 63 / 255.0, green: 110 / 255.0, blue: 79 / 255.0, alpha: 1),
                UIColor(displayP3Red: 53 / 255.0, green: 102 / 255.0, blue: 171 / 255.0, alpha: 1),
                UIColor(displayP3Red: 43 / 255.0, green: 69 / 255.0, blue: 131 / 255.0, alpha: 1),
                UIColor(displayP3Red: 94 / 255.0, green: 61 / 255.0, blue: 144 / 255.0, alpha: 1),
            ]
        case .combustion:
            return [
                UIColor(displayP3Red: 172 / 255.0, green: 39 / 255.0, blue: 29 / 255.0, alpha: 1),
                UIColor(displayP3Red: 142 / 255.0, green: 32 / 255.0, blue: 25 / 255.0, alpha: 1),
                UIColor(displayP3Red: 149 / 255.0, green: 61 / 255.0, blue: 30 / 255.0, alpha: 1),
                UIColor(displayP3Red: 176 / 255.0, green: 103 / 255.0, blue: 40 / 255.0, alpha: 1),
                UIColor(displayP3Red: 168 / 255.0, green: 127 / 255.0, blue: 47 / 255.0, alpha: 1),
                UIColor(displayP3Red: 163 / 255.0, green: 148 / 255.0, blue: 50 / 255.0, alpha: 1),
                UIColor(displayP3Red: 154 / 255.0, green: 160 / 255.0, blue: 53 / 255.0, alpha: 1),
            ]
        case .ocean:
            return [
                UIColor(displayP3Red: 34 / 255.0, green: 82 / 255.0, blue: 144 / 255.0, alpha: 1),
                UIColor(displayP3Red: 51 / 255.0, green: 115 / 255.0, blue: 190 / 255.0, alpha: 1),
                UIColor(displayP3Red: 66 / 255.0, green: 138 / 255.0, blue: 173 / 255.0, alpha: 1),
                UIColor(displayP3Red: 50 / 255.0, green: 114 / 255.0, blue: 198 / 255.0, alpha: 1),
                UIColor(displayP3Red: 73 / 255.0, green: 119 / 255.0, blue: 166 / 255.0, alpha: 1),
                UIColor(displayP3Red: 40 / 255.0, green: 89 / 255.0, blue: 149 / 255.0, alpha: 1),
                UIColor(displayP3Red: 76 / 255.0, green: 108 / 255.0, blue: 159 / 255.0, alpha: 1),
            ]
        case .forecast:
            return [
                UIColor(displayP3Red: 49 / 255.0, green: 78 / 255.0, blue: 55 / 255.0, alpha: 1),
                UIColor(displayP3Red: 91 / 255.0, green: 112 / 255.0, blue: 66 / 255.0, alpha: 1),
                UIColor(displayP3Red: 77 / 255.0, green: 141 / 255.0, blue: 57 / 255.0, alpha: 1),
                UIColor(displayP3Red: 123 / 255.0, green: 151 / 255.0, blue: 96 / 255.0, alpha: 1),
                UIColor(displayP3Red: 142 / 255.0, green: 143 / 255.0, blue: 62 / 255.0, alpha: 1),
                UIColor(displayP3Red: 102 / 255.0, green: 156 / 255.0, blue: 90 / 255.0, alpha: 1),
                UIColor(displayP3Red: 110 / 255.0, green: 111 / 255.0, blue: 59 / 255.0, alpha: 1),
            ]
        case .nuit:
            return [
                UIColor(displayP3Red: 45 / 255.0, green: 48 / 255.0, blue: 55 / 255.0, alpha: 1),
                UIColor(displayP3Red: 53 / 255.0, green: 56 / 255.0, blue: 62 / 255.0, alpha: 1),
                UIColor(displayP3Red: 49 / 255.0, green: 51 / 255.0, blue: 55 / 255.0, alpha: 1),
                UIColor(displayP3Red: 66 / 255.0, green: 69 / 255.0, blue: 73 / 255.0, alpha: 1),
                UIColor(displayP3Red: 82 / 255.0, green: 85 / 255.0, blue: 91 / 255.0, alpha: 1),
                UIColor(displayP3Red: 101 / 255.0, green: 103 / 255.0, blue: 109 / 255.0, alpha: 1),
                UIColor(displayP3Red: 123 / 255.0, green: 126 / 255.0, blue: 132 / 255.0, alpha: 1),
            ]
        case .bleep:
            return [
                UIColor(displayP3Red: 162 / 255.0, green: 78 / 255.0, blue: 65 / 255.0, alpha: 1),
                UIColor(displayP3Red: 73 / 255.0, green: 105 / 255.0, blue: 159 / 255.0, alpha: 1),
                UIColor(displayP3Red: 108 / 255.0, green: 96 / 255.0, blue: 156 / 255.0, alpha: 1),
                UIColor(displayP3Red: 168 / 255.0, green: 138 / 255.0, blue: 79 / 255.0, alpha: 1),
                UIColor(displayP3Red: 68 / 255.0, green: 126 / 255.0, blue: 85 / 255.0, alpha: 1),
                UIColor(displayP3Red: 170 / 255.0, green: 107 / 255.0, blue: 41 / 255.0, alpha: 1),
                UIColor(displayP3Red: 146 / 255.0, green: 44 / 255.0, blue: 43 / 255.0, alpha: 1),
            ]
        }
    }
}
