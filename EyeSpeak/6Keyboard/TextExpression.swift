//
//  TextExpression.swift
//  EyeSpeak
//
//  Created by Kyle Ohanian on 4/16/19.
//  Copyright © 2019 WillowTree. All rights reserved.
//

import Foundation

protocol TextExpressionDelegate: class {
    func textExpression(_ expression: TextExpression, valueChanged value: String)
}

class TextExpression {
    private(set) var value: String = ""
    
    weak var delegate: TextExpressionDelegate?
    
    var wordCount: Int {
        return value.split(separator: " ").count
    }
    
    var splitExpression: [String] {
        let trimmedExpression = self.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedExpression.split(separator: " ").map { String($0) }
    }
    
    func add(word: String) {
        let trimmedExpression = self.value.trimmingCharacters(in: .whitespacesAndNewlines)
        var newSplitExpression = trimmedExpression.split(separator: " ").map { String($0) }
        newSplitExpression.append(word)
        self.value = newSplitExpression.joined(separator: " ")
        self.delegate?.textExpression(self, valueChanged: self.value)
    }
    
    func replaceWord(at index: Int, with newWord: String) {
        var newSplitExpression = self.splitExpression
        if newSplitExpression.count > index && index >= 0 {
            newSplitExpression[index] = newWord
        }
        self.value = newSplitExpression.joined(separator: " ")
        self.delegate?.textExpression(self, valueChanged: self.value)
    }
    
    func replaceLastWord(with newWord: String) {
        self.replaceWord(at: self.splitExpression.count - 1, with: newWord)
    }
    
    func word(at index: Int) -> String? {
        if self.splitExpression.count > index && index >= 0 {
            return self.splitExpression[index]
        } else {
            return nil
        }
    }
    
    func lastWord() -> String? {
        return word(at: self.splitExpression.count - 1)
    }
    
    func backspace() {
        if self.value.count > 0 {
            _ = self.value.removeLast()
        }
        self.delegate?.textExpression(self, valueChanged: self.value)
    }
    
    func append(text: String) {
        self.value.append(text)
        self.delegate?.textExpression(self, valueChanged: self.value)
    }
    
    func clear() {
        self.value = ""
        self.delegate?.textExpression(self, valueChanged: self.value)
    }
    
    func space() {
        self.value.append(" ")
        self.delegate?.textExpression(self, valueChanged: self.value)
    }
}
