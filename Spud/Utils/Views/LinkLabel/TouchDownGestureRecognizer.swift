//
//  TouchDownGestureRecognizer.swift
//  TwIM
//
//  Created by Andrew Hart on 07/08/2015.
//  Copyright (c) 2015 Project Dent. All rights reserved.
//

import UIKit

class TouchGestureRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if self.state == UIGestureRecognizer.State.possible {
            self.state = UIGestureRecognizer.State.began
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        self.state = UIGestureRecognizer.State.changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        self.state = UIGestureRecognizer.State.ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        self.state = UIGestureRecognizer.State.cancelled
    }
}
