//
//  EdfaApplePay.swift
//  Sample
//
//  Created by Zohaib Kambrani on 23/01/2023.
//
//  ============================================================================
//  APPLE PAY INTEGRATION FOR EDFA PAYMENT GATEWAY
//  ============================================================================
//
//  This file implements Apple Pay payment processing through the EDFA Payment Gateway.
//  It provides a simplified interface for merchants to accept Apple Pay payments
//  without dealing with complex Apple Pay APIs directly.
//
//  MAIN FLOW OVERVIEW:
//  -------------------
//  Step 1: Merchant configures Apple Pay parameters (merchant ID, amount, currency, etc.)
//  Step 2: User initiates payment, Apple Pay sheet is presented
//  Step 3: User authenticates with Face ID/Touch ID and authorizes payment
//  Step 4: Payment token is received from Apple
//  Step 5: Token is sent to EDFA Payment Gateway for processing
//  Step 6: Transaction result is returned to merchant
//
//  KEY COMPONENTS:
//  ---------------
//  - EdfaPgShippingAddress: Holds shipping/billing address information
//  - EdfaApplePay: Main class for configuring and initiating Apple Pay
//  - EdfaApplePayDelegate: Handles Apple Pay callbacks and authorization
//  ============================================================================

import Foundation
import PassKit

// ============================================================================
// MARK: - Shipping Address Model
// ============================================================================
/// Represents shipping/billing address information for Apple Pay transactions.
/// This information can be collected from the user during the payment process
/// and used for order fulfillment.
public class EdfaPgShippingAddress{
    /// Customer's full name
    var name:String?
    
    /// Complete shipping/billing address
    var address:String?
    
    /// Customer's email address for receipts and notifications
    var email:String?
    
    /// Customer's contact phone number
    var phone:String?
    
    /// Initializes a new shipping address object with customer details
    /// - Parameters:
    ///   - name: Customer's full name
    ///   - address: Complete address string
    ///   - email: Customer's email
    ///   - phone: Customer's phone number
    init(name:String?, address:String?, email:String?, phone:String?) {
        self.name  = name
        self.address  = address
        self.email  = email
        self.phone  = phone
    }

}

// ============================================================================
// MARK: - Global State Variables
// ============================================================================
// These variables hold the configuration and callback closures for Apple Pay.
// They are module-private (fileprivate) to prevent external access while
// allowing sharing between related classes in this file.

/// Callback triggered when Apple Pay authentication completes successfully.
/// Receives the PKPayment object containing the encrypted payment token.
fileprivate var _onAuthentication:((PKPayment) -> Void)?

/// Callback triggered when the transaction is successfully processed by EDFA gateway.
/// Receives a dictionary containing transaction details (transaction ID, status, etc.).
fileprivate var _onTransactionSuccess:(([String:Any]?) -> Void)?

/// Callback triggered when the transaction fails or is declined.
/// Receives a dictionary with error details and failure reasons.
fileprivate var _onTransactionFailure:(([String:Any]) -> Void)?

/// Callback triggered when an error occurs during setup or validation.
/// Receives an array of error messages describing what went wrong.
fileprivate var _onError:(([String]) -> Void)!

/// Payer information (customer details like name, email, address).
fileprivate var _payer:EdfaPgPayer!

/// Order details (amount, currency, description, order ID).
fileprivate var _order:EdfaPgSaleOrder!

/// Additional custom data that can be sent with the transaction.
fileprivate var _extras:[Extra] = []

/// Flag to enable/disable detailed logging for debugging purposes.
fileprivate var enableLogs:Bool = false

/// Flag to bypass Apple Pay sheet and use placeholder data instead.
/// When enabled, no Apple Pay UI is shown and fake data is sent directly.
fileprivate var bypassApplePay:Bool = false

/// Placeholder payment data to use when bypass mode is enabled.
/// You can customize this JSON structure as needed for testing.
fileprivate var placeholderPaymentData: [String: Any] = [
    "transactionIdentifier": "BYPASS_TXN_\(UUID().uuidString)",
    "paymentData": [
        "version": "EC_v1",
        "data": "PLACEHOLDER_ENCRYPTED_DATA",
        "signature": "PLACEHOLDER_SIGNATURE",
        "header": [
            "ephemeralPublicKey": "PLACEHOLDER_PUBLIC_KEY",
            "publicKeyHash": "PLACEHOLDER_KEY_HASH",
            "transactionId": "PLACEHOLDER_TRANSACTION_ID"
        ]
    ],
    "paymentMethod": [
        "displayName": "Test Card 1234",
        "network": "Visa",
        "type": "credit"
    ]
]

/// Virtual sale adapter for processing Apple Pay transactions through EDFA gateway.
/// This handles the communication with the payment backend.
fileprivate let virtualSaleAdapter = EdfaPgVirtualSaleAdapter()

// ============================================================================
// MARK: - EdfaApplePay Main Class
// ============================================================================
/// Main class for configuring and initiating Apple Pay payments.
/// This class provides a fluent interface (builder pattern) for setting up
/// Apple Pay parameters and handling payment flow.
///
/// USAGE EXAMPLE:
/// ```
/// EdfaApplePay()
///     .set(applePayMerchantID: "merchant.com.yourcompany.app")
///     .set(order: order)
///     .set(payer: payer)
///     .addSupported(paymentNetworks: [.visa, .masterCard])
///     .on(transactionSuccess: { result in
///         print("Payment successful: \(result)")
///     })
///     .on(transactionFailure: { error in
///         print("Payment failed: \(error)")
///     })
///     .initialize(target: self, onError: { errors in
///         print("Setup error: \(errors)")
///     }, onPresent: nil)
/// ```
public class EdfaApplePay : EdfaPgAdapterDelegate{
    
    /// Initializes the Apple Pay handler and sets up the delegate connection
    /// to receive callbacks from the virtual sale adapter.
    public init() {
        virtualSaleAdapter.delegate = self
    }
    
