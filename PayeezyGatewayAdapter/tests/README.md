# Payeezy Gateway Adapter apex classes

These are files that tests the payeezy gateway adapter.
Add these classes along with adapter classes to achieve 75% code coverage in the package.
These classes work on release version 230 and above

## Deployment

The classes need to be compiled in this order:

```
1. PaymentCalloutMock.apex
2. PaymentCalloutFailureMock.apex
3. PaymentCalloutHighLevelErrorMock.apex
4. PaymentCalloutResponseParseFailureMock.apex
5. PayeezyGatewayAdapterTest.apex
```
