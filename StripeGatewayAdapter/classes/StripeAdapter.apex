/**
 * Reference Stripe adapter for Commerce Payments.
 * Implements {@link commercepayments.PaymentGatewayAdapter} for synchronous operations and
 * {@link commercepayments.PaymentGatewayAsyncAdapter} for webhook-driven completion when using
 * automatic capture on PaymentIntents.
 * This sample uses {@link StripeHttpUtil} for HTTP and {@link QueryUtils} for dynamic SOQL.
 * Harden for production (webhook signatures, error mapping, idempotency, PCI review).
 */
global without sharing class StripeAdapter
    implements commercepayments.PaymentGatewayAsyncAdapter, commercepayments.PaymentGatewayAdapter
{

    // Commerce result codes and Stripe error lists (used for notifications, declines, and retry hints).
    private static final commercepayments.SalesforceResultCodeInfo RC_SUCCESS =
        toCodeInfo(commercepayments.SalesforceResultCode.Success);
    private static final commercepayments.SalesforceResultCodeInfo RC_DECLINE =
        toCodeInfo(commercepayments.SalesforceResultCode.Decline);
    private static final commercepayments.SalesforceResultCodeInfo RC_REQUIRES_REVIEW =
        toCodeInfo(commercepayments.SalesforceResultCode.RequiresReview);

    private static final List<String> DECLINE_CODES = new List<String>{
        'card_declined', 'incorrect_cvc', 'expired_card', 'authentication_required', 'card_not_supported',
        'currency_not_supported', 'incorrect_number', 'incorrect_zip', 'account_closed', 'insufficient_funds'
    };

    private static final Map<String, commercepayments.RetryCategory> ERROR_CODES_RETRY_CATEGORY_MAP =
        new Map<String, commercepayments.RetryCategory>{
            'incorrect_cvc' => commercepayments.RetryCategory.PaymentInformation,
            'card_declined' => commercepayments.RetryCategory.PaymentProcessing,
            'expired_card' => commercepayments.RetryCategory.PaymentInformation,
            'incorrect_number' => commercepayments.RetryCategory.PaymentInformation,
            'incorrect_zip' => commercepayments.RetryCategory.PaymentInformation,
            'authentication_required' => commercepayments.RetryCategory.Security,
            'processing_error' => commercepayments.RetryCategory.PaymentProcessing,
            'account_closed' => commercepayments.RetryCategory.PaymentProcessing,
            'insufficient_funds' => commercepayments.RetryCategory.CardLimit
        };

    private static final List<String> RETRIABLE_CODES = new List<String>{
        'incorrect_cvc', 'payment_intent_payment_attempt_failed', 'incorrect_zip', 'incorrect_number',
        'authentication_required', 'processing_error', 'insufficient_funds'
    };

    private static final List<String> NON_RETRIABLE_CODES = new List<String>{
        'card_declined', 'expired_card', 'card_not_supported', 'currency_not_supported', 'account_closed'
    };

    // https://stripe.com/docs/currencies#zero-decimal
    private static final List<String> ZERO_DECIMAL_CURRENCY = new List<String>{
        'bif', 'clp', 'djf', 'gnf', 'jpy', 'kmf', 'krw', 'mga', 'pyg', 'rwf', 'ugx', 'vnd', 'vuv',
        'xaf', 'xof', 'xpf'
    };

    global StripeAdapter()
    {
    }

    // Dispatches synchronous Commerce gateway operations to Stripe HTTP endpoints.
    global commercepayments.GatewayResponse processRequest(commercepayments.paymentGatewayContext gatewayContext)
    {
        commercepayments.RequestType requestType = gatewayContext.getPaymentRequestType();
        commercepayments.PaymentGatewayRequest paymentRequest = gatewayContext.getPaymentRequest();
        commercepayments.GatewayResponse response;

        try {
            if (requestType == commercepayments.RequestType.Authorize) {
                response = createAuthResponse((commercepayments.AuthorizationRequest) paymentRequest);
            } else if (requestType == commercepayments.RequestType.Capture) {
                response = createCaptureResponse((commercepayments.CaptureRequest) paymentRequest);
            } else if (requestType == commercepayments.RequestType.Sale) {
                response = createSaleResponse((commercepayments.SaleRequest) paymentRequest);
            } else if (requestType == commercepayments.RequestType.ReferencedRefund) {
                response = createRefundResponse((commercepayments.ReferencedRefundRequest) paymentRequest);
            } else if (requestType == commercepayments.RequestType.Tokenize) {
                response =
                    createTokenizeResponse((commercepayments.PaymentMethodTokenizationRequest) paymentRequest);
            } else if (requestType == commercepayments.RequestType.AuthorizationReversal) {
                response =
                    createAuthReversalResponse((commercepayments.AuthorizationReversalRequest) paymentRequest);
            }
            return response;
        } catch (StripeValidationException e) {
            return new commercepayments.GatewayErrorResponse('400', e.getMessage());
        }
    }

    // Stripe webhook body: record PaymentIntent outcome for automatic capture (async completion path).
    global commercepayments.GatewayNotificationResponse processNotification(
        commercepayments.PaymentGatewayNotificationContext gatewayNotificationContext
    )
    {
        commercepayments.PaymentGatewayNotificationRequest gatewayNotificationRequest =
            gatewayNotificationContext.getPaymentGatewayNotificationRequest();

        commercepayments.GatewayNotificationResponse gatewayNotificationResponse =
            new commercepayments.GatewayNotificationResponse();
        Blob requestBlob = gatewayNotificationRequest.getRequestBody();

        try {
            Map<String, Object> jsonEvent = (Map<String, Object>) JSON.deserializeUntyped(requestBlob.toString());
            String eventType = (String) jsonEvent.get('type');

            // Automatic capture only: manual-capture intents complete via synchronous capture API instead.
            if ('payment_intent.succeeded'.equals(eventType) || 'payment_intent.payment_failed'.equals(eventType)) {
                Map<String, Object> eventData = (Map<String, Object>) jsonEvent.get('data');
                Map<String, Object> eventDataObject = (Map<String, Object>) eventData.get('object');
                String captureMethod = (String) eventDataObject.get('capture_method');

                if ('automatic'.equals(captureMethod)) {
                    commercepayments.BaseNotification notification = new commercepayments.SaleNotification();
                    String status = (String) eventDataObject.get('status');
                    Long amount = (Long) eventDataObject.get('amount');
                    String currencyUnit = (String) eventDataObject.get('currency');
                    Long createdAtInSeconds = (Long) eventDataObject.get('created');
                    Datetime gatewayDateTime = Datetime.newInstance(createdAtInSeconds * 1000);

                    if ('succeeded'.equals(status)) {
                        notification.setStatus(commercepayments.NotificationStatus.Success);
                        notification.setSalesforceResultCodeInfo(RC_SUCCESS);
                        notification.setGatewayResultCode(status);
                        notification.setGatewayResultCodeDescription(status);
                    } else {
                        notification.setStatus(commercepayments.NotificationStatus.Failed);
                        notification.setSalesforceResultCodeInfo(RC_DECLINE);

                        Map<String, Object> errorMap =
                            (Map<String, Object>) eventDataObject.get('last_payment_error');
                        if (errorMap != null) {
                            String errorCode = (String) errorMap.get('code');
                            String errorType = (String) errorMap.get('type');

                            if (errorType != null && errorCode != null && 'card_error'.equals(errorType)
                                && DECLINE_CODES.contains(errorCode)) {
                                commercepayments.RetryCategory retryCategory =
                                    ERROR_CODES_RETRY_CATEGORY_MAP.get(errorCode);
                                notification.setRetryCategory(retryCategory);
                                // Optional Commerce retry hints when orchestration supports Retriable vs NonRetriable.
                                if (RETRIABLE_CODES.contains(errorCode)) {
                                    notification.setRetryDecision(commercepayments.RetryDecision.Retriable);
                                } else if (NON_RETRIABLE_CODES.contains(errorCode)) {
                                    notification.setRetryDecision(commercepayments.RetryDecision.NonRetriable);
                                }
                            }

                            String gatewayResultCode = errorCode;
                            String gatewayResultCodeDescription = (String) errorMap.get('decline_code');
                            String errorMessage = (String) errorMap.get('message');
                            if (gatewayResultCode != null) {
                                notification.setGatewayResultCode(gatewayResultCode);
                            } else {
                                notification.setGatewayResultCode(status);
                            }
                            notification.setGatewayResultCodeDescription(gatewayResultCodeDescription);
                            notification.setGatewayMessage(errorMessage);
                        } else {
                            notification.setGatewayResultCode(status);
                        }
                    }

                    notification.setGatewayReferenceNumber((String) eventDataObject.get('id'));
                    notification.setAmount(fromStripeCurrencyUnits(currencyUnit, amount));
                    notification.setGatewayDate(gatewayDateTime);

                    commercepayments.NotificationSaveResult saveResult =
                        commercepayments.NotificationClient.record(notification);
                    if (saveResult.isSuccess()) {
                        gatewayNotificationResponse.setStatusCode(200);
                    } else {
                        gatewayNotificationResponse.setStatusCode(400);
                        gatewayNotificationResponse.setResponseBody(
                            Blob.valueOf('Errors in the result: ' + saveResult.getErrorMessage())
                        );
                    }
                    return gatewayNotificationResponse;
                }
            }
        } catch (Exception e) {
            gatewayNotificationResponse.setStatusCode(400);
            gatewayNotificationResponse.setResponseBody(
                Blob.valueOf('Could not parse given JSON request body: ' + requestBlob.toString())
            );
            return gatewayNotificationResponse;
        }

        gatewayNotificationResponse.setStatusCode(200);
        return gatewayNotificationResponse;
    }

    /**
     * POST /v1/payment_methods (card or bank). With autoPay, creates Stripe Customer + SetupIntent for off-session use.
     */
    public commercepayments.GatewayResponse createTokenizeResponse(
        commercepayments.PaymentMethodTokenizationRequest tokenizeRequest
    )
    {
        if (tokenizeRequest.cardPaymentMethod != null) {
            return tokeniseCardPaymentMethod(tokenizeRequest);
        }
        return tokeniseBankPaymentMethod(tokenizeRequest);
    }

    /**
     * Authorize with manual capture (capture happens later via {@link #createCaptureResponse}).
     * Uses Stripe PaymentIntents only: POST {@code /v1/payment_intents} with {@code capture_method=manual}.
     * Two inputs: (1) {@code paymentMethodData.gatewayToken} when Commerce passes a pm_/token inline,
     * or (2) card-on-file — Stripe id loaded from {@code CardPaymentMethod} via {@link #resolveCardToken}.
     */
    public commercepayments.GatewayResponse createAuthResponse(commercepayments.AuthorizationRequest authRequest)
    {
        commercepayments.AuthApiPaymentMethodRequest paymentMethod = authRequest.paymentMethod;

        // Amount/currency: Stripe expects amount in smallest currency unit (see ZERO_DECIMAL_CURRENCY).
        String currencyIsoCode = authRequest.currencyIsoCode;
        String amount = toStripeCurrencyUnits(currencyIsoCode, authRequest.amount);

        Map<String, String> params = new Map<String, String>();
        params.put('amount', amount);
        params.put('currency', currencyIsoCode);

        String token;
        String endpoint;

        Map<String, String> pmData = authRequest.paymentMethodData;
        // Inline token (e.g. API 262+): pm/customer sent on paymentMethodData; authorize off-session when applicable.
        if (pmData != null && pmData.containsKey('gatewayToken')) {
            token = pmData.get('gatewayToken');
            params.put('payment_method', token);
            params.put('payment_method_types[]', 'card');
            params.put('confirm', 'true');
            params.put('capture_method', 'manual');
            params.put('off_session', 'true');

            String gatewayCustomerReference = pmData.get('gatewayReference');
            if (gatewayCustomerReference != null) {
                params.put('customer', gatewayCustomerReference);
            }

            endpoint = 'payment_intents';
        } else {
            // Saved card: GatewayToken(Encrypted) on CardPaymentMethod is the Stripe PaymentMethod id (pm_*).
            token = resolveCardToken(paymentMethod.id);
            params.put('payment_method', StripeHttpUtil.urlEncode(token));
            params.put('confirm', 'true');
            params.put('confirmation_method', 'manual');
            params.put('capture_method', 'manual');
            endpoint = 'payment_intents';
        }

        HttpResponse response = StripeHttpUtil.doPost(endpoint, params);
        String body = response.getBody();
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);

        commercepayments.AuthorizationResponse authResponse = new commercepayments.AuthorizationResponse();
        authResponse.setGatewayDate(System.now());

        String gatewayAuthCode;

        Integer sc = response.getStatusCode();
        if (sc >= 200 && sc < 300) {
            String status = (String) results.get('status');
            // Stripe returns HTTP 200 for requires_action (3DS); map to RequiresReview, not RC_SUCCESS.
            if ('requires_action'.equals(status)) {
                authResponse.setGatewayResultCode(status);
                authResponse.setGatewayResultCodeDescription((String) results.get('client_secret'));
                authResponse.setSalesforceResultCodeInfo(RC_REQUIRES_REVIEW);
                return authResponse;
            }
            // Stored on PaymentAuthorization.GatewayAuthCode for capture/reversal (Stripe PaymentIntent id pi_*).
            gatewayAuthCode = (String) results.get('id');
            authResponse.setGatewayResultCode((String) status);
            authResponse.setGatewayResultCodeDescription((String) status);
            authResponse.setGatewayAuthCode(gatewayAuthCode);
            authResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
            authResponse.setAmount(fromStripeCurrencyUnits(currencyIsoCode, (Long) results.get('amount')));
        } else {
            Map<String, Object> error = (Map<String, Object>) results.get('error');
            Map<String, Object> paymentIntent = (Map<String, Object>) error.get('payment_intent');
            String errorCode = (String) error.get('code');
            String errorType;

            // Prefer nested last_payment_error on PaymentIntent when present (Stripe wraps errors on PI).
            if (paymentIntent != null) {
                Map<String, Object> lastPaymentError =
                    (Map<String, Object>) paymentIntent.get('last_payment_error');
                errorType = (lastPaymentError != null) ? (String) lastPaymentError.get('type') : null;
            } else {
                errorType = (String) error.get('type');
            }

            // Known card declines → Commerce decline + optional retry metadata; else raw gateway error.
            if ('card_error'.equals(errorType) && DECLINE_CODES.contains(errorCode)) {
                populateErrorResponse(authResponse, errorCode, error);
            } else {
                return new commercepayments.GatewayErrorResponse(String.valueOf(sc), 'ERROR: ' + body);
            }
        }

        // Echo which Stripe payment_method id was used so orchestration can correlate the auth call.
        commercepayments.PaymentMethodTokenizationResponse paymentMethodTokenizationResponse =
            new commercepayments.PaymentMethodTokenizationResponse();
        paymentMethodTokenizationResponse.setGatewayTokenEncrypted(token);
        authResponse.setPaymentMethodTokenizationResponse(paymentMethodTokenizationResponse);

        return authResponse;
    }

    /**
     * Capture against a prior authorize: Commerce {@link commercepayments.CaptureRequest} supplies
     * {@code paymentAuthorizationId} (PaymentAuthorization row) and the amount to capture for this request (partial capture supported).
     * {@code GatewayAuthCode} from authorize is either a Stripe Charge id ({@code ch_*}) or PaymentIntent id ({@code pi_*}):
     * POST {@code /v1/charges/:id/capture} vs POST {@code /v1/payment_intents/:id/capture} respectively.
     */
    public commercepayments.GatewayResponse createCaptureResponse(commercepayments.CaptureRequest captureRequest)
    {
        Boolean isMultiCurrencyEnabled = UserInfo.isMultiCurrencyOrganization();

        // Load PaymentAuthorization by Commerce id; GatewayAuthCode was set in createAuthResponse from Stripe response.
        QueryUtils q = new QueryUtils(PaymentAuthorization.SObjectType);
        q.getSelectClause().addField('GatewayAuthCode', false);
        if (isMultiCurrencyEnabled) {
            q.getSelectClause().addField('CurrencyIsoCode', false);
        }
        q.setWhereClause(
            ' WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(captureRequest.paymentAuthorizationId)) + '\''
        );
        PaymentAuthorization paymentAuthorization = (PaymentAuthorization) Database.query(q.buildSOQL(),AccessLevel.SYSTEM_MODE)[0];

        String authCode = paymentAuthorization.GatewayAuthCode;
        String currencyIsoCode = isMultiCurrencyEnabled
            ? String.valueOf(paymentAuthorization.get('CurrencyIsoCode'))
            : UserInfo.getDefaultCurrency();
        // Capture amount in Stripe minor units (may be less than original authorized amount for partial capture).
        String amount = toStripeCurrencyUnits(currencyIsoCode, captureRequest.amount);

        Map<String, String> params = new Map<String, String>();
        HttpResponse response;

        // Legacy Charges API vs PaymentIntents: different URL and body parameter name for the capture amount.
        if (authCode.startsWith('ch_')) {
            params.put('amount', amount);
            response = StripeHttpUtil.doPost('charges/' + authCode + '/capture', params);
        } else {
            params.put('amount_to_capture', amount);
            response = StripeHttpUtil.doPost('payment_intents/' + authCode + '/capture', params);
        }

        String body = response.getBody();
        if (response.getStatusCode() != 200) {
            return new commercepayments.GatewayErrorResponse('500', 'ERROR: ' + response + ': ' + body);
        }
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);

        commercepayments.CaptureResponse captureResponse = new commercepayments.CaptureResponse();
        Map<String, Object> charge;
        // Charge capture response body is the Charge object; PI capture returns PaymentIntent — use charges.data[0] for charge fields.
        if (authCode.startsWith('ch_')) {
            charge = results;
        } else {
            Map<String, Object> intent = (Map<String, Object>) JSON.deserializeUntyped(body);
            Map<String, Object> charges = (Map<String, Object>) intent.get('charges');
            Object[] data = (Object[]) charges.get('data');
            charge = (Map<String, Object>) data[0];
        }

        // Map settled charge fields into Commerce CaptureResponse (captured amount comes from Charge object).
        captureResponse.setGatewayResultCode((String) charge.get('balance_transaction'));
        captureResponse.setGatewayResultCodeDescription((String) charge.get('receipt_url'));
        captureResponse.setAmount(fromStripeCurrencyUnits(currencyIsoCode, (Long) charge.get('amount')));
        captureResponse.setGatewayDate(System.now());
        captureResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
        return captureResponse;
    }

    /**
     * Builds and executes a Stripe PaymentIntent for sale (automatic capture).
     */
    public commercepayments.GatewayResponse createSaleResponse(
        commercepayments.SaleRequest saleRequest
    )
    {
        // Form body for POST /v1/payment_intents (Stripe uses application/x-www-form-urlencoded).
        String token;
        String paymentMethodType;
        Map<String, String> params = new Map<String, String>();
        Id idToProcess = saleRequest.paymentMethod.id;

        // paymentMethodData null: only paymentMethod.id—load Stripe pm_/token from CPM or SPM.
        if (saleRequest.paymentMethodData == null) {
            String paymentMethodId = saleRequest.paymentMethod.id;
            if (idToProcess.getSObjectType() == CardPaymentMethod.SObjectType) {
                token = resolveCardToken(paymentMethodId);
            } else if (idToProcess.getSObjectType() == SavedPaymentMethod.SObjectType) {
                token = resolveSPMToken(paymentMethodId);
            } else {
                return new commercepayments.GatewayErrorResponse('400', 'Unsupported payment method for sale.');
            }
            // Card-only path when resolving from stored records.
            params.put('payment_method', StripeHttpUtil.urlEncode(token));
            
            // Prior to 258 release default payment method can only be card
            params.put('payment_method_types[]', 'card');
        } else {
            // API 258+: gatewayToken, paymentMethodType, gatewayReference, etc. on paymentMethodData.
            token = saleRequest.paymentMethodData.get('gatewayToken');
            paymentMethodType = determinePaymentMethodTypeForSaleFlow(saleRequest);
            params.put('payment_method', token);
            params.put('payment_method_types[]', paymentMethodType);
            populateMandateData(params, saleRequest.ipAddress);
        }

        // Optional Stripe customer id for saved tokens / recurring contexts.
        if (saleRequest.paymentMethodData != null) {
            String gatewayCustomerReference = saleRequest.paymentMethodData.get('gatewayReference');
            if (gatewayCustomerReference != null) {
                params.put('customer', gatewayCustomerReference);
            }
            // Link wallet: add link to payment_method_types (Stripe accepts repeated keys).
            String paymentMethodSubType = saleRequest.paymentMethodData.get('paymentMethodSubType');
            if (paymentMethodSubType != null && 'link'.equals(paymentMethodSubType)) {
                String existing = params.get('payment_method_types[]');
                if (existing != null) {
                    params.put('payment_method_types[]', existing + '&payment_method_types[]=link');
                } else {
                    params.put('payment_method_types[]', 'link');
                }
            }
        }

        // Pass through Commerce idempotency key as Stripe Idempotency-Key header.
        String idempotencyKey = saleRequest.idempotencyKey;
        Map<String, String> headers = new Map<String, String>();
        if (idempotencyKey != null) {
            headers.put('Idempotency-Key', idempotencyKey);
        }

        // Amount in Stripe's smallest currency unit; currency lowercased by Stripe API.
        String currencyIsoCode = saleRequest.currencyIsoCode;
        String amount = toStripeCurrencyUnits(currencyIsoCode, saleRequest.amount);
        params.put('amount', amount);
        params.put('currency', currencyIsoCode);
        
        // Create and confirm in one request; funds captured automatically when intent succeeds.
        params.put('confirm', 'true');
        params.put('capture_method', 'automatic');

        // enhancedPaymentData represents Level 2/3 (amount_details) 
        commercepayments.EnhancedPaymentDataInput enhancedPaymentData = saleRequest.enhancedPaymentData;
        if (enhancedPaymentData != null) {
            populateEnhancedPaymentData(params, enhancedPaymentData, paymentMethodType, currencyIsoCode);
        }

        // expand[]=latest_charge avoids an extra retrieve when mapping the charge-backed fields.
        HttpResponse response = StripeHttpUtil.doPost('payment_intents?expand[]=latest_charge', params, headers);
        String body = response.getBody();
        Map<String, Object> intent = (Map<String, Object>) JSON.deserializeUntyped(body);

        commercepayments.SaleResponse saleResponse = new commercepayments.SaleResponse();
        saleResponse.setGatewayDate(System.now());

        Integer sc = response.getStatusCode();
        if (sc >= 200 && sc < 300) {
            String status = (String) intent.get('status');
            saleResponse.setGatewayResultCode(status);
            saleResponse.setGatewayResultCodeDescription(status);
            saleResponse.setGatewayReferenceNumber((String) intent.get('id'));
            saleResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
            saleResponse.setAmount(fromStripeCurrencyUnits(currencyIsoCode, (Long) intent.get('amount')));
            // Async payment methods can leave the intent in processing until webhooks complete the sale.
            if ('processing'.equals(status)) {
                saleResponse.setAsync(true);
            }
        } else {
            Map<String, Object> error = (Map<String, Object>) intent.get('error');
            if (error == null) {
                return new commercepayments.GatewayErrorResponse(String.valueOf(sc), 'ERROR: ' + body);
            }
            String errorCode = (String) error.get('code');
            String errorType = (String) error.get('type');

            // Map known card errors to decline + optional retry hints for the orchestration layer.
            if ('card_error'.equals(errorType) && DECLINE_CODES.contains(errorCode)) {
                populateErrorResponse(saleResponse, errorCode, error);
                commercepayments.RetryCategory retryCategory = ERROR_CODES_RETRY_CATEGORY_MAP.get(errorCode);
                saleResponse.setRetryCategory(retryCategory);
                if (RETRIABLE_CODES.contains(errorCode)) {
                    saleResponse.setRetryDecision(commercepayments.RetryDecision.Retriable);
                } else if (NON_RETRIABLE_CODES.contains(errorCode)) {
                    saleResponse.setRetryDecision(commercepayments.RetryDecision.NonRetriable);
                }
            } else {
                return new commercepayments.GatewayErrorResponse(String.valueOf(sc), 'ERROR: ' + body);
            }
        }

        return saleResponse;
    }

    /**
     * Referenced refund: POST https://api.stripe.com/v1/refunds.
     * Resolves which Stripe object to refund from the Commerce Payment (and optional PaymentAuthorization):
     * {@code payment_intent}, {@code charge}, or sale-only {@code Payment.GatewayRefNumber} (typically pi_*).
     */
    public commercepayments.GatewayResponse createRefundResponse(
        commercepayments.ReferencedRefundRequest refundRequest
    )
    {
        Boolean isMultiCurrencyEnabled = UserInfo.isMultiCurrencyOrganization();

        // Load Payment: need GatewayRefNumber for sale-only refunds; PaymentAuthorizationId when auth+capture flow linked an auth row.
        QueryUtils q = new QueryUtils(Payment.SObjectType);
        q.getSelectClause().addField('PaymentAuthorizationId', false);
        q.getSelectClause().addField('GatewayRefNumber', false);
        if (isMultiCurrencyEnabled) {
            q.getSelectClause().addField('CurrencyIsoCode', false);
        }
        q.setWhereClause(
            ' WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(refundRequest.paymentId)) + '\''
        );
        Payment payment = (Payment) Database.query(q.buildSOQL(), AccessLevel.SYSTEM_MODE)[0];

        // Currency for minor-unit conversion (Stripe refund amount matches Payment currency).
        String currencyIsoCode = isMultiCurrencyEnabled
            ? String.valueOf(payment.get('CurrencyIsoCode'))
            : UserInfo.getDefaultCurrency();

        // When present, GatewayAuthCode holds the Stripe id used at auth/capture time (pi_* or ch_*).
        PaymentAuthorization paymentAuth;
        if (payment.PaymentAuthorizationId != null) {
            QueryUtils q1 = new QueryUtils(PaymentAuthorization.SObjectType);
            q1.getSelectClause().addField('GatewayAuthCode', false);
            q1.setWhereClause(
                ' WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(payment.PaymentAuthorizationId)) + '\''
            );
            paymentAuth = (PaymentAuthorization) Database.query(q1.buildSOQL(), AccessLevel.SYSTEM_MODE)[0];
        } else {
            paymentAuth = null;
        }

        // Partial refund amount in Stripe smallest currency unit (required when refunding less than captured).
        String amount = toStripeCurrencyUnits(currencyIsoCode, refundRequest.amount);

        Map<String, String> params = new Map<String, String>();

        // Stripe expects exactly one of payment_intent or charge on Refund create (not both).
        // Prefer auth row gateway ref when present; else sale-only flow stores PaymentIntent id on Payment.GatewayRefNumber.
        if (paymentAuth != null) {
            if (paymentAuth.GatewayAuthCode.startsWith('pi_')) {
                params.put('payment_intent', paymentAuth.GatewayAuthCode);
            } else {
                params.put('charge', paymentAuth.GatewayAuthCode);
            }
        } else {
            params.put('payment_intent', payment.GatewayRefNumber);
        }

        params.put('amount', amount);

        HttpResponse response = StripeHttpUtil.doPost('refunds', params);

        String body = response.getBody();
        if (response.getStatusCode() != 200) {
            return new commercepayments.GatewayErrorResponse('500', 'ERROR: ' + response + ': ' + body);
        }
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);

        // Map Stripe refund object into Commerce ReferencedRefundResponse (amount credited on gateway).
        commercepayments.ReferencedRefundResponse refundResponse = new commercepayments.ReferencedRefundResponse();
        refundResponse.setAmount(fromStripeCurrencyUnits(currencyIsoCode, (Long) results.get('amount')));
        refundResponse.setGatewayDate(System.now());
        refundResponse.setGatewayResultCode((String) results.get('balance_transaction'));
        refundResponse.setGatewayResultCodeDescription((String) results.get('receipt_url'));
        refundResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
        return refundResponse;
    }

    /**
     * Authorization reversal (void): Commerce sends {@link commercepayments.AuthorizationReversalRequest}
     * with {@code paymentAuthorizationId} pointing at the PaymentAuthorization whose {@code GatewayAuthCode}
     * stores the Stripe reference from authorize (here: PaymentIntent id {@code pi_*}).
     * Maps to Stripe POST {@code /v1/payment_intents/:id/cancel} for manual-capture intents still capturable.
     * Legacy Charge API ({@code ch_*}) auth reversal is not implemented in this sample.
     */
    public commercepayments.GatewayResponse createAuthReversalResponse(
        commercepayments.AuthorizationReversalRequest request
    )
    {
        // Resolve PaymentAuthorization row from Commerce id (escapes Id for dynamic SOQL).
        QueryUtils q = new QueryUtils(PaymentAuthorization.SObjectType);
        q.getSelectClause().addField('GatewayAuthCode', false);
        q.setWhereClause(
            ' WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(request.paymentAuthorizationId)) + '\''
        );
        PaymentAuthorization paymentAuth = (PaymentAuthorization) Database.query(q.buildSOQL(),AccessLevel.SYSTEM_MODE)[0];

        commercepayments.AuthorizationReversalResponse authReversalResponse =
            new commercepayments.AuthorizationReversalResponse();

        // Stripe: cancel releases an uncaptured PaymentIntent (cannot cancel after capture or final failure).
        if (paymentAuth.GatewayAuthCode.startsWith('pi_')) {
            String path = 'payment_intents/' + paymentAuth.GatewayAuthCode + '/cancel';
            Map<String, String> params = new Map<String, String>();
            HttpResponse response = StripeHttpUtil.doPost(path, params);

            String body = response.getBody();
            if (response.getStatusCode() != 200) {
                return new commercepayments.GatewayErrorResponse('500', 'ERROR: ' + response + ': ' + body);
            }
            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);

            authReversalResponse.setGatewayDate(System.now());
            authReversalResponse.setGatewayResultCode((String) results.get('status'));
            authReversalResponse.setGatewayResultCodeDescription((String) results.get('status'));
            authReversalResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
        } else {
            // createAuthResponse may store ch_* for legacy Charges; void uses a different Stripe API than cancel PI.
            return new commercepayments.GatewayErrorResponse(
                '400',
                'Authorization reversal can only be performed on a payment intent.'
            );
        }

        return authReversalResponse;
    }

    // -------------------------------------------------------------------------
    // Private helpers — tokenization (payment_methods, customers, setup_intents)
    // -------------------------------------------------------------------------

    // ACH / SEPA / BACS / BECS: map Commerce bank type to Stripe payment_method[type] parameters.
    private commercepayments.GatewayResponse tokeniseBankPaymentMethod(
        commercepayments.PaymentMethodTokenizationRequest tokenizeRequest
    )
    {
        commercepayments.BankPaymentMethodRequest bankPaymentMethod = tokenizeRequest.bankPaymentMethod;
        commercepayments.AddressRequest billingAddress = tokenizeRequest.address;
        Map<String, String> params = new Map<String, String>();

        String paymentMethodType;
        String customerName = bankPaymentMethod.accountHolderName;
        String customerEmail = bankPaymentMethod.email;

        if (bankPaymentMethod.bankType == commercepayments.BankType.Ach) {
            paymentMethodType = 'us_bank_account';
            if (bankPaymentMethod.accountHolderType == commercepayments.AccountHolderType.Individual) {
                params.put('us_bank_account[account_holder_type]', 'individual');
            } else {
                params.put('us_bank_account[account_holder_type]', 'company');
            }
            params.put('us_bank_account[account_number]', String.valueOf(bankPaymentMethod.accountNumber));
            params.put('us_bank_account[routing_number]', String.valueOf(bankPaymentMethod.bankCode));
        } else if (bankPaymentMethod.bankType == commercepayments.BankType.SepaDebit) {
            paymentMethodType = 'sepa_debit';
            params.put('sepa_debit[iban]', String.valueOf(bankPaymentMethod.accountNumber));
        } else if (bankPaymentMethod.bankType == commercepayments.BankType.Bacs) {
            paymentMethodType = 'bacs_debit';
            params.put('bacs_debit[account_number]', String.valueOf(bankPaymentMethod.accountNumber));
            params.put('bacs_debit[sort_code]', String.valueOf(bankPaymentMethod.bankCode));
        } else if (bankPaymentMethod.bankType == commercepayments.BankType.Becs) {
            paymentMethodType = 'au_becs_debit';
            params.put('au_becs_debit[account_number]', String.valueOf(bankPaymentMethod.accountNumber));
            params.put('au_becs_debit[bsb_number]', String.valueOf(bankPaymentMethod.bankCode));
        } else {
            throw new StripeValidationException('Unsupported bank payment method type for this sample.');
        }
        params.put('type', paymentMethodType);

        populateFraudData(params, tokenizeRequest);
        addBillingDetails(params, customerName, customerEmail, billingAddress);

        HttpResponse response = StripeHttpUtil.doPost('payment_methods', params);
        String body = response.getBody();
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);

        if (bankPaymentMethod.autoPay != true) {
            return buildTokenizationResponse(response);
        }

        String customerId = createCustomer(customerName, customerEmail);
        String paymentMethodId = (String) results.get('id');
        return setupIntentCreation(customerId, paymentMethodType, paymentMethodId, tokenizeRequest.ipAddress);
    }

    // Raw card data path: create pm_ then optionally attach via SetupIntent when autoPay is true.
    private commercepayments.GatewayResponse tokeniseCardPaymentMethod(
        commercepayments.PaymentMethodTokenizationRequest tokenizeRequest
    )
    {
        commercepayments.CardPaymentMethodRequest cardPaymentMethod = tokenizeRequest.cardPaymentMethod;
        commercepayments.AddressRequest billingAddress = tokenizeRequest.address;
        Map<String, String> params = new Map<String, String>();

        String customerName = StripeHttpUtil.urlEncode(cardPaymentMethod.cardHolderName);
        String customerEmail = cardPaymentMethod.email;

        params.put('type', 'card');
        params.put('card[number]', cardPaymentMethod.cardNumber);
        params.put('card[exp_month]', String.valueOf(cardPaymentMethod.expiryMonth));
        params.put('card[exp_year]', String.valueOf(cardPaymentMethod.expiryYear));
        params.put('card[cvc]', cardPaymentMethod.cvv);

        populateFraudData(params, tokenizeRequest);
        addBillingDetails(params, customerName, customerEmail, billingAddress);

        HttpResponse response = StripeHttpUtil.doPost('payment_methods', params);
        String body = response.getBody();
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);

        if (cardPaymentMethod.autoPay != true) {
            return buildTokenizationResponse(response);
        }

        String customerId = createCustomer(customerName, customerEmail);
        String paymentMethodId = (String) results.get('id');
        return setupIntentCreation(customerId, 'card', paymentMethodId, tokenizeRequest.ipAddress);
    }

    // Maps POST /v1/payment_methods response to Commerce PaymentMethodTokenizationResponse (token = pm id).
    private commercepayments.GatewayResponse buildTokenizationResponse(HttpResponse response)
    {
        commercepayments.PaymentMethodTokenizationResponse tokenizeResponse =
            new commercepayments.PaymentMethodTokenizationResponse();
        String body = response.getBody();
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);
        Integer sc = response.getStatusCode();
        tokenizeResponse.setGatewayDate(System.now());
        if (sc >= 200 && sc < 300) {
            tokenizeResponse.setGatewayTokenEncrypted((String) results.get('id'));
            tokenizeResponse.setGatewayResultCode('success');
            tokenizeResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
        } else {
            Map<String, Object> error = (Map<String, Object>) results.get('error');
            if (error == null) {
                return new commercepayments.GatewayErrorResponse(String.valueOf(sc), 'ERROR: ' + body);
            }
            String errorType = (String) error.get('type');
            String errorCode = (String) error.get('code');

            if ('card_error'.equals(errorType) && DECLINE_CODES.contains(errorCode)) {
                populateErrorResponse(tokenizeResponse, errorCode, error);
            } else {
                return new commercepayments.GatewayErrorResponse(String.valueOf(sc), 'ERROR: ' + body);
            }
        }
        return tokenizeResponse;
    }

    // Confirms SetupIntent so the saved payment method can be charged off-session (usage=off_session).
    private commercepayments.GatewayResponse setupIntentCreation(
        String customerId,
        String paymentMethodType,
        String paymentMethodId,
        String ipAddress
    )
    {
        commercepayments.PaymentMethodTokenizationResponse tokenizeResponse =
            new commercepayments.PaymentMethodTokenizationResponse();

        Map<String, String> setupIntentParams = new Map<String, String>();
        setupIntentParams.put('confirm', 'true');
        setupIntentParams.put('usage', 'off_session');
        setupIntentParams.put('customer', customerId);
        setupIntentParams.put('payment_method_types[]', paymentMethodType);
        setupIntentParams.put('payment_method', paymentMethodId);

        populateMandateData(setupIntentParams, ipAddress);

        HttpResponse response = StripeHttpUtil.doPost('setup_intents', setupIntentParams);
        String body = response.getBody();
        Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(body);
        Integer sc = response.getStatusCode();
        tokenizeResponse.setGatewayDate(System.now());
        if (sc >= 200 && sc < 300) {
            tokenizeResponse.setGatewayTokenEncrypted((String) results.get('payment_method'));
            tokenizeResponse.setGatewayResultCode('success');
            tokenizeResponse.setCustomerReference((String) results.get('customer'));
            tokenizeResponse.setSalesforceResultCodeInfo(RC_SUCCESS);
        } else {
            return new commercepayments.GatewayErrorResponse(String.valueOf(sc), 'ERROR: ' + body);
        }
        return tokenizeResponse;
    }

    // Stripe Customer id required before SetupIntent when saving payment methods for recurring/off-session.
    private String createCustomer(String customerName, String customerEmail)
    {
        Map<String, String> params = new Map<String, String>();
        params.put('name', customerName);
        params.put('email', customerEmail);
        HttpResponse createCustomerResponse = StripeHttpUtil.doPost('customers', params);
        String responseBody = createCustomerResponse.getBody();
        Map<String, Object> customerResults = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        return (String) customerResults.get('id');
    }

    // -------------------------------------------------------------------------
    // Private helpers — sale APM / wallet types (Commerce paymentMethodData -> Stripe payment_method_types[])
    // -------------------------------------------------------------------------

    // Unwraps extended wallet/APM when Commerce sends extd_* placeholders plus extendedPaymentMethodType.
    private String determinePaymentMethodTypeForSaleFlow(commercepayments.SaleRequest saleRequest)
    {
        String paymentMethodType = saleRequest.paymentMethodData.get('paymentMethodType');
        if (paymentMethodType != null
            && ('extd_wallet'.equals(paymentMethodType) || 'extd_apm_type'.equals(paymentMethodType))
            && saleRequest.paymentMethodData.get('extendedPaymentMethodType') != null) {
            paymentMethodType = saleRequest.paymentMethodData.get('extendedPaymentMethodType');
        }
        return paymentMethodType;
    }

    // Level 2/3 line items and shipping/tax (Stripe amount_details; amounts in minor units per currency rules).
    private void populateEnhancedPaymentData(
        Map<String, String> params,
        commercepayments.EnhancedPaymentDataInput enhancedPaymentData,
        String paymentMethodType,
        String currencyIsoCode
    )
    {
        Integer currencyBasedMultiplier;
        String currencyCodeLc = currencyIsoCode.toLowerCase();
        if (ZERO_DECIMAL_CURRENCY.contains(currencyCodeLc)) {
            currencyBasedMultiplier = 1;
        } else {
            currencyBasedMultiplier = 100;
        }

        if (enhancedPaymentData.referenceId != null) {
            params.put('payment_details[order_reference]', enhancedPaymentData.referenceId);
        }
        if (enhancedPaymentData.shipFromZip != null) {
            params.put('amount_details[shipping][from_postal_code]', enhancedPaymentData.shipFromZip);
        }
        if (enhancedPaymentData.shipToZip != null) {
            params.put('amount_details[shipping][to_postal_code]', enhancedPaymentData.shipToZip);
        }
        if (enhancedPaymentData.totalTaxAmount != null) {
            params.put(
                'amount_details[tax][total_tax_amount]',
                String.valueOf((enhancedPaymentData.totalTaxAmount * currencyBasedMultiplier).intValue())
            );
        }
        if (enhancedPaymentData.shippingAmount != null) {
            params.put(
                'amount_details[shipping][amount]',
                String.valueOf((enhancedPaymentData.shippingAmount * currencyBasedMultiplier).intValue())
            );
        }

        List<commercepayments.LineItemInput> lineItems = enhancedPaymentData.lineItems;
        if (lineItems != null) {
            for (Integer index = 0; index < lineItems.size(); index += 1) {
                commercepayments.LineItemInput lineItem = lineItems.get(index);
                String stripeInputIndex = '[' + index + ']';
                if (lineItem.sku != null) {
                    params.put('amount_details[line_items]' + stripeInputIndex + '[product_code]', lineItem.sku);
                }
                if (lineItem.name != null) {
                    params.put('amount_details[line_items]' + stripeInputIndex + '[product_name]', lineItem.name);
                }
                if (lineItem.quantity != null) {
                    params.put(
                        'amount_details[line_items]' + stripeInputIndex + '[quantity]',
                        String.valueOf(lineItem.quantity)
                    );
                }
                if (lineItem.unitPrice != null) {
                    params.put(
                        'amount_details[line_items]' + stripeInputIndex + '[unit_cost]',
                        String.valueOf((lineItem.unitPrice * currencyBasedMultiplier).intValue())
                    );
                }
                if (lineItem.uom != null) {
                    params.put(
                        'amount_details[line_items]' + stripeInputIndex + '[unit_of_measure]',
                        lineItem.uom
                    );
                }
                if (lineItem.discount != null) {
                    params.put(
                        'amount_details[line_items]' + stripeInputIndex + '[discount_amount]',
                        String.valueOf((lineItem.discount * currencyBasedMultiplier).intValue())
                    );
                }
                if ('card'.equals(paymentMethodType) && lineItem.commodityCode != null) {
                    params.put(
                        'amount_details[line_items]' + stripeInputIndex
                            + '[payment_method_options][card][commodity_code]',
                        lineItem.commodityCode
                    );
                }
            }
        }
        params.put('expand[0]', 'amount_details.line_items');
    }

    // -------------------------------------------------------------------------
    // Private helpers — SOQL gateway token resolution (CardPaymentMethod / SavedPaymentMethod)
    // -------------------------------------------------------------------------

    // Prefer encrypted gateway token when platform encryption stores pm_/token in GatewayTokenEncrypted.
    private String resolveCardToken(String paymentMethodId)
    {
        QueryUtils queryUtils = new QueryUtils(CardPaymentMethod.SObjectType);
        queryUtils.getSelectClause().addField('GatewayToken', false);
        queryUtils.getSelectClause().addField('GatewayTokenEncrypted', false);
        queryUtils.setWhereClause(' WHERE Id = \'' + String.escapeSingleQuotes(paymentMethodId) + '\'');
        CardPaymentMethod cardPaymentMethod = (CardPaymentMethod) Database.query(queryUtils.buildSOQL(),AccessLevel.SYSTEM_MODE)[0];
        return (cardPaymentMethod.GatewayTokenEncrypted != null)
            ? cardPaymentMethod.GatewayTokenEncrypted
            : cardPaymentMethod.GatewayToken;
    }

    // Saved payment method: Stripe pm id or equivalent stored on SPM.GatewayToken.
    private String resolveSPMToken(String paymentMethodId)
    {
        QueryUtils q = new QueryUtils(SavedPaymentMethod.SObjectType);
        q.getSelectClause().addField('GatewayToken', false);
        q.getSelectClause().addField('GatewayReference', false);
        q.getSelectClause().addField('type', false);
        q.setWhereClause(' WHERE Id = \'' + String.escapeSingleQuotes(paymentMethodId) + '\'');
        SavedPaymentMethod savedPaymentMethod = (SavedPaymentMethod) Database.query(q.buildSOQL(), AccessLevel.SYSTEM_MODE)[0];
        return savedPaymentMethod.GatewayToken;
    }

    // -------------------------------------------------------------------------
    // Private helpers — Stripe nested objects on payment_methods / payment_intents (billing, mandate, fraud)
    // -------------------------------------------------------------------------

    private void addBillingDetails(
        Map<String, String> params,
        String customerName,
        String customerEmail,
        commercepayments.AddressRequest billingAddress
    )
    {
        params.put('billing_details[name]', customerName);
        params.put('billing_details[email]', customerEmail);
        if (billingAddress != null) {
            params.put('billing_details[address[line1]]', billingAddress.street);
            params.put('billing_details[address[city]]', billingAddress.city);
            params.put('billing_details[address[state]]', billingAddress.state);
            params.put('billing_details[address[postal_code]]', billingAddress.postalCode);
            params.put('billing_details[address[country]]', billingAddress.country);
        }
    }

    // Customer acceptance for debit/bank methods (online ip/user_agent vs offline).
    private void populateMandateData(Map<String, String> params, String ipAddress)
    {
        if (ipAddress != null) {
            params.put('mandate_data[customer_acceptance][type]', 'online');
            params.put('mandate_data[customer_acceptance][online][ip_address]', ipAddress);
            params.put('mandate_data[customer_acceptance][online][user_agent]', 'SalesforceIntegration/1.0');
        } else {
            params.put('mandate_data[customer_acceptance][type]', 'offline');
        }
    }

    // Shared decline mapping from Stripe error object into Commerce gateway responses.
    private void populateErrorResponse(
        commercepayments.AbstractResponse gatewayResponse,
        String errorCode,
        Map<String, Object> error
    )
    {
        gatewayResponse.setGatewayResultCode(errorCode);
        gatewayResponse.setGatewayResultCodeDescription((String) error.get('decline_code'));
        gatewayResponse.setGatewayMessage((String) error.get('message'));
        gatewayResponse.setSalesforceResultCodeInfo(RC_DECLINE);
    }

    // Radar-like signals passed on payment_method creation when Commerce supplies ip / browser hints.
    private void populateFraudData(
        Map<String, String> params,
        commercepayments.PaymentMethodTokenizationRequest tokenizeRequest
    )
    {
        if (tokenizeRequest.ipAddress != null) {
            params.put('ip', tokenizeRequest.ipAddress);
        }
        Map<String, String> additionalData = tokenizeRequest.additionalData;
        if (additionalData != null) {
            params.put('referrer', StripeHttpUtil.urlEncode(additionalData.get('referrer')));
            params.put('user_agent', StripeHttpUtil.urlEncode(additionalData.get('user_agent')));
            params.put('payment_user_agent', StripeHttpUtil.urlEncode(additionalData.get('payment_user_agent')));
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers — currency (Salesforce major units <-> Stripe minor units)
    // -------------------------------------------------------------------------

    private static String toStripeCurrencyUnits(String currencyIsoCode, Double amount)
    {
        String currencyCodeLc = currencyIsoCode.toLowerCase();
        Decimal decimalScaledAmount = Decimal.valueOf(amount).setScale(2);

        if (ZERO_DECIMAL_CURRENCY.contains(currencyCodeLc)) {
            return String.valueOf(amount.intValue());
        } else if ('huf'.equals(currencyCodeLc)) {
            return String.valueOf((decimalScaledAmount * 100).intValue());
        }

        return String.valueOf((decimalScaledAmount * 100).intValue());
    }

    private static Double fromStripeCurrencyUnits(String currencyIsoCode, Long amount)
    {
        if (amount == null) {
            return null;
        }
        if (ZERO_DECIMAL_CURRENCY.contains(currencyIsoCode.toLowerCase())) {
            return Decimal.valueOf(amount).doubleValue();
        }
        return (Decimal.valueOf(amount) / 100).doubleValue();
    }

    /** Apex wrapper for Commerce enum codes (referenced by static RC_* fields). */
    private static commercepayments.SalesforceResultCodeInfo toCodeInfo(commercepayments.SalesforceResultCode code)
    {
        return new commercepayments.SalesforceResultCodeInfo(code);
    }
}