    /// The Apple Pay payment request object that will be configured and presented.
    private let request = PKPaymentRequest()
    
    /// Line items to display in the Apple Pay sheet (e.g., subtotal, tax, shipping).
    /// If empty, a single item will be created automatically from the order details.
    private var purchaseItems:[PKPaymentSummaryItem] = []
    
    /// Your Apple Pay merchant identifier (format: merchant.com.yourcompany.app).
    /// This must be registered in your Apple Developer account and configured
    /// in your app's capabilities.
    private var applePayMerchantID:String?
    
    /// Optional shipping address information for the transaction.
    private var shippingAddress:EdfaPgShippingAddress?
    
    /// Payment networks (card types) that you want to support.
    /// Examples: .visa, .masterCard, .amex, .discover, .mada
    /// If empty, all available networks will be used.
    private var supportedPaymentNetworks:[PKPaymentNetwork] = []
    
    /// Merchant capabilities defining the supported payment processing methods.
    /// Default is 3DS (3D Secure) for enhanced security.
    /// Options: .capability3DS, .capabilityEMV, .capabilityCredit, .capabilityDebit
    private var merchantCapability:PKMerchantCapability = PKMerchantCapability.capability3DS
    
    
    
    // ============================================================================
    // MARK: - Apple Pay Initialization and Presentation
    // ============================================================================
    
    /// **STEP 1: START APPLE PAY FLOW**
    /// This is the main entry point that orchestrates the entire Apple Pay process.
    /// It validates configuration, prepares the payment request, and presents the
    /// Apple Pay sheet to the user.
    ///
    /// **BYPASS MODE:**
    /// If bypass mode is enabled, skips Apple Pay UI entirely and uses placeholder data.
    /// This is useful for testing without Apple Pay setup or sending custom data.
    ///
    /// - Parameters:
    ///   - target: The view controller that will present the Apple Pay sheet
    ///   - onError: Callback for any errors during setup or validation
    ///   - onPresent: Optional callback triggered when Apple Pay sheet is presented
    ///
    /// PROCESS FLOW:
    /// 1. Store error callback for later use
    /// 2. Check if bypass mode is enabled - if yes, use placeholder data
    /// 3. Check if Apple Pay is supported on this device
    /// 4. Validate all required parameters (merchant ID, amount, callbacks, etc.)
    /// 5. Prepare the PKPaymentRequest with all configuration
    /// 6. Create and configure the Apple Pay view controller
    /// 7. Set up the delegate to handle payment callbacks
    /// 8. Present the Apple Pay sheet to the user
    private func start(target:UIViewController, onError:@escaping ((Any) -> Void), onPresent:(() ->Void)?){
        // Store the error callback for use throughout the payment flow
        _onError = onError
        
        // ============================================================================
        // BYPASS MODE: Skip Apple Pay and use placeholder data
        // ============================================================================
        if bypassApplePay {
            log(label: "BYPASS MODE", object: "Apple Pay bypassed - using placeholder data")
            
            // Validate minimal required parameters for bypass mode
            let validation = validateBypassMode()
            if !validation.valid {
                _onError?(validation.validationErrors)
                return
            }
            
            // Trigger the onPresent callback immediately (simulating sheet presentation)
            onPresent?()
            
            // Process payment with placeholder data
            processBypassPayment()
            return
        }
        
        // ============================================================================
        // NORMAL MODE: Standard Apple Pay flow
        // ============================================================================
        
        // Check if this device supports Apple Pay with the specified networks
        if isApplePaySupported(){
            // Validate all required configuration parameters
            let validation = validate()
            if validation.valid{
                
                // Create and configure the payment request with all parameters
                let request = preparePayment(request:PKPaymentRequest())
                
                // Create the Apple Pay authorization view controller
                if let applePayController = PKPaymentAuthorizationViewController(paymentRequest: request){
                    // Set up the delegate to receive payment callbacks
                    applePayController.delegate = prepareDelegate(target: target, edfaApplePay: self)
                    
                    // Present the Apple Pay sheet to the user
                    target.present(applePayController, animated: true, completion: onPresent)
                }else{
                    // Failed to create the Apple Pay controller
                    _onError?(["Error initializing 'PKPaymentAuthorizationViewController(paymentRequest:)'"])
                    log(label: "Error", object:"Error initializing 'PKPaymentAuthorizationViewController(paymentRequest:)'")
                }
                
            }else{
                // Validation failed - report all validation errors
                _onError?(validation.validationErrors)
                log(label: "Error", object:"Error initializing 'PKPaymentAuthorizationViewController(paymentRequest:)'")

            }

            return
        }
        
        // Apple Pay is not supported on this device or with these networks
        if supportedPaymentNetworks.isEmpty{
            _onError?(["Cannot start apple pay, device may not supported or user/merchant is restricted from authorizing payments"])
            log(label: "Error", object:"Cannot start apple pay, device may not supported or user/merchant is restricted from authorizing payments")

        }else{
            _onError?(["Cannot start apple pay with your defined supported payment networks"])
            log(label: "Error", object:"Cannot start apple pay with your defined supported payment networks")
        }
    }
    
