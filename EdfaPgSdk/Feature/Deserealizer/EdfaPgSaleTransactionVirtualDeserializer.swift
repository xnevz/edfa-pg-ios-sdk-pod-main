//
//  EdfaPgSaleTransactionVirtualDeserializer.swift
//  EdfaPgSdk
//
//  Created by EdfaPg(zik) on 11.03.2021.
//

import Foundation

final class EdfaPgSaleTransactionVirtualDeserializer {
    
    enum CodingKeys: String, CodingKey {
        case result, status, action
    }
    
    func decode(from decoder: Decoder) throws -> EdfaPgSaleVirtualTransactionResult {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Check if this is an error response (no action field means error)
        guard container.contains(.action) else {
            // If there's no action field, this might be an error response
            // Try to decode as decline which is more forgiving
            return try .decline(.init(from: decoder))
        }
        
        // Check the result and status to determine the appropriate response type
        if let result = try? container.decode(EdfaPgResult.self, forKey: .result) {
            switch result {
            case .declined, .error:
                return try .decline(.init(from: decoder))
            default:
                break
            }
        }
        
        return try .success(.init(from: decoder))
    }
}
