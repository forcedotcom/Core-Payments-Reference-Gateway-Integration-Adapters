/**
 * Http callouts mock class for payeezy adapter in test context.
 * This is used to simulate an error condition at the high level such as request throttling or unauthorized usage.
 * @author mranjan
 * @since 226
 */ 
public class PaymentCalloutHighLevelErrorMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        System.assertEquals('POST', req.getMethod());
        
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        
        List<String> jsonResponse = new List<String> {
                '"code": "Transaction_Throttled"',
                '"message": "Transaction throttled"'
        };
        res.setBody('{' + String.join(jsonResponse, ',') + '}');
        return res;
    }
}