    /// **STEP 2: CHECK APPLE PAY AVAILABILITY**
    /// Determines if Apple Pay is available and properly configured on this device.
    ///
    /// CHECKS PERFORMED:
    /// - Device hardware supports Apple Pay (iPhone 6+, iPad, Apple Watch, etc.)
    /// - User has set up at least one card in Apple Wallet
    /// - User/merchant has permission to authorize payments
    /// - If specific networks are requested, checks if user has cards for those networks
    ///
    /// - Returns: true if Apple Pay can be used, false otherwise
    func isApplePaySupported() -> Bool{
        if supportedPaymentNetworks.isEmpty{
            // Check general Apple Pay availability (any card type)
            return PKPaymentAuthorizationViewController.canMakePayments()
        }
        
        // Check if Apple Pay is available with specific payment networks
        // (e.g., only Visa and Mastercard)
        return PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: supportedPaymentNetworks)
    }
    
    /// **STEP 3: PREPARE PAYMENT REQUEST**
    /// Configures the PKPaymentRequest object with all merchant and order details.
    /// This request defines what the user will see in the Apple Pay sheet.
    ///
    /// - Parameter request: An empty PKPaymentRequest to be configured
    /// - Returns: Fully configured PKPaymentRequest ready to be presented
    ///
    /// CONFIGURATION INCLUDES:
    /// - Merchant identifier (your Apple Pay merchant ID)
    /// - Merchant capabilities (3DS, EMV, etc.)
    /// - Country and currency codes
    /// - Payment summary items (line items shown to user)
    /// - Supported payment networks (card types accepted)
    private func preparePayment(request:PKPaymentRequest) -> PKPaymentRequest{
        // Set the merchant identifier registered with Apple
        request.merchantIdentifier = applePayMerchantID!
        
        // Set merchant capabilities (e.g., 3D Secure support)
        request.merchantCapabilities = merchantCapability
        
        // Set the country code (e.g., "SA" for Saudi Arabia)
        request.countryCode = _order.country
        
        // Set the currency code (e.g., "SAR" for Saudi Riyal)
        request.currencyCode = _order.currency
        
        // Configure line items to display in the Apple Pay sheet
        request.paymentSummaryItems = purchaseItems
        if purchaseItems.isEmpty{
            // If no custom items provided, create a single line item from order
            let label = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? _order.description
            request.paymentSummaryItems = [
                PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(value: _order.amount), type: .final)
            ]
        }
        
        // Set which card networks are accepted (Visa, Mastercard, etc.)
        request.supportedNetworks = supportedPaymentNetworks
        if supportedPaymentNetworks.isEmpty{
            // If not specified, use all available networks
            request.supportedNetworks = PKPaymentRequest.availableNetworks()
        }
                
        return request
    }
    
    /// **STEP 4: PREPARE DELEGATE**
    /// Creates and configures the delegate that will handle Apple Pay callbacks.
    /// Uses a clever workaround to avoid requiring the merchant's view controller
    /// to implement PKPaymentAuthorizationViewControllerDelegate directly.
    ///
    /// - Parameters:
    ///   - target: The merchant's view controller
    ///   - edfaApplePay: Reference to this Apple Pay handler
    /// - Returns: Configured delegate ready to handle payment authorization
    ///
    /// TECHNICAL NOTE:
    /// The delegate is implemented as a UIViewController to satisfy Apple's
    /// PKPaymentAuthorizationViewControllerDelegate requirements, but it's
    /// added as a hidden child view controller to avoid interfering with the UI.
    /// This simplifies integration for merchants who don't need to implement
    /// the delegate protocol themselves.
    private func prepareDelegate(target:UIViewController, edfaApplePay:EdfaApplePay) -> EdfaApplePayDelegate{
        let delegate = EdfaApplePayDelegate()
        
        // Required for PKPaymentAuthorizationViewControllerDelegate to work
        // (delegate protocol requires UIViewController conformance)
        // This approach minimizes code complexity for merchant integration
        delegate.view.isHidden = true
        target.addChild(delegate)
        
        return delegate
    }
}


// ============================================================================
// MARK: - Configuration Methods (Builder Pattern)
// ============================================================================
// These methods provide a fluent interface for configuring Apple Pay.
// Each method returns 'self' to allow method chaining.
//
// EXAMPLE:
// EdfaApplePay()
//     .set(applePayMerchantID: "merchant.id")
//     .set(order: order)
//     .set(payer: payer)
//     .on(transactionSuccess: { ... })
//     .initialize(...)
//
extension EdfaApplePay{
    
    /// **FINAL STEP: INITIALIZE AND PRESENT APPLE PAY**
    /// Call this method last, after configuring all parameters.
    /// This triggers the validation, preparation, and presentation of Apple Pay.
    ///
    /// - Parameters:
    ///   - target: The view controller that will present the Apple Pay sheet
    ///   - onError: Callback for setup/validation errors
    ///   - onPresent: Optional callback when sheet is presented
    public func initialize(target:UIViewController, onError:@escaping ((Any) -> Void), onPresent:(() ->Void)?){
        start(target: target, onError: onError, onPresent: onPresent)
    }
    
    /// Sets callback for successful Apple Pay authentication (user authorized payment).
    /// This is triggered immediately after Face ID/Touch ID authentication,
    /// BEFORE the transaction is sent to the payment gateway.
    ///
    /// - Parameter authentication: Closure receiving PKPayment with encrypted token
    /// - Returns: Self for method chaining
    public func on(authentication:@escaping ((PKPayment) -> Void)) -> EdfaApplePay{
        _onAuthentication = authentication
        return self
    }
    
    /// **REQUIRED** Sets callback for successful transaction processing.
    /// This is triggered after the payment gateway successfully processes the payment.
    ///
    /// - Parameter transactionSuccess: Closure receiving transaction details dictionary
    ///   - Contains: transaction ID, status, amount, currency, timestamp, etc.
    /// - Returns: Self for method chaining
    public func on(transactionSuccess:@escaping (([String:Any]?) -> Void)) -> EdfaApplePay{
        _onTransactionSuccess = transactionSuccess
        return self
    }
    
    /// **REQUIRED** Sets callback for failed/declined transactions.
    /// This is triggered when the payment gateway rejects the payment or an error occurs.
    ///
    /// - Parameter transactionFailure: Closure receiving error details dictionary
    ///   - Contains: error message, error code, decline reason, etc.
    /// - Returns: Self for method chaining
    public func on(transactionFailure:@escaping (([String:Any]) -> Void)) -> EdfaApplePay{
        _onTransactionFailure = transactionFailure
        return self
    }
    
