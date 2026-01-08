//
//  EdfaApplePay.swift
//  Sample
//
//  Created by Zohaib Kambrani on 23/01/2023.
//

import Foundation
import PassKit

// Logging callback type that can be set from React Native
public typealias EdfaApplePayLogCallback = (String, String) -> Void

public class EdfaPgShippingAddress{
    var name:String?
    var address:String?
    var email:String?
    var phone:String?
    
    init(name:String?, address:String?, email:String?, phone:String?) {
        self.name  = name
        self.address  = address
        self.email  = email
        self.phone  = phone
    }

}

fileprivate var _onAuthentication:((PKPayment) -> Void)?
fileprivate var _onTransactionSuccess:(([String:Any]?) -> Void)?
fileprivate var _onTransactionFailure:(([String:Any]) -> Void)?
fileprivate var _onError:(([String]) -> Void)!

fileprivate var _payer:EdfaPgPayer!
fileprivate var _order:EdfaPgSaleOrder!
fileprivate var _extras:[Extra] = []

fileprivate var enableLogs:Bool = false
fileprivate var _logCallback:EdfaApplePayLogCallback?

fileprivate let virtualSaleAdapter = EdfaPgVirtualSaleAdapter()
public class EdfaApplePay : EdfaPgAdapterDelegate{
    
    
    public init() {
        virtualSaleAdapter.delegate = self
        log(label: "Init", object: "EdfaApplePay initialized")
    }
    
    private let request = PKPaymentRequest()
    private var purchaseItems:[PKPaymentSummaryItem] = []
    
    private var applePayMerchantID:String?
    private var shippingAddress:EdfaPgShippingAddress?
    private var supportedPaymentNetworks:[PKPaymentNetwork] = []
    private var merchantCapability:PKMerchantCapability = PKMerchantCapability.capability3DS
    
    
    
    private func start(target:UIViewController, onError:@escaping ((Any) -> Void), onPresent:(() ->Void)?){
        log(label: "Start", object: "Starting Apple Pay flow")
        _onError = onError
        
        log(label: "ApplePaySupport", object: "Checking if Apple Pay is supported")
        if isApplePaySupported(){
            log(label: "ApplePaySupport", object: "Apple Pay is supported on this device")
            log(label: "Validation", object: "Validating payment configuration")
            let validation = validate()
            if validation.valid{
                log(label: "Validation", object: "Payment configuration is valid")
                log(label: "Validation", object: "Payment configuration is valid")
                
                log(label: "PreparePayment", object: "Preparing payment request")
                let request = preparePayment(request:PKPaymentRequest())
                log(label: "PreparePayment", object: "Payment request prepared successfully")
                log(label: "PreparePayment", object: "Payment request prepared successfully")
                
                log(label: "Controller", object: "Initializing PKPaymentAuthorizationViewController")
                if let applePayController = PKPaymentAuthorizationViewController(paymentRequest: request){
                    log(label: "Controller", object: "PKPaymentAuthorizationViewController initialized successfully")
                    applePayController.delegate = prepareDelegate(target: target, edfaApplePay: self)
                    log(label: "Present", object: "Presenting Apple Pay controller")
                    target.present(applePayController, animated: true, completion: onPresent)
                }else{
                    log(label: "Error", object: "Failed to initialize PKPaymentAuthorizationViewController")
                    _onError?(["Error initializing 'PKPaymentAuthorizationViewController(paymentRequest:)'"])
                    log(label: "Error", object:"Error initializing 'PKPaymentAuthorizationViewController(paymentRequest:)'")
                }
                
            }else{
                log(label: "ValidationError", object: "Validation failed with errors: \(validation.validationErrors)")
                _onError?(validation.validationErrors)
                log(label: "Error", object:"Error initializing 'PKPaymentAuthorizationViewController(paymentRequest:)'")

            }

            return
        }
        
        log(label: "ApplePaySupport", object: "Apple Pay is NOT supported on this device")
        
        if supportedPaymentNetworks.isEmpty{
            log(label: "Error", object: "No supported payment networks configured")
            _onError?(["Cannot start apple pay, device may not supported or user/merchant is restricted from authorizing payments"])
            log(label: "Error", object:"Cannot start apple pay, device may not supported or user/merchant is restricted from authorizing payments")

        }else{
            _onError?(["Cannot start apple pay with your defined supported payment networks"])
            log(label: "Error", object:"Cannot start apple pay with your defined supported payment networks")
        }
    }
    
