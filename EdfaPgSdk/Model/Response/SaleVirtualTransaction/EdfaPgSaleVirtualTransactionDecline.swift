//
//  EdfaPgSaleVirtualTransactionDecline.swift
//  EdfaPgSdk
//
//  Created by EdfaPg(zik) on 09.03.2021.
//

import Foundation

/// The SALE Virtual Transaction decline result of the *EdfaPgSaleVirtualTransactionResult*.
///
/// See *EdfaPgSaleVirtualTransactionResult*
public struct EdfaPgSaleVirtualTransactionDecline: EdfaPgResultProtocol {
    public let action: EdfaPgAction
    public let result: EdfaPgResult
    public let status: EdfaPgStatus
    public let orderId: String
    public let transactionId: String
    public let transactionDate: String?
    public let declineReason: String?
}

extension EdfaPgSaleVirtualTransactionDecline: Codable {
    enum CodingKeys: String, CodingKey {
        case action, result, status
        case orderId = "order_id"
        case transactionId = "trans_id"
        case transactionDate = "trans_date"
        case declineReason = "decline_reason"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Provide default values for missing fields to handle error responses gracefully
        action = (try? container.decode(EdfaPgAction.self, forKey: .action)) ?? .undefined
        result = try container.decode(EdfaPgResult.self, forKey: .result)
        status = (try? container.decode(EdfaPgStatus.self, forKey: .status)) ?? .undefined
        orderId = (try? container.decode(String.self, forKey: .orderId)) ?? ""
        transactionId = (try? container.decode(String.self, forKey: .transactionId)) ?? ""
        transactionDate = try? container.decode(String.self, forKey: .transactionDate)
        declineReason = try? container.decode(String.self, forKey: .declineReason)
    }
}
