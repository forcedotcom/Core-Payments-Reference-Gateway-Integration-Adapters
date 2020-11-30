/**
 * Auth Reversal Service class
 */ 
public class AuthReversalTransactionService extends AbstractTransactionService{
    
    /**
     * Constructor that sets the gatewayContext for the service
     */ 
    public AuthReversalTransactionService(commercepayments.paymentGatewayContext gatewayContext){
        super(gatewayContext);
    }
    
    /**
     * Function to build request for Auth Reversal Transaction
     * Creates a new request and set request body, authorization parameters and other related fields
     */ 
    public override HttpRequest buildRequest(){
        HttpRequest req = new HttpRequest();
        //The rest of the endpoint is set in the buildAuthReversalRequestBody
        req.setEndpoint('/v1/transactions/');
        req.setMethod('POST');
        req.setBody(buildAuthReversalRequestBody((commercepayments.AuthorizationReversalRequest)gatewayContext.getPaymentRequest(),req));
        setAuthorizationHeaders(req);
        return req; 
    }
    
    /**
     * Function to build gateway response for Auth Reversal Transaction
     * The input is the response from gateway
     * It creates and returns AuthReversalGatewayResponse from the HttpResponse
     */
    public override commercepayments.GatewayResponse buildResponse(HttpResponse response){
        String statusCode = String.valueOf(response.getStatusCode());
        //Get the map of key and values from the gateway response using parseResponse()
        Map <String, String> mapOfResponseValues = parseResponse(response.getBody());
        commercepayments.AuthorizationReversalResponse authorizationReversalResponse = new commercepayments.AuthorizationReversalResponse();
        String res_code = null;
        String TRANSACTION_STATUS = mapOfResponseValues.get(TRANSACTION_STATUS);
        String salesforceResultCode = null;
        if(TRANSACTION_STATUS != null){
            if(TRANSACTION_STATUS == APPROVED){
               //Successful gateway response
                res_code = mapOfResponseValues.get(GATEWAY_RESPONSE_CODE);
                salesforceResultCode = SUCCESS_SALESFORCE_RESULT_CODE.name();
                Map<String, Object> refDetails = new Map<String, Object>();
                refDetails.put('transaction_id', mapOfResponseValues.get(TRANSACTION_ID));
                refDetails.put('method', mapOfResponseValues.get(PAYMENT_METHOD));
                String refDetailString = JSON.Serialize(refDetails);
                //Populating successful auth reversal response
                authorizationReversalResponse.setGatewayReferenceDetails(refDetailString);
                authorizationReversalResponse.setGatewayResultCode(res_code);
                authorizationReversalResponse.setGatewayResultCodeDescription(mapOfResponseValues.get(GATEWAY_MESSAGE));
                authorizationReversalResponse.setGatewayReferenceNumber(mapOfResponseValues.get(TRANSACTION_TAG));
            }else{
                //Failed gateway response
                salesforceResultCode= DECLINE_SALESFORCE_RESULT_CODE.name();
                res_code = mapOfResponseValues.get('code');
                String description = mapOfResponseValues.get('description');
                //Populating failed auth reversal response
                if(res_code != null){
                    authorizationReversalResponse.setGatewayResultCode(res_code);
                }else if(mapOfResponseValues.get(VALIDATION_STATUS) != null){
                    authorizationReversalResponse.setGatewayResultCode('Validation Status - failed');
                }else{
                    authorizationReversalResponse.setGatewayResultCode('failed');
                }
                if(description != null){
                    authorizationReversalResponse.setGatewayResultCodeDescription(description);
                }else{
                    authorizationReversalResponse.setGatewayResultCodeDescription(TRANSACTION_STATUS);
                }
            }

            //Gateway Result code mappings provided as custom metadata for the gateway
            if (useCustomMetadata) {
                // If customMetadata is used, fetch the salesforce result code info from the gateway result code mappings
                authorizationReversalResponse.setSalesforceResultCodeInfo(getSalesforceResultCodeInfo(res_code));
            } else {
                // Else fetch the salesforce result code info from the salesforce result code set in the method
                authorizationReversalResponse.setSalesforceResultCodeInfo(getSalesforceResultCodeInfo(salesforceResultCode));
            }
        }else {
                String message = mapOfResponseValues.get('message') == null? mapOfResponseValues.get('description') :mapOfResponseValues.get('message');
                commercepayments.GatewayErrorResponse error = new commercepayments.GatewayErrorResponse(statusCode, message);
                return error;
        }
        String amountStr = mapOfResponseValues.get('amount');
        if(amountStr != null){
            Double amountDbl = double.valueOf(amountStr);
            //amount is divided by 100 to convert cents to dollars
            authorizationReversalResponse.setAmount(double.valueOf(amountDbl/100.0));
        }
        //Gateway does not send date, assigning the current date for recording purpose
        authorizationReversalResponse.setGatewayDate(system.now());
        return authorizationReversalResponse;
    }
    
