# Apple Pay Bypass Mode - Usage Guide

## Overview
The Apple Pay bypass mode allows you to skip the actual Apple Pay payment sheet and send custom placeholder data directly to the EDFA Payment Gateway. This is useful for:
- Testing without Apple Pay setup
- Development and debugging
- Sending custom payment data structures

## ⚠️ Warning
**This bypasses real Apple Pay payment processing. Only use for testing or custom scenarios.**

---

## Basic Usage

### 1. Enable Bypass Mode (Simple)
```swift
EdfaApplePay()
    .set(applePayMerchantID: "merchant.com.yourcompany.app")  // Optional in bypass mode
    .set(order: order)
    .set(payer: payer)
    .enableBypassMode(true)  // <-- Enable bypass mode
    .on(transactionSuccess: { result in
        print("Payment successful: \(result)")
    })
    .on(transactionFailure: { error in
        print("Payment failed: \(error)")
    })
    .initialize(target: self, onError: { errors in
        print("Setup error: \(errors)")
    }, onPresent: nil)
```

### 2. Enable Bypass Mode with Custom Transaction ID
```swift
EdfaApplePay()
    .set(order: order)
    .set(payer: payer)
    .enableBypassMode(true)
    .setPlaceholderTransactionId("MY_CUSTOM_TXN_123456")  // <-- Custom transaction ID
    .on(transactionSuccess: { result in
        print("Success: \(result)")
    })
    .on(transactionFailure: { error in
        print("Failed: \(error)")
    })
    .initialize(target: self, onError: { _ in }, onPresent: nil)
```

### 3. Enable Bypass Mode with Full Custom Data
```swift
// Create your custom payment data structure
let customPaymentData: [String: Any] = [
    "transactionIdentifier": "CUSTOM_TXN_789",
    "paymentData": [
        "version": "EC_v1",
        "data": "YOUR_ENCRYPTED_DATA_HERE",
        "signature": "YOUR_SIGNATURE_HERE",
        "header": [
            "ephemeralPublicKey": "YOUR_PUBLIC_KEY",
            "publicKeyHash": "YOUR_KEY_HASH",
            "transactionId": "YOUR_TRANSACTION_ID"
        ]
    ],
    "paymentMethod": [
        "displayName": "Test Visa •••• 4242",
        "network": "Visa",
        "type": "credit"
    ]
]

EdfaApplePay()
    .set(order: order)
    .set(payer: payer)
    .enableBypassMode(true)
    .setPlaceholderPaymentData(customPaymentData)  // <-- Your custom data
    .on(transactionSuccess: { result in
        print("Success: \(result)")
    })
    .on(transactionFailure: { error in
        print("Failed: \(error)")
    })
    .initialize(target: self, onError: { _ in }, onPresent: nil)
```

---

## Default Placeholder Data Structure

When bypass mode is enabled without custom data, this is the default structure sent:

```json
{
    "transactionIdentifier": "BYPASS_TXN_<UUID>",
    "paymentData": {
        "version": "EC_v1",
        "data": "PLACEHOLDER_ENCRYPTED_DATA",
        "signature": "PLACEHOLDER_SIGNATURE",
        "header": {
            "ephemeralPublicKey": "PLACEHOLDER_PUBLIC_KEY",
            "publicKeyHash": "PLACEHOLDER_KEY_HASH",
            "transactionId": "PLACEHOLDER_TRANSACTION_ID"
        }
    },
    "paymentMethod": {
        "displayName": "Test Card 1234",
        "network": "Visa",
        "type": "credit"
    }
}
```

---

## Customization Options

### Modify Individual Fields

You can modify the default placeholder data before sending:

```swift
var customData = placeholderPaymentData
customData["transactionIdentifier"] = "MY_TXN_001"

if var paymentMethod = customData["paymentMethod"] as? [String: Any] {
    paymentMethod["displayName"] = "Custom Test Card •••• 9999"
    paymentMethod["network"] = "Mastercard"
    paymentMethod["type"] = "debit"
    customData["paymentMethod"] = paymentMethod
}

EdfaApplePay()
    .enableBypassMode(true)
    .setPlaceholderPaymentData(customData)
    // ... rest of configuration
```

### Enable Logging to See Payload

Enable logging to see exactly what data is being sent:

```swift
EdfaApplePay()
    .enableBypassMode(true)
    .enable(logs: true)  // <-- See bypass mode logs
    .set(order: order)
    .set(payer: payer)
    // ... rest of configuration
```

Logs will show:
- `[BYPASS MODE]` - When bypass mode is activated
- `[BYPASS PAYMENT]` - The placeholder data being used
- `[BYPASS PAYLOAD]` - The JSON being sent to gateway