    /// **REQUIRED** Sets your Apple Pay merchant identifier.
    /// This must match the merchant ID registered in your Apple Developer account
    /// and configured in your app's capabilities.
    ///
    /// FORMAT: "merchant.com.yourcompany.appname"
    ///
    /// - Parameter applePayMerchantID: Your registered Apple Pay merchant ID
    /// - Returns: Self for method chaining
    public func set(applePayMerchantID:String) -> EdfaApplePay{
        self.applePayMerchantID = applePayMerchantID
        return self
    }
    
    /// **REQUIRED** Sets the payer (customer) information.
    /// Contains customer details like name, email, address, phone, etc.
    ///
    /// - Parameter payer: EdfaPgPayer object with customer information
    /// - Returns: Self for method chaining
    public func set(payer:EdfaPgPayer) -> EdfaApplePay{
        _payer = payer
        return self
    }
    
    /// **REQUIRED** Sets the order details for this transaction.
    /// Contains amount, currency, order ID, description, country code.
    ///
    /// - Parameter order: EdfaPgSaleOrder object with order information
    /// - Returns: Self for method chaining
    public func set(order:EdfaPgSaleOrder) -> EdfaApplePay{
        _order = order
        return self
    }
    
    /// Sets additional custom data to send with the transaction.
    /// Use this for custom fields or metadata needed for your business logic.
    ///
    /// - Parameter extras: Array of Extra objects containing key-value pairs
    /// - Returns: Self for method chaining
    public func set(extras:[Extra]) -> EdfaApplePay{
        _extras = extras
        return self
    }
    
    
    /// Sets shipping/billing address for the transaction (optional).
    ///
    /// - Parameter shippingAddress: EdfaPgShippingAddress with customer address details
    /// - Returns: Self for method chaining
    public func set(shippingAddress:EdfaPgShippingAddress) -> EdfaApplePay{
        self.shippingAddress = shippingAddress
        return self
    }
    
    /// Sets merchant capability flags for payment processing (optional).
    /// Default is .capability3DS (3D Secure).
    ///
    /// OPTIONS:
    /// - .capability3DS: Supports 3D Secure authentication (recommended)
    /// - .capabilityEMV: Supports EMV chip card processing
    /// - .capabilityCredit: Supports credit card transactions
    /// - .capabilityDebit: Supports debit card transactions
    ///
    /// - Parameter merchantCapability: PKMerchantCapability flags
    /// - Returns: Self for method chaining
    public func set(merchantCapability:PKMerchantCapability) -> EdfaApplePay{
        self.merchantCapability = merchantCapability
        return self
    }
    
    /// Specifies which payment networks (card types) to accept (optional).
    /// If not set, all available networks will be used.
    ///
    /// EXAMPLES:
    /// - .visa, .masterCard, .amex, .discover
    /// - .mada (Saudi Arabia)
    /// - .cartesBancaires (France), .chinaUnionPay, etc.
    ///
    /// - Parameter paymentNetworks: Array of PKPaymentNetwork values
    /// - Returns: Self for method chaining
    public func addSupported(paymentNetworks:[PKPaymentNetwork]) -> EdfaApplePay{
        self.supportedPaymentNetworks = paymentNetworks
        return self
    }
    
    /// Adds a line item to display in the Apple Pay sheet (optional).
    /// Use this to show itemized breakdowns (subtotal, tax, shipping, discounts).
    /// If no items are added, a single item is created from the order total.
    ///
    /// - Parameters:
    ///   - label: Item description (e.g., "Subtotal", "Shipping", "Tax")
    ///   - amount: Item amount
    ///   - type: .final (fixed amount) or .pending (may change)
    /// - Returns: Self for method chaining
    public func addPurchaseItem(label:String, amount:Double, type:PKPaymentSummaryItemType) -> EdfaApplePay{
        purchaseItems.append(PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(value: amount), type: type))
        return self
    }
    
    /// Enables detailed logging for debugging (optional).
    /// When enabled, logs HTTP requests/responses and important events.
    ///
    /// - Parameter logs: true to enable logging, false to disable
    /// - Returns: Self for method chaining
    public func enable(logs:Bool) -> EdfaApplePay{
        enableLogs = logs
        return self
    }
    
    // ============================================================================
    // MARK: - BYPASS MODE CONFIGURATION
    // ============================================================================
    
    /// **BYPASS APPLE PAY (TEST/CUSTOM MODE)**
    /// Enables bypass mode to skip Apple Pay UI and use placeholder data instead.
    /// No Apple Pay sheet is shown, and fake payment data is sent directly to the gateway.
    ///
    /// USE CASES:
    /// - Testing without Apple Pay setup
    /// - Development/debugging
    /// - Sending custom payment data structures
    ///
    /// **WARNING:** This bypasses real Apple Pay payment processing.
    /// Only use for testing or when you want to send custom data.
    ///
    /// - Parameter bypass: true to enable bypass mode, false for normal Apple Pay
    /// - Returns: Self for method chaining
    public func enableBypassMode(_ bypass: Bool) -> EdfaApplePay {
        bypassApplePay = bypass
        return self
    }
    
    /// Sets custom placeholder payment data for bypass mode.
    /// This allows you to define the exact JSON structure sent to the gateway.
    ///
    /// EXPECTED STRUCTURE:
    /// ```
    /// [
    ///     "transactionIdentifier": "YOUR_TXN_ID",
    ///     "paymentData": [
    ///         "version": "EC_v1",
    ///         "data": "YOUR_DATA",
    ///         "signature": "YOUR_SIGNATURE",
    ///         "header": [...]
    ///     ],
    ///     "paymentMethod": [
    ///         "displayName": "Card Name",
    ///         "network": "Visa",
    ///         "type": "credit"
    ///     ]
    /// ]
    /// ```
    ///
    /// - Parameter data: Dictionary containing your custom payment data
    /// - Returns: Self for method chaining
    public func setPlaceholderPaymentData(_ data: [String: Any]) -> EdfaApplePay {
        placeholderPaymentData = data
        return self
    }
    
    /// Sets a custom transaction identifier for bypass mode.
    /// Convenience method to quickly change just the transaction ID.
    ///
    /// - Parameter identifier: Your custom transaction identifier
    /// - Returns: Self for method chaining
    public func setPlaceholderTransactionId(_ identifier: String) -> EdfaApplePay {
        placeholderPaymentData["transactionIdentifier"] = identifier
        return self
    }
}