    func isApplePaySupported() -> Bool{
        log(label: "isApplePaySupported", object: "Checking Apple Pay support")
        if supportedPaymentNetworks.isEmpty{
            let canMakePayments = PKPaymentAuthorizationViewController.canMakePayments()
            log(label: "isApplePaySupported", object: "Can make payments (no specific networks): \(canMakePayments)")
            return canMakePayments
        }
        
        let canMakePayments = PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: supportedPaymentNetworks)
        log(label: "isApplePaySupported", object: "Can make payments with networks \(supportedPaymentNetworks.map { $0.rawValue }): \(canMakePayments)")
        return canMakePayments
    }
    
    private func preparePayment(request:PKPaymentRequest) -> PKPaymentRequest{
        log(label: "preparePayment", object: "Setting merchant identifier: \(applePayMerchantID ?? "nil")")
        request.merchantIdentifier = applePayMerchantID!
        request.merchantCapabilities = merchantCapability
        
        log(label: "preparePayment", object: "Setting country: \(_order.country), currency: \(_order.currency)")
        request.countryCode = _order.country
        request.currencyCode = _order.currency
        
        request.paymentSummaryItems = purchaseItems
        if purchaseItems.isEmpty{
            log(label: "preparePayment", object: "No purchase items, creating default item with amount: \(_order.amount)")
            log(label: "preparePayment", object: "No purchase items, creating default item with amount: \(_order.amount)")
            let label = (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? _order.description
            request.paymentSummaryItems = [
                PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(value: _order.amount), type: .final)
            ]
            log(label: "preparePayment", object: "Created payment item: \(label)")
        } else {
            log(label: "preparePayment", object: "Using \(purchaseItems.count) purchase items")
        }
        request.supportedNetworks = supportedPaymentNetworks
        if supportedPaymentNetworks.isEmpty{
            log(label: "preparePayment", object: "No specific networks defined, using all available networks")
            log(label: "preparePayment", object: "No specific networks defined, using all available networks")
            request.supportedNetworks = PKPaymentRequest.availableNetworks()
            log(label: "preparePayment", object: "Available networks: \(request.supportedNetworks.map { $0.rawValue })")
        } else {
            log(label: "preparePayment", object: "Using configured networks: \(supportedPaymentNetworks.map { $0.rawValue })")
        }
        
        log(label: "preparePayment", object: "Payment request fully prepared")
        return request
    }
    
    private func prepareDelegate(target:UIViewController, edfaApplePay:EdfaApplePay) -> EdfaApplePayDelegate{
        log(label: "prepareDelegate", object: "Creating EdfaApplePayDelegate")
        let delegate = EdfaApplePayDelegate()
        // Required to PKPaymentAuthorizationViewControllerDelegate to work (should be implemented by UIViewController)
        // * done due to provide the very coding efforts to customer to start applepay in thier application *
        delegate.view.isHidden = true
        target.addChild(delegate)
        log(label: "prepareDelegate", object: "Delegate created and added to target view controller")
        
        return delegate
    }
}


// Payment Properties Setters
extension EdfaApplePay{
    
    public func initialize(target:UIViewController, onError:@escaping ((Any) -> Void), onPresent:(() ->Void)?){
        log(label: "initialize", object: "Initializing Apple Pay with target view controller")
        start(target: target, onError: onError, onPresent: onPresent)
    }
    
    public func setLogCallback(_ callback: @escaping EdfaApplePayLogCallback) -> EdfaApplePay {
        _logCallback = callback
        log(label: "setLogCallback", object: "Log callback has been set")
        return self
    }
    
    public func on(authentication:@escaping ((PKPayment) -> Void)) -> EdfaApplePay{
        log(label: "on.authentication", object: "Authentication callback registered")
        _onAuthentication = authentication
        return self
    }
    
    public func on(transactionSuccess:@escaping (([String:Any]?) -> Void)) -> EdfaApplePay{
        log(label: "on.transactionSuccess", object: "Transaction success callback registered")
        _onTransactionSuccess = transactionSuccess
        return self
    }
    
    public func on(transactionFailure:@escaping (([String:Any]) -> Void)) -> EdfaApplePay{
        log(label: "on.transactionFailure", object: "Transaction failure callback registered")
        _onTransactionFailure = transactionFailure
        return self
    }
    
    public func set(applePayMerchantID:String) -> EdfaApplePay{
        log(label: "set.applePayMerchantID", object: "Setting merchant ID: \(applePayMerchantID)")
        self.applePayMerchantID = applePayMerchantID
        return self
    }
    
