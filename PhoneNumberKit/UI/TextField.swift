//
//  TextField.swift
//  PhoneNumberKit
//
//  Created by Roy Marmelstein on 07/11/2015.
//  Copyright © 2015 Roy Marmelstein. All rights reserved.
//

import Foundation
import UIKit

/// Custom text field that formats phone numbers
open class PhoneNumberTextField: UITextField, UITextFieldDelegate {
    public let phoneNumberKit: PhoneNumberKit_!

    /// Override setText so number will be automatically formatted when setting text by code
    override open var text: String? {
        set {
            if isPartialFormatterEnabled && newValue != nil {
                let formattedNumber = partialFormatter.formatPartial(newValue! as String)
                super.text = formattedNumber
            } else {
                super.text = newValue
            }
        }
        get {
            return super.text
        }
    }

    /// allows text to be set without formatting
    open func setTextUnformatted(newValue: String?) {
        super.text = newValue
    }

    private lazy var _defaultRegion: String = PhoneNumberKit_.defaultRegionCode()

    /// Override region to set a custom region. Automatically uses the default region code.
    open var defaultRegion: String {
        get {
            return self._defaultRegion
        }
        @available(*,
            deprecated,
            message: """
                The setter of defaultRegion is deprecated,
                please override defaultRegion in a subclass instead.
            """
        )
        set {
        }
    }

    public var withPrefix: Bool = true {
        didSet {
            partialFormatter.withPrefix = withPrefix
            if withPrefix == false {
                self.keyboardType = UIKeyboardType.numberPad
            } else {
                self.keyboardType = UIKeyboardType.phonePad
            }
        }
    }
    public var isPartialFormatterEnabled = true

    public var maxDigits: Int? {
        didSet {
            partialFormatter.maxDigits = maxDigits
        }
    }
    
    public private(set) lazy var partialFormatter: PartialFormatter = PartialFormatter(
        phoneNumberKit: phoneNumberKit,
        defaultRegion: defaultRegion,
        withPrefix: withPrefix
    )

    let nonNumericSet: NSCharacterSet = {
        var mutableSet = NSMutableCharacterSet.decimalDigit().inverted
        mutableSet.remove(charactersIn: PhoneNumberConstants.plusChars)
        return mutableSet as NSCharacterSet
    }()

    weak private var _delegate: UITextFieldDelegate?

    override open var delegate: UITextFieldDelegate? {
        get {
            return _delegate
        }
        set {
            self._delegate = newValue
        }
    }

    // MARK: Status

    public var currentRegion: String {
        get {
            return partialFormatter.currentRegion
        }
    }

    public var nationalNumber: String {
        get {
            let rawNumber = self.text ?? String()
            return partialFormatter.nationalNumber(from: rawNumber)
        }
    }