// ============================================================================
// MARK: - Validation
// ============================================================================
// Validates all required parameters before presenting Apple Pay.
// This catches configuration errors early and provides clear error messages.
//
private extension EdfaApplePay{
    /// Validates all required Apple Pay configuration parameters.
    /// Checks for missing or invalid values and returns detailed error messages.
    ///
    /// VALIDATIONS PERFORMED:
    /// - Transaction success callback is set
    /// - Transaction failure callback is set
    /// - Apple Pay merchant ID is provided
    /// - Order amount is at least 0.10 (minimum for payment processing)
    /// - Currency code is provided (e.g., "SAR")
    /// - Country code is provided (e.g., "SA")
    ///
    /// - Returns: Tuple with validation result and array of error messages
    func validate() -> (valid:Bool, validationErrors:[String] ){
        var errors:[String] = []
        var valid = true

        if _onTransactionSuccess == nil{
            valid = valid && false
            errors.append("onTransactionFailure not set, try to call function 'EdfaApplePay.on(transactionSuccess:)'")
            log(label: "Error", object:"onTransactionFailure not set, try to call function 'EdfaApplePay.on(transactionSuccess:)'")
        }
        
        if _onTransactionFailure == nil{
            valid = valid && false
            errors.append("onTransactionFailure not set, try to call function 'EdfaApplePay.on(transactionFailure:)'")
            log(label: "Error", object:"onTransactionFailure not set, try to call function 'EdfaApplePay.on(transactionFailure:)'")
        }
        
        if applePayMerchantID == nil || applePayMerchantID!.isEmpty{
            valid = valid && false
            errors.append("Missing or invalid apple pay 'merchant identifier'")
            log(label: "Error", object:"Missing or invalid apple pay 'merchant identifier'")
        }
        
        if !(_order.amount >= 0.10){
            valid = valid && false
            errors.append("Missing or invalid amount should be greater than 0.09")
            log(label: "Error", object:"Missing or invalid amount should be greater than 0.09")
        }
        
        if _order.currency.isEmpty{
            valid = valid && false
            errors.append("Missing or invalid currency code (example: 'SAR' for Saudi Riyal)")
            log(label: "Error", object:"Missing or invalid currency code (example: 'SAR' for Saudi Riyal)")
        }
        
        if _order.country.isEmpty{
            valid = valid && false
            errors.append("Missing or invalid country code (example:'SA' for SaudiArabia)")
            log(label: "Error", object:"Missing or invalid country code (example:'SA' for SaudiArabia)")
        }
        
        return (valid, errors)
    }
    
    /// Validates required parameters for bypass mode (less strict than normal mode).
    /// Only checks essential parameters needed for gateway communication.
    ///
    /// - Returns: Tuple with validation result and array of error messages
    func validateBypassMode() -> (valid:Bool, validationErrors:[String]) {
        var errors:[String] = []
        var valid = true

        if _onTransactionSuccess == nil{
            valid = false
            errors.append("onTransactionSuccess callback required - call 'on(transactionSuccess:)'")
            log(label: "Bypass Error", object:"onTransactionSuccess not set")
        }
        
        if _onTransactionFailure == nil{
            valid = false
            errors.append("onTransactionFailure callback required - call 'on(transactionFailure:)'")
            log(label: "Bypass Error", object:"onTransactionFailure not set")
        }
        
        if !(_order.amount >= 0.10){
            valid = false
            errors.append("Order amount must be at least 0.10")
            log(label: "Bypass Error", object:"Invalid amount")
        }
        
        return (valid, errors)
    }
    
    /// Processes payment using placeholder data (bypass mode).
    /// Creates a fake payment structure and sends it to the gateway.
    func processBypassPayment() {
        log(label: "BYPASS PAYMENT", object: "Processing with placeholder data: \(placeholderPaymentData)")
        
        // Extract or create transaction identifier
        let transactionId = placeholderPaymentData["transactionIdentifier"] as? String ?? "BYPASS_\(UUID().uuidString)"
        
        // Convert placeholder data to JSON string
        if let paymentToken = try? JSONSerialization.data(withJSONObject: placeholderPaymentData), 
           let paymentTokenString = String(data: paymentToken, encoding: .utf8) {
            
            log(label: "BYPASS PAYLOAD", object: paymentTokenString)
            
            // Send to EDFA gateway using the same adapter as normal Apple Pay
            virtualSaleAdapter.execute(
                brand: "applepay",
                identifier: transactionId,
                returnUrl: EdfaPgProcessCompleteCallbackUrl,
                paymentToken: paymentTokenString,
                order: _order,
                payer: _payer,
                extras: _extras
            ) { response in
                switch response {
                case .result(let resp):
                    switch resp {
                    case .success(let result):
                        if result.status == .settled {
                            _onTransactionSuccess?(result.json())
                        } else {
                            _onTransactionFailure?(result.json())
                        }
                    case .decline(let result):
                        _onTransactionFailure?(result.json())
                    }
                    
                case .error(let error):
                    _onTransactionFailure?(error.json())
                    
                case .failure(let error):
                    _onTransactionFailure?(["error" : "\(error)"])
                }
            }
        } else {
            _onTransactionFailure?(["error": "Failed to serialize placeholder payment data"])
            log(label: "Bypass Error", object: "JSON serialization failed")
        }
    }
}