    public func set(payer:EdfaPgPayer) -> EdfaApplePay{
        log(label: "set.payer", object: "Setting payer information")
        _payer = payer
        return self
    }
    
    public func set(order:EdfaPgSaleOrder) -> EdfaApplePay{
        log(label: "set.order", object: "Setting order - ID: \(order.id), Amount: \(order.amount), Currency: \(order.currency)")
        _order = order
        return self
    }
    
    
    public func set(extras:[Extra]) -> EdfaApplePay{
        log(label: "set.extras", object: "Setting \(extras.count) extra parameters")
        _extras = extras
        return self
    }
    
    
    public func set(shippingAddress:EdfaPgShippingAddress) -> EdfaApplePay{
        log(label: "set.shippingAddress", object: "Setting shipping address")
        self.shippingAddress = shippingAddress
        return self
    }
    
    public func set(merchantCapability:PKMerchantCapability) -> EdfaApplePay{
        log(label: "set.merchantCapability", object: "Setting merchant capability")
        self.merchantCapability = merchantCapability
        return self
    }
    
    public func addSupported(paymentNetworks:[PKPaymentNetwork]) -> EdfaApplePay{
        log(label: "addSupported.paymentNetworks", object: "Adding supported networks: \(paymentNetworks.map { $0.rawValue })")
        self.supportedPaymentNetworks = paymentNetworks
        return self
    }
    
    public func addPurchaseItem(label:String, amount:Double, type:PKPaymentSummaryItemType) -> EdfaApplePay{
        log(label: "addPurchaseItem", object: "Adding purchase item - Label: \(label), Amount: \(amount)")
        purchaseItems.append(PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(value: amount), type: type))
        return self
    }
    
    public func enable(logs:Bool) -> EdfaApplePay{
        log(label: "enable.logs", object: "Setting logs enabled: \(logs)")
        enableLogs = logs
        return self
    }
}


// Payment Properties Validator
private extension EdfaApplePay{
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
}


fileprivate class EdfaApplePayDelegate : UIViewController, PKPaymentAuthorizationViewControllerDelegate{
    
    private var isPaymentAuthorized = false
    
    func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        log(label: "Delegate.didAuthorizePayment", object: "Payment authorized by user")
        isPaymentAuthorized = true
        log(label: "Delegate.callback", object: "Calling authentication callback")
        _onAuthentication?(payment)
        log(label: "Delegate.startPurchase", object: "Starting purchase APM flow")
        log(label: "Delegate.startPurchase", object: "Starting purchase APM flow")
        startPurchaseApm(payment: payment) { (success, response) in
            log(label: "Delegate.purchaseResult", object: "Purchase completed with success: \(success)")
            let result = PKPaymentAuthorizationResult(
                status: success ? .success : .failure,
                errors: nil
            )
            
            if #available(iOS 16.0, *) {
                result.orderDetails = nil
            } else {
                
            }
            
            if success{
                log(label: "Delegate.success", object: "Calling transaction success callback")
                _onTransactionSuccess?(response)
            }else{
                log(label: "Delegate.failure", object: "Calling transaction failure callback with response: \(response)")
                _onTransactionFailure?(response)
            }
            log(label: "Delegate.completion", object: "Completing payment authorization")
            completion(result)
        }
    }
    
    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        log(label: "Delegate.didFinish", object: "Payment authorization view controller finished")
        controller.dismiss(animated: true) {
            // If the payment was never authorized, it means the user cancelled
            if !self.isPaymentAuthorized {
                log(label: "Delegate.cancelled", object: "User cancelled Apple Pay - payment was not authorized")
                _onTransactionFailure?(["error": "User cancelled Apple Pay", "cancelled": true])
            } else {
                log(label: "Delegate.dismissed", object: "Payment controller dismissed after authorization")
            }
        }
    }
    
}