---

## What Gets Bypassed

When bypass mode is enabled:
- ❌ No Apple Pay sheet is shown
- ❌ No Face ID/Touch ID authentication
- ❌ No real payment token from Apple
- ❌ No merchant ID validation required
- ✅ Placeholder data is sent directly to EDFA gateway
- ✅ All callbacks work normally (success/failure)
- ✅ Same adapter and processing flow

---

## Validation in Bypass Mode

Bypass mode has **reduced validation** (compared to normal Apple Pay):
- ✅ Requires: `onTransactionSuccess` callback
- ✅ Requires: `onTransactionFailure` callback
- ✅ Requires: Order amount >= 0.10
- ❌ Does NOT require: Apple Pay merchant ID
- ❌ Does NOT require: Currency code
- ❌ Does NOT require: Country code

---

## Testing Flow

### Test the Gateway Response

```swift
class MyViewController: UIViewController {
    
    func testBypassMode() {
        let order = EdfaPgSaleOrder()
        order.amount = 10.00
        order.currency = "SAR"
        order.description = "Test Order"
        order.id = "TEST_001"
        
        let payer = EdfaPgPayer()
        payer.firstName = "Test"
        payer.lastName = "User"
        payer.email = "test@example.com"
        
        EdfaApplePay()
            .set(order: order)
            .set(payer: payer)
            .enableBypassMode(true)
            .setPlaceholderTransactionId("TEST_\(Date().timeIntervalSince1970)")
            .enable(logs: true)
            .on(transactionSuccess: { [weak self] result in
                print("✅ SUCCESS:", result ?? [:])
                self?.handleSuccess(result)
            })
            .on(transactionFailure: { [weak self] error in
                print("❌ FAILURE:", error)
                self?.handleFailure(error)
            })
            .initialize(
                target: self,
                onError: { errors in
                    print("⚠️ ERROR:", errors)
                },
                onPresent: {
                    print("📱 Payment processing...")
                }
            )
    }
    
    func handleSuccess(_ result: [String: Any]?) {
        // Handle successful test transaction
    }
    
    func handleFailure(_ error: [String: Any]) {
        // Handle failed test transaction
    }
}
```

---

## Switching Between Modes

You can easily switch between normal and bypass mode:

```swift
let useBypassMode = true  // Toggle this

EdfaApplePay()
    .set(applePayMerchantID: "merchant.com.app")
    .set(order: order)
    .set(payer: payer)
    .enableBypassMode(useBypassMode)  // <-- Dynamic toggle
    .on(transactionSuccess: { _ in })
    .on(transactionFailure: { _ in })
    .initialize(target: self, onError: { _ in }, onPresent: nil)
```

---

## Important Notes

1. **Gateway Validation**: The EDFA gateway will still validate the payment data. Placeholder data may be rejected depending on gateway configuration.

2. **Production Use**: Never enable bypass mode in production unless you have a specific business case for sending custom payment structures.

3. **Transaction ID**: The transaction identifier should be unique for each payment attempt.

4. **Data Format**: The placeholder data structure should match what the EDFA gateway expects for Apple Pay tokens.

5. **Testing**: Use bypass mode for integration testing, UI testing, or when Apple Pay setup is not available.

---

## Example: Multiple Test Scenarios

```swift
enum TestScenario {
    case success
    case decline
    case invalidData
}

func testScenario(_ scenario: TestScenario) {
    var txnId: String
    
    switch scenario {
    case .success:
        txnId = "SUCCESS_TEST_\(UUID())"
    case .decline:
        txnId = "DECLINE_TEST_\(UUID())"
    case .invalidData:
        txnId = "INVALID_\(UUID())"
    }
    
    EdfaApplePay()
        .set(order: order)
        .set(payer: payer)
        .enableBypassMode(true)
        .setPlaceholderTransactionId(txnId)
        .enable(logs: true)
        .on(transactionSuccess: { print("✅", $0 ?? [:]) })
        .on(transactionFailure: { print("❌", $0) })
        .initialize(target: self, onError: { print("⚠️", $0) }, onPresent: nil)
}
```

---

## API Reference

### New Methods

#### `enableBypassMode(_ bypass: Bool) -> EdfaApplePay`
Enables or disables bypass mode.

#### `setPlaceholderPaymentData(_ data: [String: Any]) -> EdfaApplePay`
Sets custom placeholder payment data structure.

#### `setPlaceholderTransactionId(_ identifier: String) -> EdfaApplePay`
Sets just the transaction identifier (convenience method).

---

## Questions?

If you need to customize the data structure further or have questions about what the gateway expects, check the EDFA Payment Gateway documentation or contact support.