// ============================================================================
// MARK: - Apple Pay Delegate (Handles Payment Authorization)
// ============================================================================
/// Internal delegate class that handles Apple Pay authorization callbacks.
/// This class conforms to PKPaymentAuthorizationViewControllerDelegate to
/// receive notifications about payment authorization status.
///
/// CALLBACK SEQUENCE:
/// 1. User authenticates with Face ID/Touch ID
/// 2. didAuthorizePayment is called with encrypted payment token
/// 3. Token is sent to EDFA payment gateway for processing
/// 4. Gateway response determines success or failure
/// 5. didFinish is called when Apple Pay sheet is dismissed
fileprivate class EdfaApplePayDelegate : UIViewController, PKPaymentAuthorizationViewControllerDelegate{
    
    /// Flag to track if payment was authorized or if user cancelled
    private var isPaymentAuthorized = false
    
    /// **STEP 5: PAYMENT AUTHORIZED - PROCESS TRANSACTION**
    /// Called when the user successfully authenticates and authorizes the payment.
    /// This method receives the encrypted payment token from Apple and sends it
    /// to the EDFA payment gateway for processing.
    ///
    /// PROCESS FLOW:
    /// 1. Mark payment as authorized (to distinguish from user cancellation)
    /// 2. Trigger the authentication callback (if set by merchant)
    /// 3. Extract payment token from PKPayment object
    /// 4. Send token to EDFA gateway via startPurchaseApm
    /// 5. Wait for gateway response
    /// 6. Report success/failure to Apple Pay
    /// 7. Trigger merchant's success/failure callback
    /// 8. Apple Pay sheet dismisses automatically
    ///
    /// - Parameters:
    ///   - controller: The Apple Pay authorization view controller
    ///   - payment: PKPayment object containing encrypted payment token
    ///   - completion: Handler to report result back to Apple Pay
    func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        // Flag that payment was authorized (not cancelled)
        isPaymentAuthorized = true
        
        // Notify merchant that authentication completed successfully
        _onAuthentication?(payment)
        
        // Send payment token to EDFA gateway for processing
        startPurchaseApm(payment: payment) { (success, response) in
            // Prepare result to send back to Apple Pay
            let result = PKPaymentAuthorizationResult(
                status: success ? .success : .failure,
                errors: nil
            )
            
            // iOS 16+ allows setting order details in the result
            if #available(iOS 16.0, *) {
                result.orderDetails = nil
            } else {
                // iOS 15 and earlier don't support order details
            }
            
            // Notify merchant of transaction result
            if success{
                _onTransactionSuccess?(response)
            }else{
                _onTransactionFailure?(response)
            }
            
            // Tell Apple Pay that processing is complete
            completion(result)
        }
    }
    
    /// **STEP 6: APPLE PAY SHEET DISMISSED**
    /// Called when the Apple Pay sheet is dismissed (either after authorization
    /// or if the user cancels).
    ///
    /// This method handles the user cancellation scenario. If the payment was
    /// never authorized, it means the user tapped "Cancel" or closed the sheet,
    /// so we notify the merchant via the failure callback.
    ///
    /// - Parameter controller: The Apple Pay authorization view controller
    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        controller.dismiss(animated: true) {
            // Check if user cancelled without authorizing
            if !self.isPaymentAuthorized {
                _onTransactionFailure?(["error": "User cancelled Apple Pay", "cancelled": true])
            }
        }
    }
    
}





// ============================================================================
// MARK: - Payment Processing (Send to EDFA Gateway)
// ============================================================================

/// **STEP 7: SEND PAYMENT TO EDFA GATEWAY**
/// Processes the Apple Pay payment token through the EDFA Payment Gateway.
/// This function extracts payment data from the PKPayment object and sends it
/// to the virtual sale adapter for processing.
///
/// PROCESS:
/// 1. Extract payment token and payment method from PKPayment
/// 2. Serialize payment data to JSON format
/// 3. Create payment request with all required parameters
/// 4. Send to EDFA gateway via virtualSaleAdapter
/// 5. Parse response and determine success/failure
/// 6. Return result via completion callback
///
/// - Parameters:
///   - payment: PKPayment containing encrypted Apple Pay token
///   - completion: Callback with (success: Bool, response: Dictionary)
fileprivate func startPurchaseApm(payment:PKPayment, completion:@escaping ((Bool,[String:Any])->Void)){
    // Extract payment token and method details from Apple Pay
    let token = payment.token
    let method = payment.token.paymentMethod
    
    // Parse the encrypted payment data from Apple Pay token
    if let paymentDataJSON = try? JSONSerialization.jsonObject(with: token.paymentData) as? [String:Any]{
        // Create payment JSON structure with all necessary information
        let paymentJSON:[String : Any] = [
            "paymentData" : paymentDataJSON,        // Encrypted payment token from Apple
            "paymentMethod" : [
                "displayName" : method.displayName ?? "",  // e.g., "Visa 1234"
                "network" : method.network?.rawValue  ?? "",  // e.g., "Visa", "Mastercard"
                "type" : method.type.name(),  // "credit", "debit", "prepaid"
            ],
            "transactionIdentifier" : token.transactionIdentifier  // Unique Apple Pay transaction ID
        ]
        
        // Convert payment JSON to string for transmission
        if let paymentToken = try? JSONSerialization.data(withJSONObject: paymentJSON), let paymentTokenString = String(data: paymentToken, encoding: .utf8){
            
            // Send payment to EDFA gateway for processing
            virtualSaleAdapter.execute(
                brand: "applepay",  // Payment method identifier
                identifier: payment.token.transactionIdentifier,  // Apple Pay transaction ID
                returnUrl: EdfaPgProcessCompleteCallbackUrl,  // Callback URL for async processing
                paymentToken: paymentTokenString,  // Serialized payment token JSON
                order: _order,  // Order details (amount, currency, etc.)
                payer: _payer,  // Customer information
                extras: _extras  // Additional custom data
                
            ) { response in
                // Handle response from payment gateway
                switch response{
                    
                case .result(let resp):
                    // Gateway returned a result (either success or decline)
                    switch resp{
                    case .success(let result):
                        // Transaction was approved by gateway
                        if(result.status == .settled){
                            // Payment is fully settled - success!
                            completion(true, result.json())
                        }else{
                            // Payment approved but not yet settled
                            completion(false, result.json())
                        }
                    case .decline(let result):
                        // Transaction was declined by gateway/bank
                        completion(false, result.json())
                    }
                    
                case .error(let error):
                    // Error occurred during processing
                    completion(false, error.json())
                    
                case .failure(let error):
                    // Network or other failure
                    completion(false, ["error" : "\(error)"])
                }
            }
        }
    }
}