// Initiate Purchase
fileprivate func startPurchaseApm(payment:PKPayment, completion:@escaping ((Bool,[String:Any])->Void)){
    log(label: "startPurchaseApm", object: "Starting APM purchase")
    let token = payment.token
    let method = payment.token.paymentMethod
    
    log(label: "startPurchaseApm", object: "Serializing payment data")
    // log token as json
    log(label: "startPurchaseApm.token", object: token)
    if let paymentDataJSON = try? JSONSerialization.jsonObject(with: token.paymentData) as? [String:Any]{
        log(label: "startPurchaseApm", object: "Payment data serialized successfully")
        let paymentJSON:[String : Any] = [
            "paymentData" : paymentDataJSON,
            "paymentMethod" : [
                "displayName" : method.displayName ?? "",
                "network" : method.network?.rawValue  ?? "",
                "type" : method.type.name(),
            ],
            "transactionIdentifier" : token.transactionIdentifier
        ]
        log(label: "startPurchaseApm", object: "Payment JSON created with transaction ID: \(token.transactionIdentifier)")
        if let paymentToken = try? JSONSerialization.data(withJSONObject: paymentJSON), let paymentTokenString = String(data: paymentToken, encoding: .utf8){
            log(label: "startPurchaseApm", object: "Payment token created, executing virtual sale adapter")
            
            virtualSaleAdapter.execute(
                brand: "applepay",
                identifier: payment.token.transactionIdentifier,
                returnUrl: EdfaPgProcessCompleteCallbackUrl,
                paymentToken: paymentTokenString,
                order: _order,
                payer: _payer,
                extras: _extras
                
            ) { response in
                log(label: "startPurchaseApm.response", object: "Received response from virtual sale adapter")
                switch response{
                    
                case .result(let resp):
                    log(label: "startPurchaseApm.result", object: "Received result response")
                    switch resp{
                    case .success(let result):
                        log(label: "startPurchaseApm.success", object: "Transaction success with status: \(result.status)")
                        if(result.status == .settled){
                            log(label: "startPurchaseApm.settled", object: "Transaction settled successfully")
                            completion(true, result.json())
                        }else{
                            log(label: "startPurchaseApm.notSettled", object: "Transaction not settled, status: \(result.status)")
                            completion(false, result.json())
                        }
                    case .decline(let result):
                        log(label: "startPurchaseApm.decline", object: "Transaction declined")
                        completion(false, result.json())
                    }
                    
                case .error(let error):
                    log(label: "startPurchaseApm.error", object: "Error response: \(error.json())")
                    completion(false, error.json())
                    
                case .failure(let error):
                    log(label: "startPurchaseApm.failure", object: "Failure: \(error)")
                    completion(false, ["error" : "\(error)"])
                }
            }
        } else {
            log(label: "startPurchaseApm.error", object: "Failed to create payment token string from JSON")
            completion(false, ["error": "Failed to create payment token"])
        }
    } else {
        log(label: "startPurchaseApm.error", object: "Failed to serialize payment data to JSON")
        completion(false, ["error": "Failed to serialize payment data"])
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


extension PKPaymentMethodType{
    func name() -> String{
        switch(self){
        case .unknown: return "unknown"
        case .debit: return "debit"
        case .credit: return "credit"
        case .prepaid: return "prepaid"
        case .store: return "store"
        case .eMoney: return "eMoney"
        default: return "unknown"
        }
    }
}

fileprivate func log(label:String = "", object:Any?){
    let message: String
    
    if let request = object as? URLRequest {
        message = formatHttpRequest(request: request, data: request.httpBody)
    } else if let response = object as? URLResponse {
        message = formatHttpResponse(response: response)
    } else {
        message = "\(object ?? ". . . ")"
    }
    
    // Always call the callback if it's set
    if let callback = _logCallback {
        callback(label, message)
    }
    
    // Also print to console if logs are enabled
    if enableLogs {
        debugPrint("[\(label)]: \(message)")
    }
}

fileprivate func formatHttpRequest(request: URLRequest, data: Data?) -> String {
    var result = "\n[HTTP Request]\n"
    result += "URL: \(request.url?.absoluteString ?? "N/A")\n"
    result += "Method: \(request.httpMethod ?? "N/A")\n"
    if let headers = request.allHTTPHeaderFields {
        result += "Headers: \(headers)\n"
    }
    if let data = data, let body = String(data: data, encoding: .utf8) {
        result += "Body: \(body)"
    }
    return result
}

fileprivate func formatHttpResponse(response: URLResponse) -> String {
    var result = "\n[HTTP Response]\n"
    if let httpResponse = response as? HTTPURLResponse {
        result += "Status Code: \(httpResponse.statusCode)\n"
        result += "Headers: \(httpResponse.allHeaderFields)"
    }
    return result
}

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


extension EdfaApplePay{
    
    public func willSendRequest(_ request: EdfaPgDataRequest) {
        
    }
    
    public func didReceiveResponse(_ reponse: EdfaPgDataResponse?) {
        
    }
}
