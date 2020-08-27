/**
 * Test class for New Payeezy Gateway Adapter
 * This class is used for re-factored reference implementation of PayeezyGatewayAdapter.
 * When testing the reference adapter as a package 75% code coverage is required before the adapter can be packaged.
 * This class is the entry point to provide that.
 * @author mranjan
 * @since 226
 */ 
@isTest
public class PayeezyGatewayAdapterTest {

    public static testmethod void testAuthRequest() {
        //Create a PaymentMethod instance
        commercepayments.AuthApiPaymentMethodRequest paymentMethod = createAuthPaymentMethodRequest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutMock());
        //Create an auth request
        commercepayments.AuthorizationRequest authRequest = new commercepayments.AuthorizationRequest(80);
        authRequest.paymentMethod = paymentMethod;
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(authRequest, commercepayments.RequestType.Authorize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse authResponse = adapter.processRequest(p);
        system.assert(authResponse instanceOf commercepayments.AuthorizationResponse, 'Response is not a valid Authorization response');
        
    }
    
    public static testmethod void testAuthValidationExceptionRequest() {
        //Create Address request
        commercepayments.AddressRequest address = new commercepayments.AddressRequest('test', 'test', 'test', 'test', 'test');
        
         // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutMock());
        //Create an auth request
        commercepayments.AuthorizationRequest authRequest = new commercepayments.AuthorizationRequest(80);
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(authRequest, commercepayments.RequestType.Authorize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse authResponse = adapter.processRequest(p);
        system.debug('authResponse '+authResponse.toString());
        system.assert(authResponse instanceOf commercepayments.GatewayErrorResponse, 'Response is not a valid Authorization response');
        
    }
    
    public static testmethod void testCaptureRequest() {
        PaymentAuthorization auth = initializeAuthObject();
        insert auth;
        //Dmls and http request can't be performed in a single transaction in apex
        //segreagating the transaction by starting a test context
        Test.startTest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutMock());
        //Create an capture request
        commercepayments.CaptureRequest captureRequest = new commercepayments.CaptureRequest(80, auth.id);
        
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(captureRequest, commercepayments.RequestType.capture);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse captureResponse = adapter.processRequest(p);
        system.assert(captureResponse instanceOf commercepayments.CaptureResponse, 'Response is not a valid Capture response');
        Test.stopTest();
    }
    