    public var isValidNumber: Bool {
        get {
            let rawNumber = self.text ?? String()
            do {
                _ = try phoneNumberKit.parse(rawNumber, withRegion: currentRegion)
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: Lifecycle

    /**
     Init with a phone number kit instance. Because a PhoneNumberKit initialization is expensive,
     you can pass a pre-initialized instance to avoid incurring perf penalties.

     - parameter phoneNumberKit: A PhoneNumberKit instance to be used by the text field.

     - returns: UITextfield
     */
    public convenience init(withPhoneNumberKit phoneNumberKit: PhoneNumberKit_) {
        self.init(frame: .zero, phoneNumberKit: phoneNumberKit)
    }

    /**
     Init with frame and phone number kit instance.

     - parameter frame: UITextfield frame
     - parameter phoneNumberKit: A PhoneNumberKit instance to be used by the text field.

     - returns: UITextfield
     */
    public init(frame: CGRect, phoneNumberKit: PhoneNumberKit_) {
        self.phoneNumberKit = phoneNumberKit
        super.init(frame: frame)
        self.setup()
    }


    /**
     Init with frame
     
     - parameter frame: UITextfield F
     
     - returns: UITextfield
     */
    override public init(frame: CGRect) {
        phoneNumberKit = PhoneNumberKit_()
        super.init(frame:frame)
        self.setup()
    }

    /**
     Init with coder
     
     - parameter aDecoder: decoder
     
     - returns: UITextfield
     */
    required public init(coder aDecoder: NSCoder) {
        phoneNumberKit = PhoneNumberKit_()
        super.init(coder: aDecoder)!
        self.setup()
    }

    func setup() {
        self.autocorrectionType = .no
        self.keyboardType = UIKeyboardType.phonePad
        super.delegate = self
    }

    // MARK: Phone number formatting

    /**
     *  To keep the cursor position, we find the character immediately after the cursor and count the number of times it repeats in the remaining string as this will remain constant in every kind of editing.
     */

    internal struct CursorPosition {
        let numberAfterCursor: String
        let repetitionCountFromEnd: Int
    }

    internal func extractCursorPosition() -> CursorPosition? {
        var repetitionCountFromEnd = 0
        // Check that there is text in the UITextField
        guard let text = text, let selectedTextRange = selectedTextRange else {
            return nil
        }
        let textAsNSString = text as NSString
        let cursorEnd = offset(from: beginningOfDocument, to: selectedTextRange.end)
        // Look for the next valid number after the cursor, when found return a CursorPosition struct
        for i in cursorEnd ..< textAsNSString.length {
            let cursorRange = NSMakeRange(i, 1)
            let candidateNumberAfterCursor: NSString = textAsNSString.substring(with: cursorRange) as NSString
            if (candidateNumberAfterCursor.rangeOfCharacter(from: nonNumericSet as CharacterSet).location == NSNotFound) {
                for j in cursorRange.location ..< textAsNSString.length {
                    let candidateCharacter = textAsNSString.substring(with: NSMakeRange(j, 1))
                    if candidateCharacter == candidateNumberAfterCursor as String {
                        repetitionCountFromEnd += 1
                    }
                }
                return CursorPosition(numberAfterCursor: candidateNumberAfterCursor as String, repetitionCountFromEnd: repetitionCountFromEnd)
            }
        }
        return nil
    }

    // Finds position of previous cursor in new formatted text
    internal func selectionRangeForNumberReplacement(textField: UITextField, formattedText: String) -> NSRange? {
        let textAsNSString = formattedText as NSString
        var countFromEnd = 0
        guard let cursorPosition = extractCursorPosition() else {
            return nil
        }

        for i in stride(from: (textAsNSString.length - 1), through: 0, by: -1) {
            let candidateRange = NSMakeRange(i, 1)
            let candidateCharacter = textAsNSString.substring(with: candidateRange)
            if candidateCharacter == cursorPosition.numberAfterCursor {
                countFromEnd += 1
                if countFromEnd == cursorPosition.repetitionCountFromEnd {
                    return candidateRange
                }
            }
        }

        return nil
    }

    open func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {

        // This allows for the case when a user autocompletes a phone number:
        if range == NSRange(location: 0, length: 0) && string == " " {
            return true
        }

        guard let text = text else {
            return false
        }

        // allow delegate to intervene
        guard _delegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true else {
            return false
        }
        guard isPartialFormatterEnabled else {
            return true
        }

        let textAsNSString = text as NSString
        let changedRange = textAsNSString.substring(with: range) as NSString
        let modifiedTextField = textAsNSString.replacingCharacters(in: range, with: string)

        let filteredCharacters = modifiedTextField.filter {
            return  String($0).rangeOfCharacter(from: (textField as! PhoneNumberTextField).nonNumericSet as CharacterSet) == nil
        }
        let rawNumberString = String(filteredCharacters)

        let formattedNationalNumber = partialFormatter.formatPartial(rawNumberString as String)
        var selectedTextRange: NSRange?

        let nonNumericRange = (changedRange.rangeOfCharacter(from: nonNumericSet as CharacterSet).location != NSNotFound)
        if (range.length == 1 && string.isEmpty && nonNumericRange) {
            selectedTextRange = selectionRangeForNumberReplacement(textField: textField, formattedText: modifiedTextField)
            textField.text = modifiedTextField
        } else {
            selectedTextRange = selectionRangeForNumberReplacement(textField: textField, formattedText: formattedNationalNumber)
            textField.text = formattedNationalNumber
        }
        sendActions(for: .editingChanged)
        if let selectedTextRange = selectedTextRange, let selectionRangePosition = textField.position(from: beginningOfDocument, offset: selectedTextRange.location) {
            let selectionRange = textField.textRange(from: selectionRangePosition, to: selectionRangePosition)
            textField.selectedTextRange = selectionRange
        }

        return false
    }

    // MARK: UITextfield Delegate

    open func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldBeginEditing?(textField) ?? true
    }

    open func textFieldDidBeginEditing(_ textField: UITextField) {
        _delegate?.textFieldDidBeginEditing?(textField)
    }

    open func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldEndEditing?(textField) ?? true
    }

    open func textFieldDidEndEditing(_ textField: UITextField) {
        _delegate?.textFieldDidEndEditing?(textField)
    }

    open func textFieldShouldClear(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldClear?(textField) ?? true
    }

    open func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return _delegate?.textFieldShouldReturn?(textField) ?? true
    }
}
