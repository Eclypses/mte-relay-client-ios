// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

class KeychainHelper {
    
    var service: String!
    var account: String!
    
    init(service: String, account: String) {
        self.service = service
        self.account = account
    }
    
    func save(data: Data) throws {

        let query: [String: AnyObject] = [
            // kSecAttrService,  kSecAttrAccount, and kSecClass
            // uniquely identify the item to save in Keychain
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: kCFBooleanTrue,
            
            // kSecValueData is the item value to save
            kSecValueData as String: data as AnyObject
        ]
        
        // SecItemAdd attempts to add the item identified by
        // the query to keychain
        let status = SecItemAdd(
            query as CFDictionary,
            nil
        )

        // errSecDuplicateItem is a special case where the
        // item identified by the query already exists. Throw
        // duplicateItem so the client can determine whether
        // or not to handle this as an error
        if status == errSecDuplicateItem {
            throw KeychainError.duplicateItem
        }

        // Any status other than errSecSuccess indicates the
        // save operation failed.
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    func read() throws -> Data {
        let query: [String: AnyObject] = [
            // kSecAttrService,  kSecAttrAccount, and kSecClass
            // uniquely identify the item to read in Keychain
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: kCFBooleanTrue,
            
            // kSecMatchLimitOne indicates keychain should read
            // only the most recent item matching this query
            kSecMatchLimit as String: kSecMatchLimitOne,

            // kSecReturnData is set to kCFBooleanTrue in order
            // to retrieve the data for the item
            kSecReturnData as String: kCFBooleanTrue
        ]

        // SecItemCopyMatching will attempt to copy the item
        // identified by query to the reference itemCopy
        var itemCopy: AnyObject?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &itemCopy
        )

        // errSecItemNotFound is a special status indicating the
        // read item does not exist. Throw itemNotFound so the
        // client can determine whether or not to handle
        // this case
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        
        // Any status other than errSecSuccess indicates the
        // read operation failed.
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        // This implementation of KeychainInterface requires all
        // items to be saved and read as Data. Otherwise,
        // invalidItemFormat is thrown
        guard let password = itemCopy as? Data else {
            throw KeychainError.invalidItemFormat
        }

        return password
    }
    
    func update(data: Data) throws {
        let query: [String: AnyObject] = [
            // kSecAttrService,  kSecAttrAccount, and kSecClass
            // uniquely identify the item to update in Keychain
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: kCFBooleanTrue
        ]
        
        // attributes is passed to SecItemUpdate with
        // kSecValueData as the updated item value
        let attributes: [String: AnyObject] = [
            kSecValueData as String: data as AnyObject
        ]
        
        // SecItemUpdate attempts to update the item identified
        // by query, overriding the previous value
        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        // errSecItemNotFound is a special status indicating the
        // item to update does not exist. Throw itemNotFound so
        // the client can determine whether or not to handle
        // this as an error
        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }

        // Any status other than errSecSuccess indicates the
        // update operation failed.
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    func delete() throws {
        let query: [String: AnyObject] = [
            // kSecAttrService,  kSecAttrAccount, and kSecClass
            // uniquely identify the item to delete in Keychain
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: kCFBooleanTrue
        ]

        // SecItemDelete attempts to perform a delete operation
        // for the item identified by query. The status indicates
        // if the operation succeeded or failed.
        let status = SecItemDelete(query as CFDictionary)

        // Any status other than errSecSuccess indicates the
        // delete operation failed.
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeychainError: Error {
    // Attempted read for an item that does not exist.
    case itemNotFound

    // Attempted save to override an existing item.
    // Use update instead of save to update existing items
    case duplicateItem

    // A read of an item in any format other than Data
    case invalidItemFormat

    // Any operation result status than errSecSuccess
    case unexpectedStatus(OSStatus)
}

// Without this, `localizedDescription` renders as "(Relay.KeychainError error 0.)"
// — the case index, with the OSStatus discarded. That string is what surfaced to
// callers when host storage failed, and it named neither the cause nor a remedy.
extension KeychainError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found."
        case .duplicateItem:
            return "Keychain item already exists; update it instead of saving."
        case .invalidItemFormat:
            return "Keychain item was not in the expected Data format."
        case .unexpectedStatus(let status):
            return "Keychain operation failed with OSStatus \(status).\(Self.hint(for: status))"
        }
    }

    /// The statuses worth explaining rather than leaving the caller to look up.
    private static func hint(for status: OSStatus) -> String {
        switch status {
        case errSecMissingEntitlement:
            // Lead with the likely cause. Ad-hoc signing is normally sufficient and
            // no entitlements file is needed, so naming the entitlement first sends
            // people to add one they do not require.
            return " The app was most likely built without code signing — Relay stores"
                 + " a small host record in the keychain, so the app must be signed."
                 + " Ad-hoc signing is enough and no entitlements file is required."
                 + " If the app IS signed, check for a missing Keychain Sharing"
                 + " entitlement."
        case errSecInteractionNotAllowed:
            return " The keychain is not accessible in the current device state,"
                 + " typically because the device is locked."
        case errSecUserCanceled:
            return " The keychain request was cancelled."
        default:
            return ""
        }
    }
}
