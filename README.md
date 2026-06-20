# Core-Payments-Reference-Gateway-Integration-Adapter
  
This repository contains reference implementations for different gateways along with one dummy implementation called Salesforce adapter. This code works with release version 230 and above.

Additional adapters:

- **`PayeezyGatewayAdapter/`** — Payeezy gateway sample using service classes per transaction type.
- **`StripeGatewayAdapter/`** — Stripe PaymentIntents / Charges–oriented sample including async webhook handling (`PaymentGatewayAsyncAdapter`).
- **`SalesforceAdapter/`** — Dummy adapter that does not call an external gateway.