fileprivate func startPurchase(payment:PKPayment, completion:@escaping ((Bool,[String:Any])->Void)){
    
    let requestHash = EdfaPgHashUtil.hashVirtualPurchaseOrder(
        number: _order.id,
        amount:  _order.formatedAmountString(),
        currency: _order.currency,
        description: _order.description
    )
    
    if let _requestHash = requestHash, let applePayVirtualPurchaseData = ApplePayPaymentData(payment: payment, payer: _payer).getData(){
        
        
        let merchant_key = EdfaPgSdk.shared.credentials.clientKey

        let sessionRequestObject = VirtualPurchaseSession(
            hash: _requestHash,
            method: "applepay",
            merchant_key: merchant_key,
            success_url: "https://pay.expresspay.sa",
            cancel_url: "https://pay.expresspay.sa",
            order: _order,
            customer: _payer
        )
        
        createSession(sessionRequest: sessionRequestObject) { token in
            if let token_ = token{
                
                var request = URLRequest(url: URL(string: "https://pay.expresspay.sa/processing/purchase/virtual")!)
                request.httpMethod = "POST"
                request.httpBody = applePayVirtualPurchaseData
                request.allHTTPHeaderFields = [
                    "X-User-Agent": "ios.com.edfapg.sdk",
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                    "Token": token_,
                ]
                
                log(label: "ApplePay Purchase Request", object:"\n\(request)")
                log(label: "ApplePay", object:"purchasing going on...")
                URLSession.shared.dataTask(with: request) { (data, response, error) in
                    printHttp(response: response, request: request, data: data)
                    
                    DispatchQueue.main.async {
                        let resp = EdfaPgDataResponse(data: data, response: response, error: error)
                        if resp.httpOK(), let json = resp.json(){
                            completion(json["result"] as? String == "success", json)
                            log(label: "Success", object:json)
                            return
                        }else if let data = resp.data{
                            let error = String(data:data, encoding:.utf8)
                            completion(false, ["error" : error ?? "Error while performing purchase on '../processing/purchase/virtual'"])
                            log(label: "Error", object:error ?? "Error while performing purchase on '../processing/purchase/virtual'")
                            return
                        }else if error != nil{
                            completion(false, ["error" : error ?? "Error while performing purchase on '../processing/purchase/virtual'"])
                            log(label: "Exception", object: error ?? "Error while performing purchase on '../processing/purchase/virtual'")
                            return
                        }
                        
                        completion(false, ["error" : "Error while performing purchase on '../processing/purchase/virtual'"])
                        log(label: "Error", object: error ?? "Error while performing purchase on '../processing/purchase/virtual'")
                    }
                }.resume()
                
            }else{
                completion(false, ["error" : "Error while create edfapay auth session token for '../purchase'"])
                log(label: "Error", object:"Error while create edfapay auth session token for '../purchase'")
            }
        }
    }else{
        completion(false, ["error" : "Invalid request data"])
        log(label: "Error", object:"Invalid request data")
    }

}




// Initiate Purchase
fileprivate func createSession(sessionRequest:VirtualPurchaseSession, completion:@escaping ((String?)->Void)){
    
    var request = URLRequest(url: URL(string: "https://pay.expresspay.sa/api/v1/session")!)
    request.httpMethod = "POST"
    request.httpBody = sessionRequest.data()
    request.allHTTPHeaderFields = [
        "X-User-Agent": "ios.com.edfapg.sdk",
        "Accept": "application/json",
        "Content-Type": "application/json",
    ]
    
    log(label: "ApplePaySession Request", object:"\n\(request)")
    log(label: "ApplePaySession", object:"Creating auth session for applepay..")
    URLSession.shared.dataTask(with: request) { (data, response, error) in
        printHttp(response: response, request: request, data: data)
        
        DispatchQueue.main.async {
            let resp = EdfaPgDataResponse(data: data, response: response, error: error)
            if resp.httpOK(), let redirect_url = resp.json()?["redirect_url"] as? String,
               let url = URL(string: redirect_url){
                completion(url.lastPathComponent)
                log(label: "SessionToken", object: url.lastPathComponent)
                return
            }else if let data = resp.data{
                let error = String(data:data, encoding:.utf8)
                _onTransactionFailure?(["error" : error ?? "undefined"])
                log(label: "Error", object:error)
            }else if error != nil{
                log(label: "Exception", object:error)
            }
            
            completion(nil)
        }
    }.resume()

}


// ============================================================================
// MARK: - Helper Extensions
// ============================================================================

/// Extension to convert PKPaymentMethodType enum to string representation.
/// This is used when serializing payment information to send to the gateway.
extension PKPaymentMethodType{
    /// Converts payment method type to string name
    /// - Returns: String representation of payment type
    func name() -> String{
        switch(self){
        case .unknown: return "unknown"  // Unknown card type
        case .debit: return "debit"      // Debit card
        case .credit: return "credit"    // Credit card
        case .prepaid: return "prepaid"  // Prepaid card
        case .store: return "store"      // Store card
        case .eMoney: return "eMoney"    // Electronic money
        default: return "unknown"
        }
    }
}

// ============================================================================
// MARK: - Logging Utilities
// ============================================================================