    /**
     * Function to build request body for Auth Reversal Transaction
     */
    private String buildAuthReversalRequestBody(commercepayments.AuthorizationReversalRequest authorizationReversalRequest,HttpRequest req) {
        Boolean IS_MULTICURRENCY_ORG = UserInfo.isMultiCurrencyOrganization();
        //Get the authorization object with all the required fields
        PaymentAuthorization authObject = getAuthObjectForAuthReversal(authorizationReversalRequest.paymentAuthorizationId,IS_MULTICURRENCY_ORG);
        String transactionId,method;
        try {
            Map<String, Object> refDetailsMap = (Map<String, Object>) JSON.deserializeUntyped(authObject.GatewayRefDetails);
            transactionId = (String)refDetailsMap.get('transaction_id');
            method = (String)refDetailsMap.get('method');
        } catch(Exception e) {}
        //Adding transaction_id to the end point   
        req.setEndpoint(req.getEndpoint() + transactionId);
         
        JSONGenerator jsonGeneratorInstance = JSON.createGenerator(true);
        // Write data to the JSON string.
        jsonGeneratorInstance.writeStartObject();
        jsonGeneratorInstance.writeStringField('merchant_ref', '');
        jsonGeneratorInstance.writeStringField('transaction_type', 'void');
        jsonGeneratorInstance.writeStringField('transaction_tag', authObject.GatewayRefNumber);
        if(authorizationReversalRequest.amount!=null)
            //Amount is multiplied by 100 as gateway accepts input in cents
            jsonGeneratorInstance.writeStringField('amount', String.ValueOf((authorizationReversalRequest.amount*100.0).intValue()));
        if (IS_MULTICURRENCY_ORG) {
            jsonGeneratorInstance.writeStringField('currency_code', authObject.get('CurrencyIsoCode').toString());
        } else {
            jsonGeneratorInstance.writeStringField('currency_code', UserInfo.getDefaultCurrency());
        }
        jsonGeneratorInstance.writeStringField('method', method);
        jsonGeneratorInstance.writeEndObject();
        return jsonGeneratorInstance.getAsString(); 
    }
    
    /**
     * Get the auth record with all the required fields 
     * Database call from apex done to fetch the record
     */ 
    private PaymentAuthorization getAuthObjectForAuthReversal(String authorizationId, Boolean IS_MULTICURRENCY_ORG){
        List<String> listOfFields = new List<String>();
        listOfFields.add('GatewayAuthCode');
        listOfFields.add('GatewayRefNumber');
        listOfFields.add('GatewayRefDetails');
        if (IS_MULTICURRENCY_ORG) {
            // currency of auth required if org is multi currency
            listOfFields.add('CurrencyIsoCode');
        }
        //Fetch the authorization record using the Auth Id
        PaymentAuthorization authObject = (PaymentAuthorization)DaoService.getSobjectById(authorizationId, listOfFields, PaymentAuthorization.SObjectType);
        return authObject;
    }
}