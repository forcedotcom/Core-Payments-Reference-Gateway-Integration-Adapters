/**
 * Http callouts mock class for payeezy adapter in test context
 * @author r.shankar
 * @since 224
 */ 
public class PaymentCalloutFailureMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        System.assertEquals('POST', req.getMethod());
        
        // Create a fake response
        HttpResponse res = new HttpResponse();
        List<String> jsonResponse;
        res.setHeader('Content-Type', 'application/json');
        if(req.getEndpoint().contains('tokens')){
            jsonResponse = new List<String> {
              '"correlation_id": "124.9765877252790"',
                '"status": "failed"',
                '"Error": {"messages": [{"code": "invalid_card_number","description": "The credit card number check failed"}]}',
                '"type": "FDToken"'
            };
        }
        else{
          jsonResponse = new List<String> {
                '"transaction_status": "Not Processed"',
                '"validation_status": "failed"',
                '"transaction_type": "authorize"',
                '"method": "credit_card"',
                '"amount": "1299"',
                '"currency": "USD"',
                '"correlation_id": "228.6136675492894"',
                '"Error": {"messages": [{"code": "invalid_card_number","description": "The credit card number check failed"}]}'           
          };
        }
        res.setBody('{' + String.join(jsonResponse, ',') + '}');
        return res;
    }
}