/// Logs debug information when logging is enabled.
/// Supports logging of general objects, HTTP requests, and responses.
///
/// - Parameters:
///   - label: Label/category for the log entry
///   - object: Object to log (can be URLRequest, URLResponse, or any other object)
fileprivate func log(label:String = "", object:Any?){
    if enableLogs{
        if let request  = object as? URLRequest{
            // Format and print HTTP request details
            printHttp(response:nil, request: request, data: request.httpBody)
        }else if let response  = object as? URLResponse{
            // Format and print HTTP response details
            printHttp(response:response, request: nil, data: nil)
        }else{
            // Print general debug information
            debugPrint("[\(label)]:  \(object ?? ". . . ")")
        }
    }
}

/// Formats and prints detailed HTTP request/response information for debugging.
/// Shows URL, headers, parameters, response status, and response body in a
/// structured, readable format.
///
/// - Parameters:
///   - response: HTTP response object (optional)
///   - request: HTTP request object (optional)
///   - data: Response body data (optional)
fileprivate func printHttp(response: URLResponse?, request: URLRequest?, data: Data?) {
    if enableLogs{
        var printString = "\n\n-------------------------------------------------------------\n"
        
        if let urlDataResponse = response as? HTTPURLResponse {
            let statusCode = urlDataResponse.statusCode
            printString += "\(statusCode == 200 ? "SUCCESS" : "ERROR") \(statusCode)\n"
        }
        
        var responceArray: [[String: Any]] = []
        // REQUEST
        if let request = request {
            var requestArray: [[String: Any]] = []
            
            // URL
            requestArray.append(["!!!<URL>!!!": request.url?.absoluteString ?? ""])
            
            // HEADERS
            if let headers = request.allHTTPHeaderFields {
                requestArray.append(["!!!<HEADERS>!!!": headers])
            } else {
                requestArray.append(["!!!<HEADERS>!!!": ["SYSTEM PRINT": "No Headers"]])
            }
            
            // PARAMETERS
            if let httpBody = request.httpBody {
                if let stringBody = String(data: httpBody, encoding: .utf8) {
                    let formatedBody = stringBody.components(separatedBy: "&").map { $0.replacingOccurrences(of: "=", with: ": ") }
                    requestArray.append(["!!!<PARAMETERS>!!!": formatedBody])
                    
                } else {
                    requestArray.append(["!!!<PARAMETERS>!!!": ["SYSTEM PRINT": "No parameters"]])
                }
            }
            
            responceArray.append(["!!!<REQUEST>!!!": requestArray])
        } else {
            responceArray.append(["!!!<REQUEST>!!!": [["SYSTEM PRINT": "No Request"]]])
        }
        
        // RESPONSE
        do {
            if let data = data {
                let temDictData = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                responceArray.append(["!!!<RESPONSE>!!!": temDictData])
            } else {
                responceArray.append(["!!!<RESPONSE>!!!": ["SYSTEM PRINT": "No Data"]])
            }
            
        } catch {
            responceArray.append(["!!!<RESPONSE>!!!": ["SYSTEM PRINT": "Throw error: \(error)"]])
        }
        
        // Print
        do {
            var httpMethod = request?.httpMethod ?? ""
            if !httpMethod.isEmpty {
                httpMethod += "\n"
            }
            
            let data = try JSONSerialization.data(withJSONObject: ["!!!<RESTAPIMANAGER>!!!": responceArray], options: .prettyPrinted)
            var responceString = String.init(data: data, encoding: .utf8) ?? ""
            responceString = responceString.replacingOccurrences(of: "\"!!!<RESTAPIMANAGER>!!!\" :", with: "")
            responceString = responceString.replacingOccurrences(of: "{\n   [\n    {\n      \"!!!<REQUEST>!!!\" : ", with: "\n\(httpMethod)REQUEST:")
            responceString = responceString.replacingOccurrences(of: "[\n        {\n          \"!!!<URL>!!!\" : ", with: "\n\tURL: \n\t\t  ")
            responceString = responceString.replacingOccurrences(of: "        },\n        {\n          \"!!!<HEADERS>!!!\" : ", with: "\tHEADERS: \n\t\t  ")
            responceString = responceString.replacingOccurrences(of: "\n        },\n        {\n          \"!!!<PARAMETERS>!!!\" : ", with: "\n\tPARAMETERS:\n\t\t  ")
            responceString = responceString.replacingOccurrences(of: "\n        }\n      ]\n    },\n    {\n      \"!!!<RESPONSE>!!!\" : ", with: "\nRESPONSE:\n\t  ")
            responceString = responceString.replacingOccurrences(of: "\\/", with: "/")
            if responceString.count > 12 {
                responceString.removeLast(12) // "\n    }\n  ]\n}"
            }
            
            if responceString.isEmpty {
                responceString = "Can't create string from responce"
            }
            
            printString += responceString + "\n"
        } catch {
            printString += "ERROR PRINTING RESPONCE\n"
        }
        
        printString += "-------------------------------------------------------------\n\n"
        
        print(printString)

    }
}


// ============================================================================
// MARK: - Adapter Delegate Implementation
// ============================================================================
/// Implements EdfaPgAdapterDelegate protocol to receive callbacks from the
/// virtual sale adapter. These methods allow monitoring of HTTP requests
/// and responses during payment processing.
extension EdfaApplePay{
    
    /// Called before an HTTP request is sent to the payment gateway.
    /// Can be used for logging or modifying requests.
    ///
    /// - Parameter request: The request about to be sent
    public func willSendRequest(_ request: EdfaPgDataRequest) {
        // Currently not implemented - can be used for request monitoring
    }
    
    /// Called after an HTTP response is received from the payment gateway.
    /// Can be used for logging or analyzing responses.
    ///
    /// - Parameter reponse: The response received from the gateway
    public func didReceiveResponse(_ reponse: EdfaPgDataResponse?) {
        // Currently not implemented - can be used for response monitoring
    }
}
