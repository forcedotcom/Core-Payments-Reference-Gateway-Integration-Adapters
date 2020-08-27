/**
 * Http callouts mock class for payeezy adapter in test context
 * This is used to send a response message that will fail during json parser .particularly parsing the error messages as list.
 * @author mranjan
 * @since 226
 */ 
public class PaymentCalloutResponseParseFailureMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        System.assertEquals('POST', req.getMethod());
        
        // Create a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        
        //Error Object in the below json response is sent as nested objects where as it's expected as lists
        /*
         check the following lines in AbstractTransactionService.apex
         list<Object> listofError = (list<object>) mapOfErrors.get('messages');
        
        */
        
        List<String> jsonResponse = new List<String> {
                '"transaction_status": "Not Processed"',
                '"validation_status": "failed"',
                '"transaction_type": "authorize"',
                '"method": "credit_card"',
                '"amount": "1299"',
                '"currency": "USD"',
                '"correlation_id": "228.6136675492894","Error": {"messages": {"code": "invalid_card_number","description": "The credit card number check failed"}}'                
                            
        };
        res.setBody('{' + String.join(jsonResponse, ',') + '}');
        return res;
    }
}