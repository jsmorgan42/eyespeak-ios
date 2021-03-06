//
//  UIViewController+Segues.swift
//  EyeSpeak
//
//  Created by Kyle Ohanian on 4/19/19.
//  Copyright © 2019 WillowTree. All rights reserved.
//

import UIKit

enum Segue: String {
    case presetsCollectionViewSegue
    case presetsSegue
    case unknown
}

extension UIViewController {
    func perform(segue: Segue, sender: Any?) {
        self.performSegue(withIdentifier: segue.rawValue, sender: sender)
    }
}