    public static testmethod void testReferencedRefundRequest() {
        Payment pmt = initializePaymentObject();
        insert pmt;
        //Dmls and http request can't be performed in a single transaction in apex
        //segreagating the transaction by starting a test context
        Test.startTest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutMock());
        //Create an capture request
        commercepayments.ReferencedRefundRequest refundRequest = new commercepayments.ReferencedRefundRequest(80, pmt.id);
        
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(refundRequest, commercepayments.RequestType.referencedrefund);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse refundResponse = adapter.processRequest(p);
        system.assert(refundResponse instanceOf commercepayments.ReferencedRefundResponse, 'Response is not a valid Refund response');
        Test.stopTest();
    }
    
    
    
    /**
     * Uses PaymentCalloutHighLevelErrorMock to simulate a throttling error. 
     */
    public static testmethod void testAuthFailureHighLevelErrorRequest() {
        //Create a PaymentMethod instance
        commercepayments.AuthApiPaymentMethodRequest paymentMethod = createAuthPaymentMethodRequest();
        // Set mock callout class
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutHighLevelErrorMock());
        //Create an auth request
        commercepayments.AuthorizationRequest authRequest = new commercepayments.AuthorizationRequest(80);
        authRequest.paymentMethod = paymentMethod;
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(authRequest, commercepayments.RequestType.Authorize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse authResponse = adapter.processRequest(p);
        system.assert(authResponse instanceOf commercepayments.GatewayErrorResponse, 'Response is not a valid response');
        
    }
    
    
   public static testmethod void testAuthFailureRequest() {
        //Create a PaymentMethod instance
        commercepayments.AuthApiPaymentMethodRequest paymentMethod = createAuthPaymentMethodRequest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutFailureMock());
        //Create an auth request
        commercepayments.AuthorizationRequest authRequest = new commercepayments.AuthorizationRequest(80);
        authRequest.paymentMethod = paymentMethod;
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(authRequest, commercepayments.RequestType.Authorize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse authResponse = adapter.processRequest(p);
        system.assert(authResponse instanceOf commercepayments.AuthorizationResponse, 'Response is not a valid Authorization response');
        
    }
    
    /**
     * Uses PaymentCalloutResponseParseFailureMock to simulate a response parsing error. 
     */
    public static testmethod void testAuthResponseParseFailureRequest() {
        //Create a PaymentMethod instance
        commercepayments.AuthApiPaymentMethodRequest paymentMethod = createAuthPaymentMethodRequest();
        //paymentMethod.address = address;
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutResponseParseFailureMock());
        //Create an auth request
        commercepayments.AuthorizationRequest authRequest = new commercepayments.AuthorizationRequest(80);
        authRequest.paymentMethod = paymentMethod;
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(authRequest, commercepayments.RequestType.Authorize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse authResponse = adapter.processRequest(p);
        system.assert(authResponse instanceOf commercepayments.GatewayErrorResponse, 'Response is not a valid Gateway error response');
        
    }
    
    
    public static testmethod void testCaptureFailureRequest() {
        PaymentAuthorization auth = initializeAuthObject();
        insert auth;
        //Dmls and http request can't be performed in a single transaction in apex
        //segreagating the transaction by starting a test context
        Test.startTest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutFailureMock());
        //Create an capture request
        commercepayments.CaptureRequest captureRequest = new commercepayments.CaptureRequest(80, auth.id);
        
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(captureRequest, commercepayments.RequestType.Capture);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse captureResponse = adapter.processRequest(p);
        system.assert(captureResponse instanceOf commercepayments.CaptureResponse, 'Response is not a valid Capture response');
        Test.stopTest();
    }
    
    
    
    public static testmethod void testReferencedRefundFailureRequest() {
        Payment pmt = initializePaymentObject();
        insert pmt;
        //Dmls and http request can't be performed in a single transaction in apex
        //segreagating the transaction by starting a test context
        Test.startTest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutFailureMock());
        //Create an capture request
        commercepayments.ReferencedRefundRequest refundRequest = new commercepayments.ReferencedRefundRequest(80, pmt.id);
        
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(refundRequest, commercepayments.RequestType.referencedrefund);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse refundResponse = adapter.processRequest(p);
        system.assert(refundResponse instanceOf commercepayments.ReferencedRefundResponse, 'Response is not a valid Refund response');
        Test.stopTest();
    }
    
    public static testmethod void testSaleRequest() {
        //Create a PaymentMethod instance
        commercepayments.SaleApiPaymentMethodRequest paymentMethod = createSalePaymentMethodRequest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutMock());
        //Create an auth request
        commercepayments.SaleRequest saleRequest = new commercepayments.SaleRequest(80);
        saleRequest.paymentMethod = paymentMethod;
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(saleRequest, commercepayments.RequestType.Sale);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        commercepayments.GatewayResponse saleResponse = adapter.processRequest(p);
        system.assert(saleResponse instanceOf commercepayments.SaleResponse, 'Response is not a valid Sale response');
        
    }
    
    public static testmethod void testSaleFailureRequest() {
        //Create a PaymentMethod instance
        commercepayments.SaleApiPaymentMethodRequest paymentMethod = createSalePaymentMethodRequest();
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutFailureMock());
        //Create an auth request
        commercepayments.SaleRequest saleRequest = new commercepayments.SaleRequest(80);
        saleRequest.paymentMethod = paymentMethod;
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(saleRequest, commercepayments.RequestType.Sale);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        
        commercepayments.GatewayResponse saleResponse = adapter.processRequest(p);
        system.assert(saleResponse instanceOf commercepayments.SaleResponse, 'Response is not a valid Sale response');
    }
    
    public static testmethod void testTokenizeRequest() {
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutMock());
        //Create an auth request
        commercepayments.PaymentMethodTokenizationRequest tokenizeRequest = new commercepayments.PaymentMethodTokenizationRequest(NULL);
        tokenizeRequest.cardPaymentMethod = getCardPaymentMethod();
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(tokenizeRequest, commercepayments.RequestType.Tokenize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        commercepayments.GatewayResponse tokenizeResponse = adapter.processRequest(p);
        system.assert(tokenizeResponse instanceOf commercepayments.PaymentMethodTokenizationResponse, 'Response is not a valid Tokenize response');
        
    }
    
    public static testmethod void testTokenizeFailureRequest() {
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new PaymentCalloutFailureMock());
        //Create an auth request
        commercepayments.PaymentMethodTokenizationRequest tokenizeRequest = new commercepayments.PaymentMethodTokenizationRequest(NULL);
        tokenizeRequest.cardPaymentMethod = getCardPaymentMethod();
        commercepayments.PaymentGatewayContext p = new commercepayments.PaymentGatewayContext(tokenizeRequest, commercepayments.RequestType.Tokenize);
        PayeezyGatewayAdapter adapter = new PayeezyGatewayAdapter();
        commercepayments.GatewayResponse tokenizeResponse = adapter.processRequest(p);
        system.assert(tokenizeResponse instanceOf commercepayments.PaymentMethodTokenizationResponse, 'Response is not a valid Tokenize response');
    }
    
    private static PaymentAuthorization initializeAuthObject()
    {
        PaymentAuthorization auth = new PaymentAuthorization();
        auth.amount = 1500;
        auth.Status = 'Processed';
        auth.ProcessingMode = 'External';
        auth.GatewayRefNumber = 'testreferencenumber';
        auth.GatewayRefDetails = '{"method":"credit_card","transaction_id":"ET119982"}';
        return auth;
    
    }
    
    private static Payment initializePaymentObject()
    {
        Payment pmt = new Payment();
        pmt.amount = 1500;
        pmt.Status = 'Processed';
        pmt.ProcessingMode = 'External';
        pmt.GatewayRefNumber = 'testreferencenumber';
        pmt.Type = 'Capture';
        pmt.GatewayRefDetails = '{"method":"credit_card","transaction_id":"ET119982"}';
        return pmt;    
    }
    
    private static commercepayments.AuthApiPaymentMethodRequest createAuthPaymentMethodRequest()
    {
           //Create Address request
        commercepayments.AddressRequest address = new commercepayments.AddressRequest('test', 'test', 'test', 'test', 'test');
        //Create a PaymentMethod instance
        commercepayments.AuthApiPaymentMethodRequest paymentMethod = new commercepayments.AuthApiPaymentMethodRequest(getCardPaymentMethod());
        //paymentMethod.address = address;
        return paymentMethod;
    
    }
    
    private static commercepayments.SaleApiPaymentMethodRequest createSalePaymentMethodRequest()
    {
           //Create Address request
        commercepayments.AddressRequest address = new commercepayments.AddressRequest('test', 'test', 'test', 'test', 'test');
        //Create a PaymentMethod instance
        commercepayments.SaleApiPaymentMethodRequest paymentMethod = new commercepayments.SaleApiPaymentMethodRequest(getCardPaymentMethod());
        paymentMethod.address = address;
        return paymentMethod;
    
    }
    
    private static commercepayments.CardPaymentMethodRequest getCardPaymentMethod(){
        commercepayments.CardPaymentMethodRequest cardPaymentMethod = new commercepayments.CardPaymentMethodRequest(commercepayments.CardCategory.CreditCard);
        cardPaymentMethod.cardType = commercepayments.CardType.Visa;
        cardPaymentMethod.cardHolderFirstName = 'Test';
        cardPaymentMethod.cardHolderLastName = 'Test';
        cardPaymentMethod.cardHolderName = 'Test Test';
        cardPaymentMethod.cardNumber = '4443434343284111';
        cardPaymentMethod.cvv = '123';
        cardPaymentMethod.email = 'h@test.com';
        cardPaymentMethod.expiryMonth = 2;
        cardPaymentMethod.expiryYear = 1111;
        cardPaymentMethod.startMonth = 2;
        cardPaymentMethod.startYear = 1333;
        return cardPaymentMethod;
    }
}