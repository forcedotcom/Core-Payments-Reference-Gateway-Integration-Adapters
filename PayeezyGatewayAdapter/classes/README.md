# Payeezy Gateway Adapter apex classes

These are the files for the implementation of gateway adapter for payeezy payment gateway.
These classes work on release version 230 and above.

## Deployment

The classes need to be compiled in this order:

```
1. PayeezyValidationException.apex
2. DaoService.apex
3. AbstractTransactionService.apex
4. AuthorizationTransactionService.apex
5. CaptureTransactionService.apex
6. ReferencedRefundTransactionService.apex
7. SaleTransactionService.apex
8. TokenizeTransactionService.apex
9. AuthReversalTransactionService.apex
10. TransactionServiceAdapter.apex
11. PayeezyGatewayAdapter.apex
```
