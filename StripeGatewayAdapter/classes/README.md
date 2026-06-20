# Stripe Gateway Adapter (reference)

Reference implementation of `commercepayments.PaymentGatewayAdapter` and `commercepayments.PaymentGatewayAsyncAdapter` for the Stripe API.

These classes are intended for **Commerce Payments API version 230+** (confirm against your org’s package release notes).

## What this sample includes

- **Synchronous flows**: authorize, capture, sale, referenced refund, tokenize (card and bank), authorization reversal (PaymentIntent cancel).
- **Webhooks**: `processNotification` handling for `payment_intent.succeeded` / `payment_intent.payment_failed` with automatic capture (`capture_method = automatic`).
- **Helpers**: currency conversion for Stripe’s smallest unit, form-encoded POSTs via `commercepayments.PaymentsHttp`, basic decline-code mapping.

## Prerequisites (not shipped in this repo)

- **Named Credential / Payments connection** configured for Stripe (`PaymentsHttp` resolves the base URL and secrets).
- **Remote Site / Named Credential** permissions as required by your org.
- Stripe API version and objects aligned with your integration (PaymentIntents, Charges, Refunds, SetupIntents, Customers, Payment Methods).

## Deployment / compile order

1. `QueryUtils.apex`
2. `StripeHttpUtil.apex`
3. `StripeValidationException.apex`
4. `StripeAdapter.apex`

## Public vs. internal fork

For a **public** reference repository:

- Prefer **clear documentation** at class and method level over internal-only comments.
- **Remove** QA-only branches, hard-coded URLs used only for testing, and verbose `System.debug` logging.
- **Avoid** QA-only branches, hard-coded URLs used only for testing, and verbose `System.debug` logging.
- **`QueryUtils`** is included here for dynamic SOQL; ensure field API names match your org (e.g. `SavedPaymentMethod.type`).
- **Splitting** the adapter (see root `README.md` and Payeezy folder) is optional; see discussion in the pull request.

## Security and compliance

Payment integrations are sensitive. Review Stripe’s documentation for PCI, webhooks (signature verification), and idempotency. This sample is illustrative and must be hardened for production.
